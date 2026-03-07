#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# CONFIG
###############################################################################

TEST_SCRIPT="${TEST_SCRIPT:-$ARG3/test/h200/test_script_poc_h200.sh}"


TARGET_GPUS=4

###############################################################################

DATASET_DIR="$ARG1"
UNIQUE_NAME="$ARG2"
WD="$ARG3"
AA_or_DNA="$ARG4"
GPU_TYPE="$ARG5"
length="$ARG6"
TYPE="$ARG7"

###############################################################################
# CHECKS
###############################################################################
die() { echo "ERROR: $*" >&2; exit 1; }

command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi not found. Are you on a GPU node?"

[[ -f "$TEST_SCRIPT" ]] || die "TEST_SCRIPT not found: $TEST_SCRIPT"
# Not required to be executable since we run with bash, but nice to know:
[[ -x "$TEST_SCRIPT" ]] || echo "NOTE: $TEST_SCRIPT is not executable; running with 'bash' anyway."

# Detect how many GPUs are visible
GPU_COUNT="$(nvidia-smi -L 2>/dev/null | wc -l | tr -d ' ')"
[[ "$GPU_COUNT" =~ ^[0-9]+$ ]] || die "Could not parse GPU count"
(( GPU_COUNT >= 1 )) || die "No GPUs detected"

# Use up to TARGET_GPUS, but not more than visible
USE_GPUS="$GPU_COUNT"
if (( USE_GPUS > TARGET_GPUS )); then USE_GPUS="$TARGET_GPUS"; fi

# Prevent CPU thread oversubscription when one process runs on each GPU.
if [[ -n "${PBS_NCPUS:-}" ]] && [[ "${PBS_NCPUS}" =~ ^[0-9]+$ ]] && (( PBS_NCPUS > 0 )); then
  CPU_THREADS_PER_WORKER=$(( PBS_NCPUS / USE_GPUS ))
  if (( CPU_THREADS_PER_WORKER < 1 )); then
    CPU_THREADS_PER_WORKER=1
  fi
else
  CPU_THREADS_PER_WORKER=1
fi

# Stage dataset to node-local storage if available to reduce shared FS contention.
RUN_DATASET_DIR="$DATASET_DIR"
if [[ -n "${PBS_JOBFS:-}" ]] && [[ -d "${PBS_JOBFS}" ]]; then
  LOCAL_DATASET_DIR="${PBS_JOBFS}/dataset_local"
  rm -rf "$LOCAL_DATASET_DIR"
  mkdir -p "$LOCAL_DATASET_DIR"
  cp -a "${DATASET_DIR}/." "$LOCAL_DATASET_DIR"/
  RUN_DATASET_DIR="$LOCAL_DATASET_DIR"
fi

# Logs
TS="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$WD/gpu_parallel_runs_$TS"
mkdir -p "$LOG_DIR" || die "Failed to create log dir: $LOG_DIR"

echo "Visible GPUs  : $GPU_COUNT"
echo "Using GPUs    : $USE_GPUS (0..$((USE_GPUS-1)))"
echo "Threads/worker: $CPU_THREADS_PER_WORKER"
echo "Test script   : $TEST_SCRIPT"
echo "Dataset dir   : $RUN_DATASET_DIR"
echo "Log directory : $LOG_DIR"
echo

###############################################################################
# RUN ONE PROCESS PER GPU
###############################################################################
pids=()
for ((gpu=0; gpu<USE_GPUS; gpu++)); do
  (
    export CUDA_VISIBLE_DEVICES="$gpu"
    export GPU_ID="$gpu"
    export CUDA_DEVICE_ORDER=PCI_BUS_ID
    export OMP_NUM_THREADS="$CPU_THREADS_PER_WORKER"
    export MKL_NUM_THREADS=1
    export OPENBLAS_NUM_THREADS=1
    export NUMEXPR_NUM_THREADS=1

    UNIQUE_NAME_LOC="${UNIQUE_NAME}_gpu${gpu}"
    LOG_FILE="$LOG_DIR/gpu_${gpu}.log"
    CPU_PIN_CMD=""
    if command -v taskset >/dev/null 2>&1; then
      core_start=$(( gpu * CPU_THREADS_PER_WORKER ))
      core_end=$(( core_start + CPU_THREADS_PER_WORKER - 1 ))
      CPU_PIN_CMD="taskset -c ${core_start}-${core_end}"
    fi

    {
      echo "=============================="
      echo "[GPU $gpu] Host: $(hostname)"
      echo "[GPU $gpu] Start: $(date)"
      echo "[GPU $gpu] CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
      echo "[GPU $gpu] OMP_NUM_THREADS=$OMP_NUM_THREADS"
      if [[ -n "$CPU_PIN_CMD" ]]; then echo "[GPU $gpu] CPU pinning=$CPU_PIN_CMD"; fi
      echo "[GPU $gpu] UNIQUE_NAME_LOC=$UNIQUE_NAME_LOC"
      echo "=============================="
      echo
    } >>"$LOG_FILE"

    START_NS="$(date +%s%N)"

    # Important: don't let 'set -e' kill the worker before we log RC/time
    set +e
    if [[ -n "$CPU_PIN_CMD" ]]; then
      $CPU_PIN_CMD bash "$TEST_SCRIPT" \
        "$RUN_DATASET_DIR" \
        "$UNIQUE_NAME_LOC" \
        "$WD" \
        "$AA_or_DNA" \
        "$GPU_TYPE" \
        "$length" \
        "$TYPE" \
        >>"$LOG_FILE" 2>&1
    else
      bash "$TEST_SCRIPT" \
        "$RUN_DATASET_DIR" \
        "$UNIQUE_NAME_LOC" \
        "$WD" \
        "$AA_or_DNA" \
        "$GPU_TYPE" \
        "$length" \
        "$TYPE" \
        >>"$LOG_FILE" 2>&1
    fi
    RC=$?
    set -e

    END_NS="$(date +%s%N)"
    ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))

    {
      echo
      echo "=============================="
      echo "[GPU $gpu] End: $(date)"
      echo "[GPU $gpu] Exit code: $RC"
      echo "[GPU $gpu] Elapsed ms: $ELAPSED_MS"
      echo "=============================="
    } >>"$LOG_FILE"

    exit "$RC"
  ) &

  pids+=("$!")
done

###############################################################################
# WAIT + FINAL STATUS
###############################################################################
FAIL=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    FAIL=1
  fi
done

echo
if (( FAIL != 0 )); then
  echo "One or more GPU runs FAILED."
  echo "See logs in: $LOG_DIR"
  exit 1
fi

echo "All GPU runs completed successfully."
echo "Logs: $LOG_DIR"
