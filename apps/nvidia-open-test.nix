# Trial of NVIDIA's open kernel module (hardware.nvidia.open) against the
# proprietary one this machine normally runs. Procedure: docs/NVIDIA-OPEN-TEST.md.
#
#   - "nvidia-open" specialisation: identical system, only open = true. Boot it
#     from the boot menu (hold Space at power-on), so the default entry stays
#     on the known-good proprietary module.
#   - `gpu-driver-test`: run once on each boot entry; it records idle power
#     (incl. whether the dGPU actually powers off: RTD3 / finegrained), load
#     power, CUDA from Python (PyTorch), OpenGL/Vulkan offload and optionally
#     a suspend/resume cycle, into ~/gpu-driver-test/. `gpu-driver-test
#     --compare` puts the summaries of all runs side by side.
#
# Once decided: either drop this file + its import (stay proprietary), or set
# hardware.nvidia.open = true in nvidia.nix and drop this file.
{ config, lib, pkgs, ... }:
let
  # "PCI:1:0:0" (decimal, as nvidia.nix wants it) -> sysfs "0000:01:00.0"
  pciAddr =
    let
      p = map lib.toInt (lib.tail (lib.splitString ":" config.hardware.nvidia.prime.nvidiaBusId));
      hex = w: n: lib.fixedWidthString w "0" (lib.toLower (lib.toHexString n));
    in
    "0000:${hex 2 (lib.elemAt p 0)}:${hex 2 (lib.elemAt p 1)}.${hex 1 (lib.elemAt p 2)}";

  # Python + prebuilt CUDA PyTorch from this system's own nixpkgs, built on
  # first use only (it is ~3 GB, so it is not part of the system closure).
  pythonExpr = ''
    let p = import ${pkgs.path} { system = "${pkgs.stdenv.hostPlatform.system}"; config.allowUnfree = true; };
    in p.python3.withPackages (ps: [ ps.torch-bin ])
  '';

  torchTest = pkgs.writeText "gpu-driver-test.py" ''
    import sys, time
    import torch

    secs = float(sys.argv[1])
    print(f"torch {torch.__version__}, built for CUDA {torch.version.cuda}")
    if not torch.cuda.is_available():
        print("SUMMARY cuda=FAIL (torch.cuda.is_available() is False)")
        sys.exit(1)
    dev = torch.device("cuda")
    print("device:", torch.cuda.get_device_name(0))

    # Correctness: the GPU result must match the CPU one.
    a = torch.randn(512, 512)
    b = torch.randn(512, 512)
    err = ((a.to(dev) @ b.to(dev)).cpu() - a @ b).abs().max().item()
    ok = err < 1e-2
    print(f"matmul max abs error vs CPU: {err:.2e} ({'ok' if ok else 'WRONG'})")

    # Sustained load for the power measurement.
    n = 2048
    x = torch.randn(n, n, device=dev)
    y = torch.randn(n, n, device=dev)
    torch.cuda.synchronize()
    t0 = time.time()
    it = 0
    while time.time() - t0 < secs:
        for _ in range(10):
            x @ y
        torch.cuda.synchronize()
        it += 10
    el = time.time() - t0
    tflops = 2 * n**3 * it / el / 1e12
    print(f"fp32 matmul: {tflops:.2f} TFLOPS over {el:.0f}s")
    print(f"SUMMARY cuda={'ok' if ok else 'WRONG'} tflops={tflops:.2f}")
    sys.exit(0 if ok else 1)
  '';

  gpuDriverTest = pkgs.writeShellApplication {
    name = "gpu-driver-test";
    runtimeInputs = with pkgs; [ coreutils gawk gnugrep gnused psmisc mesa-demos vulkan-tools util-linux ];
    text = ''
      IDLE_SECS=''${IDLE_SECS:-180}
      LOAD_SECS=''${LOAD_SECS:-60}
      outdir="$HOME/gpu-driver-test"
      gpu=/sys/bus/pci/devices/${pciAddr}

      usage() {
        cat <<EOF
      usage: gpu-driver-test [--suspend] [--skip-idle]   run the test, log to $outdir
             gpu-driver-test --compare                   summaries of all runs
      env:   IDLE_SECS (default 180), LOAD_SECS (default 60),
             GPU_TEST_PYTHON=/path/to/python  test your own Python/venv instead
      EOF
        exit 2
      }

      do_suspend=0 skip_idle=0
      for a in "$@"; do
        case "$a" in
          --suspend) do_suspend=1 ;;
          --skip-idle) skip_idle=1 ;;
          --compare)
            shopt -s nullglob
            for f in "$outdir"/*.log; do
              echo "== $(basename "$f")"
              grep '^SUMMARY' "$f" | sed 's/^SUMMARY /   /' || true
            done
            exit 0
            ;;
          *) usage ;;
        esac
      done

      if [ ! -r /proc/driver/nvidia/version ]; then
        echo "NVIDIA driver not loaded." >&2; exit 1
      fi
      if grep -q "Open Kernel Module" /proc/driver/nvidia/version; then flavor=open; else flavor=proprietary; fi
      mkdir -p "$outdir"
      log="$outdir/$flavor-$(date +%Y%m%d-%H%M%S).log"
      exec > >(tee "$log") 2>&1

      # Battery draw in watts (empty when there is no reading).
      battery_w() {
        local b
        for b in /sys/class/power_supply/BAT*; do
          if [ -r "$b/power_now" ]; then
            awk '{ printf "%.2f", $1 / 1e6 }' "$b/power_now"; return
          elif [ -r "$b/current_now" ] && [ -r "$b/voltage_now" ]; then
            awk -v v="$(cat "$b/voltage_now")" '{ printf "%.2f", $1 * v / 1e12 }' "$b/current_now"; return
          fi
        done
      }
      on_ac() { grep -qs 1 /sys/class/power_supply/{AC,ADP}*/online; }
      avg() { awk 'NF { s += $1; n++ } END { if (n) printf "%.2f", s / n; else print "n/a" }'; }

      echo "gpu-driver-test, $(date)"
      echo "SUMMARY flavor=$flavor"
      head -n 1 /proc/driver/nvidia/version
      echo "kernel $(uname -r), system $(readlink -f /run/current-system)"
      if on_ac; then
        echo "WARNING: on AC power - battery watt figures below are meaningless."
        echo "         Unplug the charger for the power comparison."
        echo "SUMMARY power_source=AC"
      else
        echo "SUMMARY power_source=battery"
      fi

      # ---- 1. idle: does the dGPU power off (RTD3), and what does it cost? --
      # Nothing in this phase may touch the GPU: even nvidia-smi wakes it.
      if [ "$skip_idle" = 0 ]; then
        echo
        echo "== Idle ($IDLE_SECS s). Leave the machine alone; close GPU apps."
        echo "Processes holding /dev/nvidia* (these keep the dGPU awake):"
        fuser -v /dev/nvidia* 2>&1 | sed 's/^/   /' || true
        sleep 10   # let it settle into runtime suspend
        s0=$(cat "$gpu/power/runtime_suspended_time") a0=$(cat "$gpu/power/runtime_active_time")
        samples=()
        end=$(( $(date +%s) + IDLE_SECS ))
        while [ "$(date +%s)" -lt "$end" ]; do
          w=$(battery_w); [ -n "$w" ] && samples+=("$w")
          sleep 5
        done
        s1=$(cat "$gpu/power/runtime_suspended_time") a1=$(cat "$gpu/power/runtime_active_time")
        ds=$(( s1 - s0 )) da=$(( a1 - a0 ))
        pct=$(( (ds + da) > 0 ? 100 * ds / (ds + da) : 0 ))
        idle_w=$(printf '%s\n' "''${samples[@]}" | avg)
        echo "dGPU runtime-suspended ''${pct}% of the time (status now: $(cat "$gpu/power/runtime_status"))"
        echo "average battery draw: $idle_w W"
        echo "SUMMARY idle_dgpu_suspended_pct=$pct idle_battery_w=$idle_w"
      fi

      # ---- 2. driver basics ------------------------------------------------
      echo
      echo "== nvidia-smi"
      nvidia-smi --query-gpu=name,driver_version,pstate,temperature.gpu,power.draw --format=csv || echo "nvidia-smi FAILED"

      # ---- 3. CUDA from Python under load ----------------------------------
      echo
      echo "== CUDA / PyTorch ($LOAD_SECS s load)"
      py=''${GPU_TEST_PYTHON:-}
      if [ -z "$py" ]; then
        echo "building Python + torch-bin (first run downloads ~3 GB) ..."
        env=$(nix build --no-link --print-out-paths --impure --expr ${lib.escapeShellArg pythonExpr})
        py="$env/bin/python3"
      fi
      "$py" ${torchTest} "$LOAD_SECS" &
      pypid=$!
      bat=() gpuw=()
      sleep 5
      while kill -0 "$pypid" 2>/dev/null; do
        w=$(battery_w); [ -n "$w" ] && bat+=("$w")
        g=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | grep -E '^[0-9.]+$' || true)
        [ -n "$g" ] && gpuw+=("$g")
        sleep 3
      done
      if wait "$pypid"; then cuda_rc=ok; else cuda_rc=FAIL; fi
      load_bat=$(printf '%s\n' "''${bat[@]}" | avg)
      load_gpu=$(printf '%s\n' "''${gpuw[@]}" | avg)
      echo "under load: battery $load_bat W, GPU (nvidia-smi) $load_gpu W"
      echo "SUMMARY cuda_exit=$cuda_rc load_battery_w=$load_bat load_gpu_w=$load_gpu"

      # ---- 4. graphics offload ---------------------------------------------
      echo
      echo "== OpenGL / Vulkan via nvidia-offload"
      gl=$(nvidia-offload glxinfo -B 2>&1 | grep -m1 'OpenGL renderer' || echo "glxinfo FAILED")
      vk=$(nvidia-offload vulkaninfo --summary 2>&1 | grep -m1 -i 'deviceName.*nvidia' || echo "no NVIDIA Vulkan device")
      echo "$gl"; echo "$vk"
      gl_ok=FAIL vk_ok=FAIL
      if grep -qi nvidia <<<"$gl"; then gl_ok=ok; fi
      if grep -qi nvidia <<<"$vk"; then vk_ok=ok; fi
      echo "SUMMARY gl=$gl_ok vulkan=$vk_ok"

      # ---- 5. optional suspend / resume ------------------------------------
      if [ "$do_suspend" = 1 ]; then
        echo
        echo "== Suspend/resume: suspending for ~40 s (RTC alarm wakes it) ..."
        # Through systemd (not rtcwake -m mem), so nvidia-suspend/-resume run
        # exactly as on a real lid close. Ignores stay-awake's inhibitor.
        sudo rtcwake -m no -s 40
        sudo systemctl suspend --check-inhibitors=no
        sleep 50
        echo "resumed: $(date)"
        if nvidia-smi -L >/dev/null 2>&1 && "$py" -c 'import torch; assert torch.cuda.is_available(); print((torch.ones(4, device="cuda") * 2).sum().item())'; then
          resume=ok
        else
          resume=FAIL
        fi
        journalctl -b -k --since "-2min" | grep -iE 'nvrm|nvidia' | tail -n 20 || true
        echo "SUMMARY resume=$resume"
      fi

      echo
      echo "Log: $log"
    '';
  };
in
{
  specialisation."nvidia-open".configuration = {
    system.nixos.tags = [ "nvidia-open" ];
    hardware.nvidia.open = lib.mkForce true;
  };

  environment.systemPackages = [ gpuDriverTest ];
}
