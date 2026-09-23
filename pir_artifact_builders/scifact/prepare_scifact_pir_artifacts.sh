#!/usr/bin/env bash

# Build the raw (pre-Cuckoo) SciFact Stage-1 and Stage-2 databases used by
# run_pir_scifact.sh. Physical Cuckoo tables are deliberately not built here.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PYTHON_BIN=${PYTHON_BIN:-python3}
INDEX=${INDEX:-"$ROOT/indexes/scifact"}
DATA_ROOT=${DATA_ROOT:-"$ROOT/data/scifact"}
PIR_DATA_ROOT=${PIR_DATA_ROOT:-"$DATA_ROOT/pir"}
N=${N:-5183}
R=${R:-128}
SCALE=${SCALE:-10}

mkdir -p "$PIR_DATA_ROOT"

# Unique (B,s) layouts required by the current C1--C5 selections.
CONFIGURATIONS=("8:2" "16:4" "32:2")

for specification in "${CONFIGURATIONS[@]}"; do
  IFS=: read -r B S <<< "$specification"
  CONFIG_DIR="$PIR_DATA_ROOT/B${B}_r${R}_s${S}"
  LAYOUT="$CONFIG_DIR/layout.json"
  STAGE1_PREFIX="$CONFIG_DIR/stage1"
  STAGE2_DIR="$CONFIG_DIR/stage2"
  mkdir -p "$CONFIG_DIR" "$STAGE2_DIR"

  if [[ ! -s "$LAYOUT" ]]; then
    "$PYTHON_BIN" "$ROOT/gen_layout.py" "$N" "$B" "$R" "$LAYOUT"
  fi

  if [[ ! -s "${STAGE1_PREFIX}_data.bin" \
     || ! -s "${STAGE1_PREFIX}_idmap.bin" \
     || ! -s "${STAGE1_PREFIX}_vocab.json" ]]; then
    "$PYTHON_BIN" "$ROOT/prepare_data.py" \
      --index "$INDEX" \
      --terms-from-index \
      --layout-stats "$LAYOUT" \
      --out-prefix "$STAGE1_PREFIX" \
      --B "$B" \
      --r "$R" \
      --scale "$SCALE" \
      --k1 0.9 \
      --bparam 0.4
  fi

  if [[ ! -s "$STAGE2_DIR/data.bin" || ! -s "$STAGE2_DIR/idmap.bin" ]]; then
    "$PYTHON_BIN" "$ROOT/prepare_data_stage2.py" \
      --index "$INDEX" \
      --vocab "${STAGE1_PREFIX}_vocab.json" \
      --out-dir "$STAGE2_DIR" \
      --layout-stats "$LAYOUT" \
      --B "$B" \
      --r "$R" \
      --s "$S" \
      --scale "$SCALE" \
      --bm25-k1 0.9 \
      --bm25-b 0.4
  fi
done

echo "SciFact raw PIR artifacts are ready under: $PIR_DATA_ROOT"
