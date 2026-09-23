# Minimal Stage-1/2 artifact builders

This directory contains the minimum repository code needed to generate raw
BM25Tree Stage-1 and Stage-2 artifacts from an existing Lucene index.

It intentionally excludes:

- Corpus download and Lucene indexing code.
- Document and query embedding generation.
- Queries, qrels, indexes, and embedding data.
- The `bm25-search` runtime binary.
- Physical Cuckoo caches.

## Contents

```text
pir_artifact_builders/
├── README.md
├── msmarco/
│   ├── prepare_msmarco_pir_bundle.sh
│   ├── MSMARCO_PIR_BUNDLE_README.txt
│   └── tools/
│       └── BuildPirDatabases.java
└── scifact/
    ├── prepare_scifact_pir_artifacts.sh
    ├── gen_layout.py
    ├── prepare_data.py
    └── prepare_data_stage2.py
```

These are standalone snapshots of the corresponding files at the repository
root. If a root implementation changes, refresh its copy here as well.

## MS MARCO

Required external inputs and programs:

- A reordered MS MARCO Lucene index.
- The Anserini fat JAR matching the index/Pyserini version.
- Bash 5, a JDK, `zip`, and `unzip`.

Run from the copied MS MARCO directory:

```bash
cd pir_artifact_builders/msmarco

INDEX=/absolute/path/to/msmarco_reordered \
ARCHIVE=/absolute/path/to/msmarco_pir_bundle.zip \
PYSERINI_JAR=/absolute/path/to/anserini-0.22.1-fatjar.jar \
./prepare_msmarco_pir_bundle.sh
```

Pass `B:r:s` triples for a custom bundle:

```bash
INDEX=/absolute/path/to/msmarco_reordered \
ARCHIVE=/absolute/path/to/msmarco_custom_pir_bundle.zip \
PYSERINI_JAR=/absolute/path/to/anserini-0.22.1-fatjar.jar \
./prepare_msmarco_pir_bundle.sh \
  32:64:4 \
  32:64:8 \
  64:128:16
```

Use `--plan` before the full build to validate and group configurations
without reading the index:

```bash
./prepare_msmarco_pir_bundle.sh --plan 32:64:4 32:64:8
```

The wrapper compiles `tools/BuildPirDatabases.java`, generates Stage-1 and
Stage-2 files once per unique `(B,r)`, shares common files with relative
symbolic links, and produces a validated zip archive.

## SciFact

Required external inputs and programs:

- An existing clustered SciFact Lucene index, normally
  `indexes/scifact/`.
- Python 3 with NumPy, Pyserini, PyJNIus, and tqdm.

Run from the copied SciFact directory:

```bash
cd pir_artifact_builders/scifact

INDEX=/absolute/path/to/indexes/scifact \
PIR_DATA_ROOT=/absolute/path/to/output/scifact/pir \
PYTHON_BIN=/absolute/path/to/python \
./prepare_scifact_pir_artifacts.sh
```

The wrapper creates the current three layouts:

| Directory | B | r | s |
|---|---:|---:|---:|
| `B8_r128_s2` | 8 | 128 | 2 |
| `B16_r128_s4` | 16 | 128 | 4 |
| `B32_r128_s2` | 32 | 128 | 2 |

It calls `gen_layout.py`, `prepare_data.py`, and
`prepare_data_stage2.py`. Existing nonempty outputs are reused.

Only the Stage-1/2 artifacts are produced. To run retrieval, separately
provide the Lucene index and document map, queries and qrels, aligned document
and query embeddings, block permutation, and `bm25-search` executable.
