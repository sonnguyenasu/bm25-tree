#!/bin/bash -l
#SBATCH --job-name=Tree_Ablation
#SBATCH --partition=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=150G
#SBATCH --time=0-05:30:00

#SBATCH --array=0-59
#SBATCH --output=logs/Tree_%A_%a.out
#SBATCH --error=logs/Tree_%A_%a.err

set -euo pipefail
cd "$SLURM_SUBMIT_DIR"

module --quiet purge
module load hosts/hopper
module load gnu9/9.3.0
export PATH=$PATH:/usr/local/go/bin

DATA_ARR=()
METHOD_ARR=()
B_ARR=()
R_ARR=()
K_ARR=()

# Helper function to generate the 15 ablations per dataset/method
add_ablations() {
    local d=$1
    local m=$2

    # 1. VARY B & R (k=100) -> 9 combinations
    for b in 16 32 64; do
        for r in 8 32 128; do
            DATA_ARR+=("$d")
            METHOD_ARR+=("$m")
            B_ARR+=("$b")
            R_ARR+=("$r")
            K_ARR+=("100")
        done
    done

    # 2. VARY K (B=32, r=128) -> 6 combinations
    for k in 10 50 100 500 1000 5000; do
        DATA_ARR+=("$d")
        METHOD_ARR+=("$m")
        B_ARR+=("32")
        R_ARR+=("128")
        K_ARR+=("$k")
    done
}

# Build the setups
add_ablations "msmarco" "cluster"
add_ablations "msmarco" "lucene"
add_ablations "scifact" "default"
add_ablations "trec-covid" "default"

task_id=$SLURM_ARRAY_TASK_ID

dataset=${DATA_ARR[$task_id]}
method=${METHOD_ARR[$task_id]}
B_val=${B_ARR[$task_id]}
r_val=${R_ARR[$task_id]}
k_val=${K_ARR[$task_id]}

DATA_ROOT="data/"

if [ "$dataset" == "msmarco" ]; then
    DB_SIZE=8841823
    MAX_QUERIES=6980
    EMBED_DIM=192

    LAYOUT_PATH="${DATA_ROOT}/layout_with_stats_${B_val}_${r_val}.json"

    # These files have moved directly into the data/ folder
    QRELS="${DATA_ROOT}/qrels.dev.small.tsv"
    QUERIES="${DATA_ROOT}/queries.dev.small.tsv"
    DOC_EMBED="${DATA_ROOT}/stage3_doc_aligned_shuffle.npy"
    DOC_ID_MAP="${DATA_ROOT}/stage3_doc_aligned.npy.ids"
    QUERY_EMBED="${DATA_ROOT}/stage3_query.npy"
    BLOCK_PERMS="${DATA_ROOT}/block_permutations.json"

    # Pointing directly to the directory with the Lucene segments
    INDEX="${DATA_ROOT}/msmarco_reordered"

    # All cluster configurations (including b64) are now uniformly in exp_cluster
    # Route to the correct directory based on the ablation method
    if [ "$method" == "cluster" ]; then
        SUB_DIR="exp_setup/exp_cluster"
        PREFIX="cluster_golang"
    elif [ "$method" == "lucene" ]; then
        SUB_DIR="exp_setup/exp_lucene"
        PREFIX="lucene_golang"
    else
        echo "Unknown method for msmarco: $method"
        exit 1
    fi

    STAGE1_DATA="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_data.bin"
    STAGE1_IDMAP="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_idmap.bin"
    STAGE2_DATA="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_stage2/data.bin"
    STAGE2_IDMAP="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_stage2/idmap.bin"
    VOCAB="${DATA_ROOT}/${SUB_DIR}/${PREFIX}_b${B_val}_r${r_val}_vocab.json"


elif [ "$dataset" == "scifact" ]; then
    DB_SIZE=5183
    MAX_QUERIES=1109
    EMBED_DIM=192

    # Using DATA_DIR to avoid overwriting the global DATA_ROOT="data/"
    DATA_DIR="data/scifact"
    LAYOUT_PATH="${DATA_DIR}/layout_with_stats_${B_val}_${r_val}.json"

    QRELS="${DATA_DIR}/qrels.trec"
    QUERIES="${DATA_DIR}/queries.tsv"

    # The index is one level up in the main datasets directory
    INDEX="../index_scifact"

    # These vectors are sitting in your current bm25-tree directory
    DOC_EMBED="./my_scifact_vectors_192_float32.npy"
    DOC_ID_MAP="./my_scifact_vectors_192_float32.npy.ids"
    QUERY_EMBED="./query_scifact.npy"

    STAGE1_DATA="${DATA_DIR}/stage1_b${B_val}_r${r_val}_data.bin"
    STAGE1_IDMAP="${DATA_DIR}/stage1_b${B_val}_r${r_val}_idmap.bin"
    STAGE2_DATA="${DATA_DIR}/stage2_b${B_val}_r${r_val}/data.bin"
    STAGE2_IDMAP="${DATA_DIR}/stage2_b${B_val}_r${r_val}/idmap.bin"
    VOCAB="${DATA_DIR}/stage1_b${B_val}_r${r_val}_vocab.json"

    # This sits in the main data/ directory
    BLOCK_PERMS="${DATA_ROOT}/scifact_block_permutations.json"


