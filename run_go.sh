#!/bin/bash
export PATH=$PATH:/usr/local/go/bin
go build -o bm25-search ./cmd
echo "Start executing"

N=8841823
NUM_QUERIES=6980
for B in 32
do
    for r in 8 32 128
    do
        for K_CANDIDATES in 32 64 128 256
        do
        python gen_layout.py $N $B $r
        SECONDS=0
        echo "Running bm25-search with B=$B and r=$r..."
        ./bm25-search --B $B --r $r --k_candidates $K_CANDIDATES --layout-path data/layout_with_stats_${B}_${r}.json --qrels data/qrels.dev.small.tsv --index data/msmarco_reordered --queries data/queries.dev.small.tsv --max-queries ${NUM_QUERIES} --precompute --doc-embed data/stage3_doc_aligned_shuffle.npy --doc-id-map data/stage3_doc_aligned.npy.ids --query-embed data/stage3_query.npy --embed-dim 192 --stage1-data-bin exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_data.bin --stage1-idmap-bin exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_idmap.bin --stage2-data-bin exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_stage2/data.bin --stage2-idmap-bin exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_stage2/idmap.bin --vocab exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_vocab.json --query-words 8 --pir-batch-size 128 2>&1 | grep "ms\|MRR\|MB\|KB" > run_go_b${B}_r${r}_k${K_CANDIDATES}.log
        elapsed_time=$SECONDS
        echo "Time elapsed: $elapsed_time seconds"
        echo "Parsing log for accuracy and performance..."
        python parse_log.py run_go_b${B}_r${r}_k${K_CANDIDATES}.log
        mv approx_precompute_reranked_200.tsv go_results_b${B}_r${r}_k${K_CANDIDATES}.tsv
        done
    done
done
echo "Execution finished."