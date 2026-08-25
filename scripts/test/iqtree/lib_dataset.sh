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
#   4. FLAT-DIR FALLBACK: the orchestrator may build DATASET_DIR from the nested
#      simulated/complex pattern ({data_type}/{model}/taxa_{taxa}/len_{len}[/tree_1])
#      even though the empirical data is staged FLAT as <root>/<Name>.<ext>
#      (e.g. the server's Empirical_datasets/Lassa_Virus.fas). So walk up to the
#      nearest existing ancestor directory and look for an alignment named after
#      one of the path components below it (the {model} component matches the
#      flat file). This only runs in the empirical branch (callers reach this
#      function only when DATASET_DIR has no tree_*/ subdirs), so it can NOT
#      affect simulated-data analysis.
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
    # 4. Flat-dir fallback (see header comment).
    local root=$base
    while [ -n "$root" ] && [ "$root" != "/" ] && [ "$root" != "." ] && [ ! -d "$root" ]; do
        root=$(dirname "$root")
    done
    if [ -d "$root" ] && [ "$root" != "$base" ]; then
        local rel=${base#"$root"/}
        local oldifs=$IFS; IFS='/'; local comps=($rel); IFS=$oldifs
        local i c
        for ((i=${#comps[@]}-1; i>=0; i--)); do
            c=${comps[i]}
            [ -z "$c" ] && continue
            if [ -f "$root/$c" ]; then echo "$root/$c"; return 0; fi
            for ext in "${DATASET_ALN_EXTS[@]}"; do
                if [ -f "$root/$c.$ext" ]; then echo "$root/$c.$ext"; return 0; fi
            done
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

# ─── Output relocation ────────────────────────────────────────────────────────
# By default IQ-TREE writes its outputs into the directory it is invoked from,
# which is the DATASET tree -- results end up interleaved with the input data,
# and a second run over the same dataset overwrites or collides with the first.
#
# Setting OUTPUT_DIR redirects them to a separate root that MIRRORS the dataset
# layout, so the output tree has the same shape as the input tree:
#
#   DATASET_ROOT = /scratch/.../empirical_kingdoms
#   alignment    = /scratch/.../empirical_kingdoms/Animalia/AA/Birds_Jarvis2014/Exon.AminoAcid.aln.phy
#   OUTPUT_DIR   = /scratch/.../results/run42
#   -> outputs land in  /scratch/.../results/run42/Animalia/AA/Birds_Jarvis2014/
#
# OUTPUT_DIR empty   -> unchanged behaviour (outputs beside the alignment), so
#                       existing callers that do not set it are unaffected.
# DATASET_ROOT empty -> falls back to the leaf directory name. The outputs are
#                       still separated from the data, just flatter.
#
# Usage:  run_iqtree_cmd "$aln" "$targs" "$(resolve_out_prefix "$dir" "output_x")"
resolve_out_prefix() {   # <dir_containing_alignment> <prefix_basename>
    local src_dir=$1 base=$2 rel out root
    if [ -z "${OUTPUT_DIR:-}" ]; then
        echo "$base"          # legacy: relative prefix, written into CWD
        return 0
    fi
    # Canonicalise so the ${src#root/} strip below is not defeated by symlinks
    # or trailing slashes -- the empirical data is staged behind symlinks.
    src_dir=$(cd "$src_dir" 2>/dev/null && pwd) || src_dir=$1
    if [ -n "${DATASET_ROOT:-}" ]; then
        root=$(cd "$DATASET_ROOT" 2>/dev/null && pwd) || root=$DATASET_ROOT
        rel=${src_dir#"$root"/}
        [ "$rel" = "$src_dir" ] && rel=$(basename "$src_dir")   # not under root
    else
        rel=$(basename "$src_dir")
    fi
    out="$OUTPUT_DIR/$rel"
    mkdir -p "$out" || { echo "Failed to create output dir: $out" >&2; return 1; }
    echo "$out/$base"
}
