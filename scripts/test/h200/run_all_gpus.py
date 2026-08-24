#!/usr/bin/env python3
import os
import sys
import shlex
import subprocess
from pathlib import Path
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed


def die(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)


def run(cmd, *, env, log_path: Path) -> int:
    """
    Run a command, stream stdout/stderr to a log file, return exit code.
    """
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write("========================================\n")
        f.write(f"Host: {os.uname().nodename}\n")
        f.write(f"Start: {datetime.now().isoformat(sep=' ', timespec='seconds')}\n")
        f.write(f"CMD: {' '.join(shlex.quote(c) for c in cmd)}\n")
        f.write(f"CUDA_VISIBLE_DEVICES={env.get('CUDA_VISIBLE_DEVICES','')}\n")
        f.write("========================================\n\n")
        f.flush()

        proc = subprocess.Popen(
            cmd,
            stdout=f,
            stderr=subprocess.STDOUT,
            env=env,
            text=True,
        )
        rc = proc.wait()

        f.write("\n========================================\n")
        f.write(f"End: {datetime.now().isoformat(sep=' ', timespec='seconds')}\n")
        f.write(f"Exit code: {rc}\n")
        f.write("========================================\n")
        f.flush()

    return rc


def detect_gpu_count() -> int:
    try:
        out = subprocess.check_output(["nvidia-smi", "-L"], text=True, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        die("nvidia-smi not found. Are you on a GPU node?")
    except subprocess.CalledProcessError as e:
        die(f"nvidia-smi failed: {e}")

    lines = [ln for ln in out.splitlines() if ln.strip()]
    return len(lines)


def main() -> None:
    # Usage:
    #   python3 run_on_all_gpus.py /path/to/test_poc.sh DATASET_DIR UNIQUE_NAME WD AA_or_DNA GPU_TYPE length TYPE
    #
    # Example:
    #   python3 run_on_all_gpus.py ./test_poc.sh "$DATASET_DIR" "$UNIQUE_NAME" "$WD" "$AA_or_DNA" "$GPU_TYPE" "$length" "$TYPE"
    if len(sys.argv) < 9:
        die(
            "Usage: run_on_all_gpus.py TEST_SCRIPT DATASET_DIR UNIQUE_NAME WD AA_or_DNA GPU_TYPE length TYPE\n"
            "Example: run_on_all_gpus.py ./test_poc.sh /data myrun /work AA H200 1000000 bench"
        )

    test_script = Path(sys.argv[1]).expanduser().resolve()
    dataset_dir = sys.argv[2]
    unique_name = sys.argv[3]
    wd = Path(sys.argv[4]).expanduser().resolve()
    aa_or_dna = sys.argv[5]
    gpu_type = sys.argv[6]
    length = sys.argv[7]
    run_type = sys.argv[8]

    if not test_script.exists():
        die(f"TEST_SCRIPT not found: {test_script}")

    gpu_count = detect_gpu_count()
    if gpu_count < 1:
        die("No GPUs detected")

    target_gpus = int(os.environ.get("TARGET_GPUS", "4"))
    use_gpus = min(gpu_count, target_gpus)

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_dir = wd / f"gpu_parallel_runs_{ts}"
    log_dir.mkdir(parents=True, exist_ok=True)

    print(f"Visible GPUs : {gpu_count}")
    print(f"Using GPUs   : {use_gpus} (0..{use_gpus-1})")
    print(f"Test script  : {test_script}")
    print(f"Logs         : {log_dir}")
    print()

    # IMPORTANT NOTE:
    # If your underlying binary uses cudaSetDevice(0) internally,
    # this is STILL OK because with CUDA_VISIBLE_DEVICES set to one GPU,
    # that GPU is device 0 inside the process.
    #
    # If you had been exporting GPU_ID=gpu and using it inside the app,
    # that can cause problems. Here we do NOT pass GPU_ID by default.
    base_cmd = [
        "bash",
        str(test_script),
        dataset_dir,
        "",  # placeholder for UNIQUE_NAME_LOC
        str(wd),
        aa_or_dna,
        gpu_type,
        length,
        run_type,
    ]

    def launch_one(gpu: int) -> tuple[int, int, Path]:
        env = os.environ.copy()
        env["CUDA_VISIBLE_DEVICES"] = str(gpu)

        # Optional: reduce incidental CPU-threading from libraries even if you don't use OpenMP
        env.setdefault("OMP_NUM_THREADS", "1")
        env.setdefault("MKL_NUM_THREADS", "1")
        env.setdefault("OPENBLAS_NUM_THREADS", "1")
        env.setdefault("NUMEXPR_NUM_THREADS", "1")
        env.setdefault("VECLIB_MAXIMUM_THREADS", "1")

        unique_loc = f"{unique_name}_gpu{gpu}"
        cmd = base_cmd.copy()
        cmd[4] = unique_loc  # fill UNIQUE_NAME_LOC

        log_path = log_dir / f"gpu_{gpu}.log"

        # Optional: stage dataset to local scratch to avoid filesystem contention
        # tmp_root = Path(env.get("TMPDIR", "/tmp")) / env.get("USER", "user")
        # local_dataset = tmp_root / unique_loc / "dataset"
        # local_dataset.parent.mkdir(parents=True, exist_ok=True)
        # subprocess.check_call(["rsync", "-a", f"{dataset_dir}/", str(local_dataset) + "/"])
        # cmd[3] = str(local_dataset)  # replace DATASET_DIR in cmd

        rc = run(cmd, env=env, log_path=log_path)
        return gpu, rc, log_path

    failures = 0
    with ThreadPoolExecutor(max_workers=use_gpus) as ex:
        futures = [ex.submit(launch_one, gpu) for gpu in range(use_gpus)]
        for fut in as_completed(futures):
            gpu, rc, log_path = fut.result()
            if rc != 0:
                failures += 1
                print(f"!! GPU {gpu} FAILED (rc={rc}) log={log_path}")
            else:
                print(f"OK GPU {gpu} finished log={log_path}")

    print()
    if failures:
        die(f"{failures} GPU run(s) failed. See logs: {log_dir}", code=1)

    print(f"All GPU runs completed successfully. Logs: {log_dir}")


if __name__ == "__main__":
    main()