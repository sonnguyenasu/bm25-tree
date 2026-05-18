#!/bin/bash
set -euo pipefail

N=171332
INDEX_DIR="indexes/trec-covid"
DATA_DIR="data/trec-covid"
EMBED_DIR="trec-embeddings"



DOC_EMBED="my_trec_vectors_192_float32.npy"
DOC_ID_MAP="my_trec_vectors_192_float32.npy.ids"
QUERY_EMBED="query_trec.npy"
BLOCK_PERM="data/trec_block_permutations.json"

for B in 16 32 64; do
  for R in 8 32 128; do
    echo "Generating layout for B=${B} and R=${R}"
    python gen_layout.py $N $B $R $DATA_DIR/layout_with_stats_${B}_${R}.json
  

    STAGE1_PREFIX="${DATA_DIR}/stage1_b${B}_r${R}"
    STAGE2_DIR="${DATA_DIR}/stage2_b${B}_r${R}"
    SECONDS=0
    ./bm25-search \
      --index "${INDEX_DIR}" \
      --queries "${DATA_DIR}/queries.tsv" \
      --qrels "${DATA_DIR}/qrels.trec" \
      --stage1-data-bin "${STAGE1_PREFIX}_data.bin" \
      --stage1-idmap-bin "${STAGE1_PREFIX}_idmap.bin" \
      --stage2-data-bin "${STAGE2_DIR}/data.bin" \
      --stage2-idmap-bin "${STAGE2_DIR}/idmap.bin" \
      --doc-id-map "${DOC_ID_MAP}" \
      --vocab "${STAGE1_PREFIX}_vocab.json" \
      --layout-path "${DATA_DIR}/layout_with_stats_${B}_${R}.json" \
      --doc-embed "${DOC_EMBED}" \
      --query-embed "${QUERY_EMBED}" \
      --block-permutation "${BLOCK_PERM}" \
      --embed-dim 384 \
      --B "${B}" \
      --r "${R}" \
      --max-queries 500 \
      --pir-batch-size 16 --debug \
      --precompute 2>&1 > run_go_trec_covid.log
    elapsed_time=$SECONDS
    echo "Time elapsed: $elapsed_time seconds"
    echo "Parsing log for accuracy and performance..."
    python parse_log.py run_go_trec_covid.log
  done
done
# mv approx_precompute_reranked_200.tsv go_results_b${B}_r${r}_k${K_CANDIDATES}.tsv