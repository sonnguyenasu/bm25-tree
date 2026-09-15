# BM25 MSMarco

This is a Go implementation of BM25 ranking for the MSMarco dataset, converted from the Python implementation.

## Prerequisites

1. Install Go:
   - For Ubuntu/Debian: `sudo apt-get install golang-go`
   - For macOS: `brew install go`
   - For Windows: Download installer from [golang.org](https://golang.org/dl/)

2. Verify installation:
   ```bash
   go version
   ```

## Project Structure

```
.
├── cmd/            # Command-line applications
├── internal/       # Private application and library code
│   └── bm25/      # BM25 tree implementation
├── go.mod         # Go module definition
├── run_go.sh.     # build and run script 
└── README.md      # Project documentation
```

## Getting Started

1. Clone the repository
2. Navigate to the project directory
3. Download the data folder at [Google Drive](https://drive.google.com/file/d/1hqjyfew5o6QWGynvUshe44GvPLyX1NwH/view?usp=sharing)
3. Initialize the Go module:
   ```bash
   go mod init bm25-msmarco
   ```
4. Run the application (once implemented):
   ```bash
   ./run_go
   ```

## Faithful Cuckoo/PIR database layout

With `--precompute`, Stage 1 and Stage 2 use physical two-hash Cuckoo tables
instead of treating the compact score files as dense PIR databases:

- Stage 1 constructs one independent database and one BatchPIR instance per
  tree expansion level. A nonempty slot is `(term_id, parent_node_id, r child
  scores)`; every online logical lookup reads both candidate slots and accepts
  a value only when the returned key matches.
- Stage 2 constructs a separate table with slots `(term_id, leaf_node_id, B/s
  sub-block scores)` and uses the same two-probe/key-check rule.
- Empty slots are zero. Query padding uses OOV keys, so it generates the same
  two probes without changing the BM25 score.

The default Cuckoo load factor is the paper's `alpha=0.4`. The implementation
builds these physical tables from the existing `data.bin`/`idmap.bin` score
artifacts at startup. Since the full tables are large, persist them between
runs with:

```bash
./bm25-search ... \
  --precompute \
  --cuckoo-cache-dir /path/with/enough/free/space \
  --cuckoo-load-factor 0.4
```

Relevant controls are `--cuckoo-max-kicks`, `--cuckoo-build-attempts`, and
`--pir-batch-size`. `--strict-pir` additionally compares PIR responses with
the local table and is intended for diagnostics. `--disable-pir` preserves the
old direct-access path for accuracy comparison. With `--debug`, each online
stage logs its logical lookup count, physical two-probe count, table slots, and
entry width.

Use `--pir-constant-work` for latency experiments where repeated query rows
must not become much faster through Piano's client cache. It pads every
partition to a public high-probability occupancy bound, performs dummy server
work for cached rows, and scans the complete primary hint table. The bound has
at most a 2^-16 union-bound overflow probability per BatchPIR call; an overflow
is reported as an error instead of silently dropping a request. This mode is
slower than the default workload-sensitive mode.

Use `--pir-threads N` to process independent BatchPIR partitions concurrently
during preprocessing and online retrieval. Query order remains sequential
inside each partition because Piano updates client state after every query.
For a 64-partition Stage 1/2 database, `--pir-threads 32` is a practical
starting point; Stage 3 currently has 16 partitions and therefore uses at most
16 of those workers.