elif [ "$dataset" == "trec-covid" ]; then
    DB_SIZE=171332
    MAX_QUERIES=50
    EMBED_DIM=384

    DATA_DIR="data/trec-covid"
    LAYOUT_PATH="${DATA_DIR}/layout_with_stats_${B_val}_${r_val}.json"

    QRELS="${DATA_DIR}/qrels.trec"
    QUERIES="${DATA_DIR}/queries.tsv"

    # The index is one level up in the main datasets directory
    INDEX="../index_trec_covid"

    # Document embeddings are in data/trec-covid, but query embeddings are in the current dir
    DOC_EMBED="${DATA_DIR}/my_vectors_384_float32.npy"
    DOC_ID_MAP="${DATA_DIR}/my_vectors_384_float32.npy.ids"
    QUERY_EMBED="./query_trec.npy"

    STAGE1_DATA="${DATA_DIR}/stage1_b${B_val}_r${r_val}_data.bin"
    STAGE1_IDMAP="${DATA_DIR}/stage1_b${B_val}_r${r_val}_idmap.bin"
    STAGE2_DATA="${DATA_DIR}/stage2_b${B_val}_r${r_val}/data.bin"
    STAGE2_IDMAP="${DATA_DIR}/stage2_b${B_val}_r${r_val}/idmap.bin"
    VOCAB="${DATA_DIR}/stage1_b${B_val}_r${r_val}_vocab.json"

    # This sits in the main data/ directory
    BLOCK_PERMS="${DATA_ROOT}/trec_block_permutations.json"

else
    echo "Unknown dataset: $dataset"
    exit 1
fi

LAYOUT_PATH="${LAYOUT_PATH%.json}_${SLURM_ARRAY_TASK_ID}.json"

OUT_DIR="../results/tree_${dataset}_${method}_b${B_val}_r${r_val}_k${k_val}"
mkdir -p "$OUT_DIR"

echo "========================================"
echo "Array Task ID: $SLURM_ARRAY_TASK_ID"
echo "Dataset:       $dataset"
echo "Method:        $method"
echo "B Value:       $B_val"
echo "r Value:       $r_val"
echo "K Value:       $k_val"
echo "Embed Dim:     $EMBED_DIM"
echo "Output Dir:    $OUT_DIR"
echo "========================================"

# Run the python layout generator
python gen_layout.py "$DB_SIZE" "$B_val" "$r_val" "$LAYOUT_PATH"

# Define log file name
LOG_FILE="${OUT_DIR}/run_go_${dataset}_${method}_b${B_val}_r${r_val}_k${k_val}.log"

rm -f "$OUT_DIR/go_results.tsv"
touch "$OUT_DIR/go_results.tsv"

#echo "Running dummy round to see if anything is wrong"
#./bm25-search \
#    --B "$B_val" \
#    --r "$r_val" \
#    --k_candidates "$k_val" \
#    --layout-path "$LAYOUT_PATH" \
#    --qrels "$QRELS" \
#    --index "$INDEX" \
#    --queries "$QUERIES" \
#    --max-queries "$MAX_QUERIES" \
#    --precompute \
#    --doc-embed "$DOC_EMBED" \
#    --doc-id-map "$DOC_ID_MAP" \
#    --query-embed "$QUERY_EMBED" \
#    --embed-dim "$EMBED_DIM" \
#    --stage1-data-bin "$STAGE1_DATA" \
#    --stage1-idmap-bin "$STAGE1_IDMAP" \
#    --stage2-data-bin "$STAGE2_DATA" \
#    --stage2-idmap-bin "$STAGE2_IDMAP" \
#    --vocab "$VOCAB" \
#    --query-words 8 \
#    --block-permutation "$BLOCK_PERMS" \
#    --output-tsv-path "$OUT_DIR/go_results.tsv" \
#    --pir-batch-size 128


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
    --output-tsv-path "$OUT_DIR/go_results.tsv" \
    --pir-batch-size 128 > "$LOG_FILE"


elapsed_time=$SECONDS
echo "Time elapsed: $elapsed_time seconds"
echo "Parsing log for accuracy and performance..."

echo "Log file:"
cat  "$LOG_FILE"

# Parse the logs and move outputs
# python parse_log.py "$LOG_FILE" "$k_val"
python make_json.py --log_file "$LOG_FILE" --out "$OUT_DIR/metadata.json" --k "$k_val"

# Copy SLURM logs
cp "logs/Tree_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.out" "${OUT_DIR}/execution.log" || true
cp "logs/Tree_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}.err" "${OUT_DIR}/error.log" || true

rm -f "$LAYOUT_PATH"

echo "Execution finished."
