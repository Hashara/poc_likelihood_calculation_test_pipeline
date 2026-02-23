#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# CONFIG
###############################################################################

TEST_SCRIPT="${TEST_SCRIPT:-./test_poc.sh}"   # override by exporting TEST_SCRIPT if you want


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

# Logs
TS="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$WD/gpu_parallel_runs_$TS"
mkdir -p "$LOG_DIR" || die "Failed to create log dir: $LOG_DIR"

echo "Visible GPUs  : $GPU_COUNT"
echo "Using GPUs    : $USE_GPUS (0..$((USE_GPUS-1)))"
echo "Test script   : $TEST_SCRIPT"
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

    UNIQUE_NAME_LOC="${UNIQUE_NAME}_gpu${gpu}"
    LOG_FILE="$LOG_DIR/gpu_${gpu}.log"

    {
      echo "=============================="
      echo "[GPU $gpu] Host: $(hostname)"
      echo "[GPU $gpu] Start: $(date)"
      echo "[GPU $gpu] CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
      echo "[GPU $gpu] UNIQUE_NAME_LOC=$UNIQUE_NAME_LOC"
      echo "=============================="
      echo
    } >>"$LOG_FILE"

    START_NS="$(date +%s%N)"

    # Important: don't let 'set -e' kill the worker before we log RC/time
    set +e
    bash "$TEST_SCRIPT" \
      "$DATASET_DIR" \
      "$UNIQUE_NAME_LOC" \
      "$WD" \
      "$AA_or_DNA" \
      "$GPU_TYPE" \
      "$length" \
      "$TYPE" \
      >>"$LOG_FILE" 2>&1
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
