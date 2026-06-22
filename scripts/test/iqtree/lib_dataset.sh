#!/bin/bash
# =============================================================================
# lib_dataset.sh — shared dataset-layout helpers for the iqtree test scripts
# =============================================================================
# Sourced by test_script_iqtree.sh and test_script_iqtree_omp.sh.
#
# Two supported layouts (auto-detected from DATASET_DIR — no config flag needed):
#
#   simulated : <DATASET_DIR>/tree_<i>/alignment_<length>.phy
#               (+ optional tree_<i>.full.treefile for -te/-t)
#               -> caller iterates tree_1..NUM_TREES (existing behaviour).
#
#   empirical : a single alignment file (FASTA/PHYLIP/...). Supports the flat
#               model_tamer layout, e.g.  <Empirical_datasets>/<Name>.fas
#               referenced via the CSV `model` column + dataset_path_pattern
#               "{model}" (DATASET_DIR = <parent>/<Name>, no extension), as well
#               as DATASET_DIR pointing straight at the file or at a directory
#               that holds a single alignment.
#               -> caller runs once; empirical data has no bundled fixed tree, so
#                  a full tree search is used unless a sibling <name>.treefile
#                  exists (see empirical_tree_args).
# =============================================================================

# Alignment extensions tried (priority order) when resolving empirical data.
DATASET_ALN_EXTS=(fasta fas fa phy phylip nex nexus aln)

# dataset_dir_has_glob <DATASET_DIR> <glob>
# True (0) when DATASET_DIR is a directory containing at least one entry matching
# <glob> (relative to DATASET_DIR). Use this to detect a script's own simulated
# marker: tree_<i>/ scripts pass "tree_*", length-based scripts pass "alignment_*".
dataset_dir_has_glob() {
    local d=$1 g=$2
    [ -d "$d" ] || return 1
    compgen -G "$d/$g" >/dev/null 2>&1
}

# dataset_is_simulated <DATASET_DIR>
# True (0) when DATASET_DIR is a directory containing tree_<i>/ subfolders
# (the tree-indexed simulated layout). Thin wrapper over dataset_dir_has_glob.
dataset_is_simulated() {
    dataset_dir_has_glob "$1" "tree_*"
}

# resolve_empirical_alignment <DATASET_DIR>
# Echoes the path to the single alignment file; returns 1 if none is found.
# Resolution order:
#   1. DATASET_DIR itself, if it is a file.
#   2. DATASET_DIR.<ext> for each known extension.
#   3. The first matching alignment file inside DATASET_DIR, if it is a directory.
resolve_empirical_alignment() {
    local base=$1 ext f
    if [ -f "$base" ]; then
        echo "$base"; return 0
    fi
    for ext in "${DATASET_ALN_EXTS[@]}"; do
        if [ -f "${base}.${ext}" ]; then
            echo "${base}.${ext}"; return 0
        fi
    done
    if [ -d "$base" ]; then
        for ext in "${DATASET_ALN_EXTS[@]}"; do
            f=$(compgen -G "$base/*.$ext" 2>/dev/null | head -n1)
            if [ -n "$f" ]; then
                echo "$f"; return 0
            fi
        done
    fi
    return 1
}

# empirical_tree_args <TREE_MODE> <ALIGN_FILE>
# Echoes the iqtree tree flag for empirical data (stdout). Empirical alignments
# carry no bundled fixed tree, so te/t only engage when a sibling
# "<align-without-ext>.treefile" exists; otherwise a full tree search is run
# (no flag) and a notice is written to stderr.
empirical_tree_args() {
    local mode=$1 aln=$2 tf
    case "$mode" in
        te|t)
            tf="${aln%.*}.treefile"
            if [ -f "$tf" ]; then
                if [ "$mode" = te ]; then echo "-te $tf"; else echo "-t $tf"; fi
            else
                echo "empirical: tree_mode=$mode but no fixed tree '$tf' found — running full tree search" >&2
            fi
            ;;
        *) : ;;  # none (or anything else) → full search, no tree flag
    esac
}
