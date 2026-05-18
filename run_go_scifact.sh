#!/bin/bash
set -euo pipefail

N=5183
B=16
R=8
INDEX_DIR="indexes/scifact"
DATA_DIR="data/scifact"
EMBED_DIR="scifact-embeddings"


DOC_EMBED="my_scifact_vectors_192_float32.npy"
DOC_ID_MAP="my_scifact_vectors_192_float32.npy.ids"
QUERY_EMBED="query_scifact.npy"
BLOCK_PERM="data/scifact_block_permutations.json"
SECONDS=0

for B in 16 32 64; do
  for R in 8 32 128; do
    echo "Running with B=${B} and R=${R}"
    python gen_layout.py $N $B $R $DATA_DIR/layout_with_stats_${B}_${R}.json

  STAGE1_PREFIX="${DATA_DIR}/stage1_b${B}_r${R}"
  STAGE2_DIR="${DATA_DIR}/stage2_b${B}_r${R}"
  ./bm25-search \
    --index "${INDEX_DIR}" \
    --queries "${DATA_DIR}/queries.qrels.tsv" \
    --qrels "${DATA_DIR}/qrels.trec" \
    --stage1-data-bin "${STAGE1_PREFIX}_data.bin" \
    --stage1-idmap-bin "${STAGE1_PREFIX}_idmap.bin" \
    --stage2-data-bin "${STAGE2_DIR}/data.bin" \
    --stage2-idmap-bin "${STAGE2_DIR}/idmap.bin" \
    --vocab "${STAGE1_PREFIX}_vocab.json" \
    --layout-path "${DATA_DIR}/layout_with_stats_${B}_${R}.json" \
    --doc-embed "${DOC_EMBED}" \
    --doc-id-map "${DOC_ID_MAP}" \
    --query-embed "${QUERY_EMBED}" \
    --block-permutation "${BLOCK_PERM}" \
    --embed-dim 384 \
    --B "${B}" \
    --r "${R}" \
    --max-queries 0 \
    --pir-batch-size 128 --k_candidates 20 --L 20 --debug \
    --precompute 2>&1 > run_go_scifact_${B}_${R}.log
  elapsed_time=$SECONDS
  echo "Time elapsed: $elapsed_time seconds"
  echo "Parsing log for accuracy and performance..."
  python parse_log.py run_go_scifact_${B}_${R}.log
done
done
# mv approx_precompute_reranked_200.tsv go_results_b${B}_r${R}_k${K_CANDIDATES}.tsv