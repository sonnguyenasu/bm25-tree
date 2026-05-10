# Stage3 ID Alignment Guide (TREC-COVID and Similar Datasets)

This document explains how Stage3 expects document/query IDs to align with embeddings, why a query-ID map is needed, and how to apply the same pattern to other datasets.

## Background

Stage3 reranking uses dense embeddings with this data flow:

- Document embeddings: `doc_embed.npy` with a matching `doc_embed.npy.ids` file.
- Query embeddings: `query_embed.npy` with a matching `query_embed.npy.ids` file.
- Stage2 hitSubBlocks: ranges of *internal* doc IDs from the BM25/Lucene index.

TREC-COVID embeddings (from the Colab notebook) are generated from:
- `collection.tsv` for documents (docid + text).
- `queries.tsv` for queries (qid + text).

The notebook writes the `.ids` files in the same order as the embedding rows. This means:
- The line number in `doc_embed.npy.ids` is the embedding row index.
- The line number in `query_embed.npy.ids` is the embedding row index.

## What Changed in Stage3

Stage3 now loads a query ID map from `query_embed.npy.ids` and uses it to select the correct query embedding for each query ID. This avoids relying on the query iteration order in the Go pipeline.

Implementation points:
- Query ID map is loaded by Stage3 at initialization time.
- During rerank, Stage3 uses `QueryIDMap[queryID]` when available, otherwise falls back to the query index.

Files:
- `internal/bm25/stage3.go` loads the query ID map.
- `cmd/main.go` uses the map to choose the correct query embedding for each query.

## Why This Matters

If the Go pipeline's query order differs from the embedding generation order, the wrong query embedding will be used. This can zero out MRR even when Stage2 contains gold documents. The query ID map fixes that mismatch.

For documents:
- If you do not have a `docmap.bin`, Stage3 expects `doc_embed.npy.ids` to be aligned to internal doc IDs.
- If `doc_embed.npy.ids` is aligned to *external* IDs (string IDs), Stage3 can still rerank as long as it uses the same external ID strings in the gold set and in Stage3 outputs.

## How to Apply to a New Dataset

1. Generate document embeddings and write `doc_embed.npy.ids` in the same order as rows.
   - Use the same doc IDs that appear in qrels (string IDs are fine).

2. Generate query embeddings and write `query_embed.npy.ids` in the same order as rows.
   - The query IDs must match those in qrels and in `queries.tsv`.

3. Ensure Stage3 loads the query ID map:
   - `query_embed.npy.ids` must sit next to `query_embed.npy` with the same prefix.

4. When running:
   - Use `--doc-embed`, `--doc-id-map`, and `--query-embed` pointing to the aligned files.

## TREC-COVID Specific Notes

The Colab notebook writes:
- `my_vectors_384_float32.npy` + `.ids` from `collection.tsv`.
- `query_384_float32.npy` + `.ids` from `queries.tsv`.

If you use these files directly, Stage3 will be consistent as long as the query ID map is used.

## Quick Validation Checklist

- `len(query_embed.npy.ids)` equals number of query embeddings.
- `len(doc_embed.npy.ids)` equals number of document embeddings.
- Sample query IDs from `query_embed.npy.ids` exist in qrels.
- Sample doc IDs from `doc_embed.npy.ids` exist in qrels.

## Common Pitfalls

- Query embeddings generated in a different order than the Go pipeline uses.
- Mixing internal numeric IDs and external string IDs between stages.
- Missing `.ids` files or mismatched file prefixes.

## Recommended Practice

Always keep `query_embed.npy.ids` and use the query ID map in Stage3. This is the most robust way to avoid ordering bugs across datasets and pipelines.
