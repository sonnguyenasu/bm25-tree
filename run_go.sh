#!/bin/bash
export PATH=$PATH:/usr/local/go/bin
go build -o bm25-search ./cmd
echo "Start executing"
B=32
r=32
N=8841823
python gen_layout.py $N $B $r
./bm25-search --B $B --r $r --layout-path data/layout_with_stats_${B}_${r}.json --qrels data/qrels.dev.small.tsv --index data/msmarco_reordered --debug --queries data/queries.dev.small.tsv --max-queries 10 --precompute --doc-embed data/stage3_doc_aligned_shuffle.npy --doc-id-map data/stage3_doc_aligned.npy.ids --query-embed data/stage3_query.npy --embed-dim 192 --stage1-data-bin exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_data.bin --stage1-idmap-bin exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_idmap.bin --stage2-data-bin exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_stage2/data.bin --stage2-idmap-bin exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_stage2/idmap.bin --vocab exp_setup/exp_cluster/cluster_golang_b${B}_r${r}_vocab.json --query-words 8 --pir-batch-size 128 #2>&1 | grep "ms\|MRR" 
