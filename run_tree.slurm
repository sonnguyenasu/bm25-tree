#!/bin/bash -l
#SBATCH --job-name=Tree_Ablation
#SBATCH --partition=bigmem
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=500G
#SBATCH --time=0-05:30:00

# Total Jobs: 14 (Indices 0 through 13)
#SBATCH --array=0-13
#SBATCH --output=logs/Tree_%A_%a.out
#SBATCH --error=logs/Tree_%A_%a.err

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"

module --quiet purge
module load hosts/hopper
module load gnu9/9.3.0
export PATH=$PATH:/usr/local/go/bin

# --- PARALLEL ARRAYS FOR ABLATION STUDY ---
# Index:      0       1       2       3       4       5       6       7       8       | 9       10      11      | 12         13
# Test:       VARY B & R (msmarco, k=50)                                              | VARY K (B=32, r=128)  | VARY DATA
DATA_ARR=(    msmarco msmarco msmarco msmarco msmarco msmarco msmarco msmarco msmarco   msmarco msmarco msmarco   scifact    trec-covid )
B_ARR=(       16      16      16      32      32      32      64      64      64        32      32      32        32         32         )
R_ARR=(       8       32      128     8       32      128     8       32      128       128     128     128       128        128        )
K_ARR=(       50      50      50      50      50      50      50      50      50        100     500     1000      50         50         )

task_id=$SLURM_ARRAY_TASK_ID

dataset=${DATA_ARR[$task_id]}
B_val=${B_ARR[$task_id]}
r_val=${R_ARR[$task_id]}
k_val=${K_ARR[$task_id]}
BLOCK_PERMS="../datasets/tree/scifact-all/data/scifact_block_permutations.json"

if [ "$dataset" == "msmarco" ]; then
    DB_SIZE=8841823
    MAX_QUERIES=6980
    EMBED_DIM=192
    DATA_ROOT="../datasets/tree/msmarco-all"

    # Dynamically adapt paths for the b64 structure
    if [ "$B_val" == "64" ]; then
        SUB_DIR="b64"
        PREFIX="cluster_golang"
    else
        # Fallback to standard exp_setup layout for B=16 and B=32
        EXP_TYPE="exp_cluster"  # Toggle to "exp_lucene" if needed
        SUB_DIR="exp_setup/${EXP_TYPE}"
        PREFIX="cluster_golang" # Toggle to "lucene_golang" if needed
    fi

    LAYOUT_PATH="${DATA_ROOT}/layout_with_stats_${B_val}_${r_val}.json"
    QRELS="${DATA_ROOT}/qrels.dev.small.tsv"
    INDEX="${DATA_ROOT}/msmarco_reordered"
    QUERIES="${DATA_ROOT}/queries.dev.small.tsv"
    DOC_EMBED="${DATA_ROOT}/stage3_doc_aligned_shuffle.npy"
    DOC_ID_MAP="${DATA_ROOT}/stage3_doc_aligned.npy.ids"
    QUERY_EMBED="${DATA_ROOT}/stage3_query.npy"

    # Updated paths using dynamic sub-directories
    STAGE1_DATA="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_data.bin"
    STAGE1_IDMAP="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_idmap.bin"
    STAGE2_DATA="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_stage2/data.bin"
    STAGE2_IDMAP="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_stage2/idmap.bin"
    VOCAB="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_vocab.json"

elif [ "$dataset" == "scifact" ]; then
    DB_SIZE=5183
    MAX_QUERIES=1109
    EMBED_DIM=192
    DATA_ROOT="../datasets/tree/scifact-all"
    LAYOUT_PATH="${DATA_ROOT}/data/scifact/layout_with_stats_${B_val}_${r_val}.json"
    QRELS="${DATA_ROOT}/data/scifact/qrels.trec"
    INDEX="${DATA_ROOT}/indexes/scifact"
    QUERIES="${DATA_ROOT}/data/scifact/queries.tsv"
    DOC_EMBED="${DATA_ROOT}/my_scifact_vectors_192_float32.npy"
    DOC_ID_MAP="${DATA_ROOT}/my_scifact_vectors_192_float32.npy.ids"
    QUERY_EMBED="${DATA_ROOT}/query_scifact.npy"
    STAGE1_DATA="${DATA_ROOT}/data/scifact/stage1_b${B_val}_r${r_val}_data.bin"
    STAGE1_IDMAP="${DATA_ROOT}/data/scifact/stage1_b${B_val}_r${r_val}_idmap.bin"
    STAGE2_DATA="${DATA_ROOT}/data/scifact/stage2_b${B_val}_r${r_val}/data.bin"
    STAGE2_IDMAP="${DATA_ROOT}/data/scifact/stage2_b${B_val}_r${r_val}/idmap.bin"
    VOCAB="${DATA_ROOT}/data/scifact/stage1_b${B_val}_r${r_val}_vocab.json"
    BLOCK_PERMS="${DATA_ROOT}/data/scifact_block_permutations.json"


