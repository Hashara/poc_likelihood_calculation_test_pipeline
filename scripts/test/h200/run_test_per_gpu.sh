#!/usr/bin/env bash
set -euo pipefail

DATASET_DIR=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
AA_or_DNA=$ARG4
GPU_TYPE=$ARG5

length=$ARG6
TYPE=$ARG7


TEST_SCRIPT="$WD"/test/h200/test_script_poc_h200.sh

# Logs directory
LOG_DIR=""$WD"/test/h200/gpu_runs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

# Check NVIDIA visibility
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi not found. Are you on a GPU node?"
  exit 1
fi

# Detect GPUs
GPU_COUNT=$(nvidia-smi -L | wc -l | tr -d ' ')
if [[ "$GPU_COUNT" -lt 1 ]]; then
  echo "ERROR: No GPUs detected."
  exit 1
fi

echo "Detected $GPU_COUNT GPU(s)"
echo "Running test_poc.sh once per GPU in parallel..."
echo "Logs will be stored in: $LOG_DIR"
echo

pids=()

for ((gpu=0; gpu<GPU_COUNT; gpu++)); do
  (
    export CUDA_VISIBLE_DEVICES=$gpu
    export GPU_ID=$gpu
    export GPU_COUNT=$GPU_COUNT

    LOG_FILE="$LOG_DIR/gpu_${gpu}.log"

    echo "[GPU $gpu] Starting at $(date)" | tee -a "$LOG_FILE"
    echo "[GPU $gpu] CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES" | tee -a "$LOG_FILE"

    START=$(date +%s%N)
    UNIQUE_NAME_LOC=${UNIQUE_NAME}_gpu_${gpu}

    # --- run test, but DON'T let `set -e` kill the subshell before we log ---
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
    # ----------------------------------------------------------------------

    END=$(date +%s%N)
    ELAPSED_MS=$(( (END - START) / 1000000 ))

    echo "[GPU $gpu] Finished with exit code $RC at $(date)" | tee -a "$LOG_FILE"
    echo "[GPU $gpu] Elapsed time: ${ELAPSED_MS} ms" | tee -a "$LOG_FILE"

    exit $RC
  ) &
  pids+=($!)
done

# Wait for all jobs
FAIL=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    FAIL=1
  fi
done

echo
if [[ "$FAIL" -ne 0 ]]; then
  echo "One or more GPU runs failed. Check logs in $LOG_DIR"
  exit 1
fi

echo "All GPU runs completed successfully."
