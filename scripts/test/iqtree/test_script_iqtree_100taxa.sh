#!/bin/bash
# =============================================================================
# test_script_iqtree_100taxa.sh
#
# CSV-driven test runner for the 100taxa_1000000sites multi-model dataset.
# Reads each row from the CSV and runs IQ-TREE with the correct model,
# alignment, and tree file for that combination.
#
# Arguments (passed via qsub -v):
#   ARG1  -  Base path to the 100taxa_1000000sites dataset
#   ARG2  -  Unique name / run identifier
#   ARG3  -  Working directory (contains builds/)
#   ARG4  -  Data type filter: "AA", "DNA", or "ALL"
#   ARG5  -  Backend type: VANILA | CUDA | OPENACC | OPENACC_PROFILE
#   ARG6  -  Path to the CSV test matrix file
#   ARG7  -  Extra IQ-TREE arguments (appended after the model flag)
# =============================================================================

set -euo pipefail

DATASET_BASE=$ARG1
UNIQUE_NAME=$ARG2
WD=$ARG3
DATA_TYPE_FILTER=$ARG4
TYPE=$ARG5
CSV_FILE=$ARG6
EXTRA_IQTREE_ARGS=${ARG7:-}

# ---------------------------------------------------------------------------
# Resolve executable based on backend type
# ---------------------------------------------------------------------------
executable_path=""
if [ "$TYPE" == "VANILA" ]; then
    executable_path="$WD/builds/build-vanila/iqtree3"
elif [ "$TYPE" == "CUDA" ]; then
    executable_path="$WD/builds/build-nvhpc-cuda/iqtree3"
elif [ "$TYPE" == "OPENACC_PROFILE" ]; then
    executable_path="$WD/builds/build-nvhpc-prof-openacc/iqtree3"
elif [ "$TYPE" == "OPENACC" ]; then
    executable_path="$WD/builds/build-nvhpc-openacc/iqtree3"
fi

if [ ! -f "$executable_path" ]; then
    echo "ERROR: Executable not found: $executable_path"
    exit 1
fi

echo "=============================================="
echo "100-taxa multi-model IQ-TREE test runner"
echo "  Dataset base : $DATASET_BASE"
echo "  Run name     : $UNIQUE_NAME"
echo "  Backend      : $TYPE"
echo "  Executable   : $executable_path"
echo "  Data filter  : $DATA_TYPE_FILTER"
echo "  CSV file     : $CSV_FILE"
echo "  Extra args   : $EXTRA_IQTREE_ARGS"
echo "=============================================="

# ---------------------------------------------------------------------------
# Iterate over CSV rows
# ---------------------------------------------------------------------------
total=0
passed=0
failed=0

# Skip header line
tail -n +2 "$CSV_FILE" | while IFS=',' read -r data_type tree_type model tree_number taxa sites alignment_file tree_file dataset_dir iqtree_model_flag; do

    # Filter by data type if requested
    if [ "$DATA_TYPE_FILTER" != "ALL" ] && [ "$data_type" != "$DATA_TYPE_FILTER" ]; then
        continue
    fi

    total=$((total + 1))

    # Build the full path to the tree directory
    TREE_DIR="${DATASET_BASE}/${dataset_dir}"

    echo "--------------------------------------"
    echo "[$total] data_type=$data_type  tree_type=$tree_type  model=$model  tree=$tree_number"
    echo "  Directory: $TREE_DIR"

    if [ ! -d "$TREE_DIR" ]; then
        echo "  WARNING: Directory not found, skipping: $TREE_DIR"
        failed=$((failed + 1))
        continue
    fi

    cd "$TREE_DIR" || { echo "  ERROR: Failed to cd into $TREE_DIR"; failed=$((failed + 1)); continue; }

    # Verify input files exist
    if [ ! -f "$alignment_file" ]; then
        echo "  WARNING: Alignment file not found: $alignment_file"
        failed=$((failed + 1))
        cd - > /dev/null
        continue
    fi
    if [ ! -f "$tree_file" ]; then
        echo "  WARNING: Tree file not found: $tree_file"
        failed=$((failed + 1))
        cd - > /dev/null
        continue
    fi

    # Build the output prefix
    prefix="output_${UNIQUE_NAME}_${data_type}_${tree_type}_${model}_tree${tree_number}_${TYPE}"

    echo "  Running: $executable_path -s $alignment_file -te $tree_file $iqtree_model_flag -blfix --kernel-nonrev $EXTRA_IQTREE_ARGS --prefix $prefix"

    $executable_path \
        -s "$alignment_file" \
        -te "$tree_file" \
        $iqtree_model_flag \
        -blfix --kernel-nonrev \
        $EXTRA_IQTREE_ARGS \
        --prefix "$prefix"

    if [ $? -ne 0 ]; then
        echo "  FAILED: $data_type / $tree_type / $model / tree_$tree_number"
        failed=$((failed + 1))
    else
        echo "  PASSED"
        passed=$((passed + 1))
    fi

    cd - > /dev/null

done

echo "=============================================="
echo "Summary: total=$total  passed=$passed  failed=$failed"
echo "=============================================="

if [ "$failed" -gt 0 ]; then
    echo "Some tests failed!"
    exit 1
fi