elif [ "$dataset" == "trec-covid" ]; then
    DB_SIZE=171332
    MAX_QUERIES=50
    EMBED_DIM=384
    DATA_ROOT="../datasets/tree/trec-covid-all"
    LAYOUT_PATH="${DATA_ROOT}/data/trec-covid/layout_with_stats_${B_val}_${r_val}.json"
    QRELS="${DATA_ROOT}/data/trec-covid/qrels.trec"
    INDEX="${DATA_ROOT}/indexes/trec-covid"
    QUERIES="${DATA_ROOT}/data/trec-covid/queries.tsv"
    DOC_EMBED="${DATA_ROOT}/data/trec-covid/my_vectors_384_float32.npy"
    DOC_ID_MAP="${DATA_ROOT}/data/trec-covid/my_vectors_384_float32.npy.ids"
    QUERY_EMBED="${DATA_ROOT}/query_trec.npy"
    STAGE1_DATA="${DATA_ROOT}/data/trec-covid/stage1_b${B_val}_r${r_val}_data.bin"
    STAGE1_IDMAP="${DATA_ROOT}/data/trec-covid/stage1_b${B_val}_r${r_val}_idmap.bin"
    STAGE2_DATA="${DATA_ROOT}/data/trec-covid/stage2_b${B_val}_r${r_val}/data.bin"
    STAGE2_IDMAP="${DATA_ROOT}/data/trec-covid/stage2_b${B_val}_r${r_val}/idmap.bin"
    VOCAB="${DATA_ROOT}/data/trec-covid/stage1_b${B_val}_r${r_val}_vocab.json"
    BLOCK_PERMS="${DATA_ROOT}/data/trec_block_permutations.json"

else
    echo "Unknown dataset: $dataset"
    exit 1
fi

LAYOUT_PATH="${LAYOUT_PATH%.json}_${SLURM_ARRAY_TASK_ID}.json"

OUT_DIR="../results/tree_${dataset}_b${B_val}_r${r_val}_k${k_val}"
mkdir -p "$OUT_DIR"

echo "========================================"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Dataset:       $dataset"
echo "B Value:       $B_val"
echo "r Value:       $r_val"
echo "K Value:       $k_val"
echo "Embed Dim:     $EMBED_DIM"
echo "Output Dir:    $OUT_DIR"
echo "========================================"

# Run the python layout generator
python gen_layout.py "$DB_SIZE" "$B_val" "$r_val" "$LAYOUT_PATH"

# Define log file name
LOG_FILE="${OUT_DIR}/run_go_${dataset}_b${B_val}_r${r_val}_k${k_val}.log"


echo "Running dummy round to see if anything is wrong"
./bm25-search \
    --B "$B_val" \
    --r "$r_val" \
    --k_candidates "$k_val" \
    --layout-path "$LAYOUT_PATH" \
    --qrels "$QRELS" \
    --index "$INDEX" \
    --queries "$QUERIES" \
    --max-queries "$MAX_QUERIES" \
    --precompute \
    --doc-embed "$DOC_EMBED" \
    --doc-id-map "$DOC_ID_MAP" \
    --query-embed "$QUERY_EMBED" \
    --embed-dim "$EMBED_DIM" \
    --stage1-data-bin "$STAGE1_DATA" \
    --stage1-idmap-bin "$STAGE1_IDMAP" \
    --stage2-data-bin "$STAGE2_DATA" \
    --stage2-idmap-bin "$STAGE2_IDMAP" \
    --vocab "$VOCAB" \
    --query-words 8 \
    --block-permutation "$BLOCK_PERMS" \
    --pir-batch-size 128


SECONDS=0
echo "Running real tree search..."
./bm25-search \
    --B "$B_val" \
    --r "$r_val" \
    --k "$k_val" \
    --layout-path "$LAYOUT_PATH" \
    --qrels "$QRELS" \
    --index "$INDEX" \
    --queries "$QUERIES" \
    --max-queries "$MAX_QUERIES" \
    --precompute \
    --doc-embed "$DOC_EMBED" \
    --doc-id-map "$DOC_ID_MAP" \
    --query-embed "$QUERY_EMBED" \
    --embed-dim "$EMBED_DIM" \
    --stage1-data-bin "$STAGE1_DATA" \
    --stage1-idmap-bin "$STAGE1_IDMAP" \
    --stage2-data-bin "$STAGE2_DATA" \
    --stage2-idmap-bin "$STAGE2_IDMAP" \
    --vocab "$VOCAB" \
    --query-words 8 \
    --pir-batch-size 128 2>&1 | grep "ns\|us\|µs\|micro\|ms\|MRR\|MB\|KB" > "$LOG_FILE"

elapsed_time=$SECONDS
echo "Time elapsed: $elapsed_time seconds"
echo "Parsing log for accuracy and performance..."

echo "Log file:"
cat  "$LOG_FILE"

# Parse the logs and move outputs
# python parse_log.py "$LOG_FILE" "$k_val"
python make_json.py --log_file "$LOG_FILE" --out "$OUT_DIR/metadata.json" --k "$k_val"
mv "approx_precompute_reranked_$k_val.tsv" "${OUT_DIR}/go_results_${dataset}_b${B_val}_r${r_val}_k${k_val}_rerank.tsv" || true
mv "approx_precompute_$k_val.tsv" "${OUT_DIR}/go_results_${dataset}_b${B_val}_r${r_val}_k${k_val}.tsv" || true

# Copy SLURM logs
cp "logs/Tree_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out" "${OUT_DIR}/execution.log" || true
cp "logs/Tree_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err" "${OUT_DIR}/error.log" || true

rm -f "$LAYOUT_PATH"

echo "Execution finished."