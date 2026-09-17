#!/bin/bash -l
#SBATCH --job-name=Tree_Ablation_PIR
#SBATCH --partition=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=70G
#SBATCH --time=0-05:30:00
#SBATCH --constraint=amd
#SBATCH --array=0-9
#SBATCH --output=logs/Tree_%A_%a.out
#SBATCH --error=logs/Tree_%A_%a.err

set -euo pipefail
ROOT_DIR="$SLURM_SUBMIT_DIR"
cd "$ROOT_DIR"

module --quiet purge
module load hosts/hopper
module load gnu9/9.3.0
export PATH=$PATH:/usr/local/go/bin

# 0-4: msmarco configs
# 5-9: scifact configs (C1-C5)
DATA_ARR=("msmarco" "msmarco" "msmarco" "msmarco" "msmarco" "scifact" "scifact" "scifact" "scifact" "scifact")

# Hyperparameters mapped to the 10 specific runs
L_ARR=(100 50 200 400 400 5 5 10 20 40)
KCAND_ARR=(128 64 128 256 256 5 5 10 5 10)
QWORDS_ARR=(6 4 6 8 8 12 8 12 16 16)
B_ARR=(64 64 64 16 64 8 32 8 8 16)
R_ARR=(128 128 128 128 128 128 128 128 128 128)
S_ARR=(8 16 16 8 4 2 2 2 2 2)
MAX_Q_ARR=(6980 6980 6980 6980 6980 300 300 300 300 300)
EMBED_ARR=(192 192 192 192 192 384 384 384 384 384)

task_id=$SLURM_ARRAY_TASK_ID
dataset=${DATA_ARR[$task_id]}
L_val=${L_ARR[$task_id]}
k_cand_val=${KCAND_ARR[$task_id]}
q_words_val=${QWORDS_ARR[$task_id]}
B_val=${B_ARR[$task_id]}
r_val=${R_ARR[$task_id]}
s_val=${S_ARR[$task_id]}
max_q_val=${MAX_Q_ARR[$task_id]}
embed_val=${EMBED_ARR[$task_id]}
k_val=10

BINARY="${ROOT_DIR}/bm25-search"
OUT_DIR="/scratch/dblackle/results/tree_${dataset}_b${B_val}_r${r_val}_s${s_val}_L${L_val}_k${k_val}"
mkdir -p "$OUT_DIR"

echo "========================================"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Dataset:       $dataset"
echo "B Value:       $B_val"
echo "r Value:       $r_val"
echo "s Value:       $s_val"
echo "L Value:       $L_val"
echo "k_candidates:  $k_cand_val"
echo "Query Words:   $q_words_val"
echo "Output Dir:    $OUT_DIR"
echo "========================================"

# Pre-define dataset-specific variables using absolute paths
if [ "$dataset" == "msmarco" ]; then
    DB_SIZE=8841823
    LAYOUT_PATH="data/layout_with_stats_${B_val}_${r_val}.json"
    python gen_layout.py "$DB_SIZE" "$B_val" "$r_val"
    BLOCK_PERMS="data/block_permutations_$B_val.json"
    INDEX="${ROOT_DIR}/data/msmarco_reordered"
    QUERIES="${ROOT_DIR}/data/queries.dev.small.tsv"
    QRELS="${ROOT_DIR}/data/qrels.dev.small.tsv"
    VOCAB="${ROOT_DIR}/data/stage1_vocab.json"
    STAGE1_DATA="${ROOT_DIR}/data/stage1_data.bin"
    STAGE1_IDMAP="${ROOT_DIR}/data/stage1/stage1_idmap.bin"
    STAGE2_DATA="${ROOT_DIR}/data/stage2/data.bin"
    STAGE2_IDMAP="${ROOT_DIR}/data/stage2/idmap.bin"
    DOC_EMBED="${ROOT_DIR}/data/stage3_doc_aligned_shuffle.npy"
    DOC_ID_MAP="${ROOT_DIR}/data/stage3_doc_aligned.npy.ids"
    QUERY_EMBED="${ROOT_DIR}/data/stage3_query.npy"
    CACHE_ARGS=""

