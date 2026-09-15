./bm25-search \
  --L 50  --k_candidates 64  --query-words 4 --pir-constant-work \
  --B 32 \
  --r 128 \
  --s 8 \
  --k 10 \
  --max-queries 6980 \
  --k1 0.9 \
  --b 0.4 \
  --scale 10 \
  --precompute \
  --pir-batch-size 128 \
  --cuckoo-load-factor 0.4 \
  --cuckoo-max-kicks 1000 \
  --cuckoo-build-attempts 8 \
  --layout-path data/layout_with_stats_32_128.json \
  --index data/msmarco_reordered \
  --queries data/queries.dev.small.tsv \
  --qrels data/qrels.dev.small.tsv \
  --vocab data/stage1_vocab.json \
  --stage1-data-bin data/stage1_data.bin \
  --stage1-idmap-bin data/stage1/stage1_idmap.bin \
  --stage2-data-bin data/stage2/data.bin \
  --stage2-idmap-bin data/stage2/idmap.bin \
  --doc-embed data/stage3_doc_aligned_shuffle.npy \
  --doc-id-map data/stage3_doc_aligned.npy.ids \
  --query-embed data/stage3_query.npy \
  --embed-dim 192 \
  2>&1 | tee logs/cuckoo_100q_config1.log


  ./bm25-search \
  --L 100  --k_candidates 128  --query-words 6 --pir-constant-work \
  --B 32 \
  --r 128 \
  --s 8 \
  --k 10 \
  --max-queries 6980 \
  --k1 0.9 \
  --b 0.4 \
  --scale 10 \
  --precompute \
  --pir-batch-size 128 \
  --cuckoo-load-factor 0.4 \
  --cuckoo-max-kicks 1000 \
  --cuckoo-build-attempts 8 \
  --layout-path data/layout_with_stats_32_128.json \
  --index data/msmarco_reordered \
  --queries data/queries.dev.small.tsv \
  --qrels data/qrels.dev.small.tsv \
  --vocab data/stage1_vocab.json \
  --stage1-data-bin data/stage1_data.bin \
  --stage1-idmap-bin data/stage1/stage1_idmap.bin \
  --stage2-data-bin data/stage2/data.bin \
  --stage2-idmap-bin data/stage2/idmap.bin \
  --doc-embed data/stage3_doc_aligned_shuffle.npy \
  --doc-id-map data/stage3_doc_aligned.npy.ids \
  --query-embed data/stage3_query.npy \
  --embed-dim 192 \
  2>&1 | tee logs/cuckoo_100q_config2.log


  ./bm25-search \
  --L 200  --k_candidates 128  --query-words 6 --pir-constant-work \
  --B 32 \
  --r 128 \
  --s 8 \
  --k 10 \
  --max-queries 6980 \
  --k1 0.9 \
  --b 0.4 \
  --scale 10 \
  --precompute \
  --pir-batch-size 128 \
  --cuckoo-load-factor 0.4 \
  --cuckoo-max-kicks 1000 \
  --cuckoo-build-attempts 8 \
  --layout-path data/layout_with_stats_32_128.json \
  --index data/msmarco_reordered \
  --queries data/queries.dev.small.tsv \
  --qrels data/qrels.dev.small.tsv \
  --vocab data/stage1_vocab.json \
  --stage1-data-bin data/stage1_data.bin \
  --stage1-idmap-bin data/stage1/stage1_idmap.bin \
  --stage2-data-bin data/stage2/data.bin \
  --stage2-idmap-bin data/stage2/idmap.bin \
  --doc-embed data/stage3_doc_aligned_shuffle.npy \
  --doc-id-map data/stage3_doc_aligned.npy.ids \
  --query-embed data/stage3_query.npy \
  --embed-dim 192 \
  2>&1 | tee logs/cuckoo_100q_config3.log


  ./bm25-search \
  --L 400  --k_candidates 256  --query-words 6 --pir-constant-work \
  --B 32 \
  --r 128 \
  --s 8 \
  --k 10 \
  --max-queries 6980 \
  --k1 0.9 \
  --b 0.4 \
  --scale 10 \
  --precompute \
  --pir-batch-size 128 \
  --cuckoo-load-factor 0.4 \
  --cuckoo-max-kicks 1000 \
  --cuckoo-build-attempts 8 \
  --layout-path data/layout_with_stats_32_128.json \
  --index data/msmarco_reordered \
  --queries data/queries.dev.small.tsv \
  --qrels data/qrels.dev.small.tsv \
  --vocab data/stage1_vocab.json \
  --stage1-data-bin data/stage1_data.bin \
  --stage1-idmap-bin data/stage1/stage1_idmap.bin \
  --stage2-data-bin data/stage2/data.bin \
  --stage2-idmap-bin data/stage2/idmap.bin \
  --doc-embed data/stage3_doc_aligned_shuffle.npy \
  --doc-id-map data/stage3_doc_aligned.npy.ids \
  --query-embed data/stage3_query.npy \
  --embed-dim 192 \
  2>&1 | tee logs/cuckoo_100q_config4.log


  ./bm25-search \
  --L 400  --k_candidates 256  --query-words 8 --pir-constant-work \
  --B 32 \
  --r 128 \
  --s 8 \
  --k 10 \
  --max-queries 6980 \
  --k1 0.9 \
  --b 0.4 \
  --scale 10 \
  --precompute \
  --pir-batch-size 128 \
  --cuckoo-load-factor 0.4 \
  --cuckoo-max-kicks 1000 \
  --cuckoo-build-attempts 8 \
  --layout-path data/layout_with_stats_32_128.json \
  --index data/msmarco_reordered \
  --queries data/queries.dev.small.tsv \
  --qrels data/qrels.dev.small.tsv \
  --vocab data/stage1_vocab.json \
  --stage1-data-bin data/stage1_data.bin \
  --stage1-idmap-bin data/stage1/stage1_idmap.bin \
  --stage2-data-bin data/stage2/data.bin \
  --stage2-idmap-bin data/stage2/idmap.bin \
  --doc-embed data/stage3_doc_aligned_shuffle.npy \
  --doc-id-map data/stage3_doc_aligned.npy.ids \
  --query-embed data/stage3_query.npy \
  --embed-dim 192 \
  2>&1 | tee logs/cuckoo_100q_config5.log