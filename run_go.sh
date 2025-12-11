#!/bin/bash
export PATH=$PATH:/usr/local/go/bin
go build -o bm25-search ./cmd

./bm25-search --qrels data/qrels.dev.small.tsv --index data/msmarco_reordered --queries data/queries.dev.small.tsv --max-queries 100 --debug --precompute --doc-embed stage3_doc.npy --doc-id-map stage3_doc.npy.ids --query-embed stage3_query.npy --embed-dim 192 --stage1-data-bin data/stage1_data.bin --stage1-idmap-bin data/stage1/stage1_idmap.bin --vocab data/stage1_vocab.json --query-words 4 --pir-batch-size 1024 2>&1