elif [ "$dataset" == "scifact" ]; then
    DATA_ROOT="${ROOT_DIR}/data/scifact"
    ARTIFACT_DIR="${DATA_ROOT}/pir/B${B_val}_r${r_val}_s${s_val}"
    BLOCK_PERMS="${ROOT_DIR}/data/scifact_block_permutations.json"

    CACHE_DIR="${ROOT_DIR}/cuckoo_cache/scifact/B${B_val}_r${r_val}_s${s_val}"
    mkdir -p "$CACHE_DIR"

    LAYOUT_PATH="${ARTIFACT_DIR}/layout.json"
    INDEX="${ROOT_DIR}/indexes/scifact"
    QUERIES="${DATA_ROOT}/queries.qrels.tsv"
    QRELS="${DATA_ROOT}/qrels.trec"
    VOCAB="${ARTIFACT_DIR}/stage1_vocab.json"
    STAGE1_DATA="${ARTIFACT_DIR}/stage1_data.bin"
    STAGE1_IDMAP="${ARTIFACT_DIR}/stage1_idmap.bin"
    STAGE2_DATA="${ARTIFACT_DIR}/stage2/data.bin"
    STAGE2_IDMAP="${ARTIFACT_DIR}/stage2/idmap.bin"
    DOC_EMBED="${DATA_ROOT}/clustered/doc_embeddings.npy"
    DOC_ID_MAP="${DATA_ROOT}/clustered/doc_embeddings.npy.ids"
    QUERY_EMBED="${DATA_ROOT}/query_embeddings.npy"

    CACHE_ARGS="--cuckoo-cache-dir ${CACHE_DIR}"


else
    echo "Unknown dataset: $dataset"
    exit 1
fi

LOG_FILE="${OUT_DIR}/run_go_${dataset}_b${B_val}_r${r_val}_s${s_val}_L${L_val}_k${k_val}.log"

SECONDS=0
echo "Running tree search..."
"$BINARY" \
    --L "$L_val" \
    --k_candidates "$k_cand_val" \
    --query-words "$q_words_val" \
    --pir-constant-work \
    --B "$B_val" \
    --r "$r_val" \
    --s "$s_val" \
    --k "$k_val" \
    --max-queries "$max_q_val" \
    --k1 0.9 \
    --b 0.4 \
    --scale 10 \
    --precompute \
    --pir-batch-size 128 \
    --cuckoo-load-factor 0.4 \
    --cuckoo-max-kicks 1000 \
    --cuckoo-build-attempts 8 \
    --layout-path "$LAYOUT_PATH" \
    --index "$INDEX" \
    --queries "$QUERIES" \
    --qrels "$QRELS" \
    --vocab "$VOCAB" \
    --stage1-data-bin "$STAGE1_DATA" \
    --stage1-idmap-bin "$STAGE1_IDMAP" \
    --stage2-data-bin "$STAGE2_DATA" \
    --stage2-idmap-bin "$STAGE2_IDMAP" \
    --doc-embed "$DOC_EMBED" \
    --doc-id-map "$DOC_ID_MAP" \
    --query-embed "$QUERY_EMBED" \
    --embed-dim "$embed_val" \
    --output-tsv-path "$OUT_DIR/go_results.tsv" \
    --block-permutation "$BLOCK_PERMS" \
    --meta-json-path "$OUT_DIR/metadata.json" \
    --pir-threads 16 \
    $CACHE_ARGS > "$LOG_FILE" 2>&1

elapsed_time=$SECONDS
echo "Time elapsed: $elapsed_time seconds"

# Copy SLURM logs into the output directory for reference
cp "${ROOT_DIR}/logs/Tree_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out" "execution.log" || true
cp "${ROOT_DIR}/logs/Tree_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err" "error.log" || true

echo "Execution finished."