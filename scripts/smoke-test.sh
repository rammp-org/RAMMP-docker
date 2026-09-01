#!/usr/bin/env bash
# Verify a built RAMMP image.
#
#   ./scripts/smoke-test.sh                    # defaults to rammp-cuda:1.0.0-jp6
#   ./scripts/smoke-test.sh rammp-base:1.0.0-jp6
#   ./scripts/smoke-test.sh ghcr.io/rammp-org/rammp-cuda:1.0.0-jp6
#
# One script, two environments. It detects whether the image carries the CUDA
# stack and whether the host can actually run GPU work, then tests accordingly:
# on a GPU-less CI runner the GPU section is skipped, on the Jetson it runs.
# So CI and the robot exercise the same checks and there is only one file to
# keep in step.
#
# Orin NX vs AGX Orin: both are Tegra234 at compute capability sm_87, so a pass
# on an NX carries to an AGX for everything here. It does NOT carry for
# serialized TensorRT engines (device-specific, must be rebuilt) or for
# anything memory-bound -- the NX has far less RAM and is the stricter test.
set -uo pipefail

IMAGE="${1:-rammp-cuda:1.0.0-jp6}"
PASS=0; FAIL=0; SKIP=0

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; PASS=$((PASS+1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
check() { local n="$1"; shift; if out=$("$@" 2>&1); then pass "$n" "$out"; else fail "$n" "$out"; fi; }

run()     { docker run --rm "$IMAGE" "$@"; }
gpu_run() { docker run --rm --runtime nvidia "$IMAGE" "$@"; }

echo "== smoke test: $IMAGE =="

# ── what are we testing, and where? ──────────────────────────────────────────
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "no such image: $IMAGE" >&2; exit 1; }
# Detected via find_spec, which locates the package WITHOUT loading its
# shared libraries: if torch is installed but broken, the checks below must
# FAIL loudly, not silently reclassify the image as a base image.
HAS_CUDA=false
run python3 -c 'import importlib.util,sys; sys.exit(0 if importlib.util.find_spec("torch") else 1)' \
    >/dev/null 2>&1 && HAS_CUDA=true
HAS_GPU=false
if [ -f /etc/nv_tegra_release ] && docker info 2>/dev/null | grep -qi 'runtimes:.*nvidia'; then
    HAS_GPU=true
fi
echo "   image: $([ "$HAS_CUDA" = true ] && echo 'CUDA stack present' || echo 'base (no CUDA)')"
echo "   host : $([ "$HAS_GPU" = true ] && head -1 /etc/nv_tegra_release || echo 'no Jetson GPU -- GPU checks will be skipped')"

echo
echo "-- image + ROS 2 --"
check "image is linux/arm64" bash -c \
    '[ "$(docker image inspect --format "{{.Os}}/{{.Architecture}}" "'"$IMAGE"'")" = "linux/arm64" ]'
check "Cyclone is the selected middleware" run bash -c \
    '[ "$RMW_IMPLEMENTATION" = rmw_cyclonedds_cpp ] && ls /opt/ros/humble/lib/librmw_cyclonedds_cpp.so* >/dev/null && echo rmw_cyclonedds_cpp'
check "CYCLONEDDS_URI points at a real file" run bash -c 'test -f "${CYCLONEDDS_URI#file://}"'
check "workspace overlay auto-sourced, build/ pruned" run bash -c \
    'echo "$AMENT_PREFIX_PATH" | grep -q /ros2_ws/install && test -d /ros2_ws/install && test ! -d /ros2_ws/build && echo ok'

echo
echo "-- RAMMP-interfaces contract --"
# Resolving every type is the point of the base image: if one is missing, a
# module built FROM here fails at runtime rather than at build time.
MISSING=""
for t in arm_interfaces/srv/SetMode arm_interfaces/srv/SetSpeedPreset \
         arm_interfaces/srv/GetSpeedPreset arm_interfaces/srv/CheckReachability \
         arm_interfaces/action/ReachPreset arm_interfaces/action/ExecuteTrajectory \
         arm_interfaces/action/Calibrate \
         rammp_prototype_interfaces/action/Calibration \
         rammp_prototype_interfaces/action/CurbTraverse \
         rammp_prototype_interfaces/msg/RAMMPPrototypeState \
         rammp_prototype_interfaces/msg/SeatCommand; do
    run ros2 interface show "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
[ -z "$MISSING" ] && pass "all 11 interface types resolve" \
                  || fail "interface types missing:" "$MISSING"
check "types import from Python" run python3 -c \
    'from arm_interfaces.srv import SetMode
from rammp_prototype_interfaces.msg import RAMMPPrototypeState
print("ok")'

if [ "$HAS_CUDA" = true ]; then
    echo
    echo "-- CUDA stack (no GPU needed) --"
    check "torch is a CUDA build" run python3 -c \
        'import torch, torchvision
assert torch.version.cuda, "torch has no CUDA support -- wrong wheel index?"
print(f"torch {torch.__version__} / torchvision {torchvision.__version__} / CUDA {torch.version.cuda} / cuDNN {torch.backends.cudnn.version()}")'
    check "CUDA runtime libraries resolve via ldconfig" run bash -c \
        'ldconfig -p | grep -q libcudart && echo ok'
    # The driver must come from the container runtime. One baked into the image
    # would collide with the host's and break CUDA in confusing ways.
    check "no driver baked into the image" run bash -c \
        '! ls /usr/local/cuda/lib64/libcuda.so.1 >/dev/null 2>&1 && echo ok'
    # ...but the runtime only injects that driver if the image ASKS: its hook
    # keys off NVIDIA_VISIBLE_DEVICES, not off --runtime nvidia alone. Checked
    # here because it needs no GPU -- CI catches a missing env before the
    # Jetson ever sees the image.
    check "image requests driver injection (NVIDIA_VISIBLE_DEVICES)" run bash -c \
        '[ -n "$NVIDIA_VISIBLE_DEVICES" ] && echo "NVIDIA_VISIBLE_DEVICES=$NVIDIA_VISIBLE_DEVICES"'

    echo
    echo "-- GPU execution (Jetson only) --"
    if [ "$HAS_GPU" = true ]; then
        # The image needs the host to inject a CUDA 12.6-era driver, i.e. L4T
        # r36.4+ (JetPack 6.1+). A JetPack 6.0 host (r36.2/r36.3) fails all
        # the torch checks below with misleading errors -- diagnose it here.
        l4t_major=$(sed -n 's/^# R\([0-9]*\).*/\1/p' /etc/nv_tegra_release)
        l4t_rev=$(sed -n 's/.*REVISION: \([0-9]*\).*/\1/p' /etc/nv_tegra_release)
        if [ "${l4t_major:-0}" -lt 36 ] || { [ "${l4t_major:-0}" -eq 36 ] && [ "${l4t_rev:-0}" -lt 4 ]; }; then
            fail "host L4T r${l4t_major:-?}.${l4t_rev:-?} is too old for this image" \
                 "CUDA 12.6 needs L4T r36.4+ (JetPack 6.1+); upgrade JetPack on this host"
        else
            pass "host L4T r${l4t_major}.${l4t_rev} supports CUDA 12.6 (r36.4+ required)"
        fi
        check "torch.cuda.is_available()" gpu_run python3 -c \
            'import torch
assert torch.cuda.is_available(), "CUDA unavailable -- was --runtime nvidia used?"
print("device:", torch.cuda.get_device_name(0))'
        check "GPU reports sm_87 (Orin)" gpu_run python3 -c \
            'import torch
cc = torch.cuda.get_device_capability(0)
assert cc == (8, 7), f"expected sm_87, got sm_{cc[0]}{cc[1]}"
print("sm_87 confirmed")'
        check "matmul and cuDNN convolution execute on GPU" gpu_run python3 -c \
            'import torch, torch.nn as nn
a = torch.randn(512, 512, device="cuda")
s = (a @ a).sum().item(); torch.cuda.synchronize()
c = nn.Conv2d(3, 8, 3).cuda()(torch.randn(1, 3, 64, 64, device="cuda"))
print("matmul ok, conv out", tuple(c.shape))'
    else
        skip "GPU execution -- not a Jetson, or nvidia runtime not configured"
    fi
fi

echo
echo "-- DDS discovery between containers --"
# The most common ROS-in-Docker failure, and it needs a real network: on a
# bridge network Cyclone binds the bridge and containers never see each other.
if docker run -d --rm --name rammp_smoke_pub --network host --ipc host "$IMAGE" \
     ros2 topic pub -r 2 /rammp_smoke rammp_prototype_interfaces/msg/SeatCommand '{command: 3}' \
     >/dev/null 2>&1; then
    sleep 5
    check "subscriber receives from another container" \
        docker run --rm --network host --ipc host "$IMAGE" \
            timeout 12 ros2 topic echo --once /rammp_smoke rammp_prototype_interfaces/msg/SeatCommand
    docker stop rammp_smoke_pub >/dev/null 2>&1
else
    fail "could not start publisher container"
fi

echo
echo "== $PASS passed, $FAIL failed, $SKIP skipped =="
if [ "$FAIL" -eq 0 ] && [ "$HAS_GPU" = true ]; then
    echo "Image is good on this hardware. When moving Orin NX -> AGX Orin:"
    echo "  - rebuild any serialized TensorRT engines (not portable between modules)"
    echo "  - revisit --device flags: the carrier board changes serial/GPIO/CSI mapping"
fi
[ "$FAIL" -eq 0 ]
