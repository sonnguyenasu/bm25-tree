#!/usr/bin/env bash

# Build and package raw (pre-Cuckoo) MS MARCO PIR databases for arbitrary
# B:r:s configurations. Configurations with the same (B,r) share Stage 1 and
# their Stage-2 ID map, and are generated in one Lucene postings pass.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./prepare_msmarco_pir_bundle.sh [--plan] [B:r:s ...]

Examples:
  ./prepare_msmarco_pir_bundle.sh
  ./prepare_msmarco_pir_bundle.sh 64:128:4 64:128:8 32:64:4
  CONFIGURATIONS="64:128:4 32:64:8" ./prepare_msmarco_pir_bundle.sh
  ./prepare_msmarco_pir_bundle.sh --plan 24:64:6 24:64:8

With no configurations, the script builds the original bundle:
  64:128:4 64:128:8 64:128:16 16:128:8

Configuration format:
  B  document block size
  r  Stage-1 tree fanout (must be greater than 1)
  s  Stage-2 sub-block size (must divide B)

Environment overrides:
  CONFIGURATIONS  whitespace-separated B:r:s configurations
  INDEX           reordered Lucene index
  ARCHIVE         output zip path
  WORK_ROOT       resumable temporary-work directory
  R               fanout used only by the default configuration list
  SCALE, K1, BM25_B, PROGRESS_EVERY, PYSERINI_JAR

--plan validates configurations and prints the grouped Java invocations
without reading the index or creating files.
EOF
}

PLAN_ONLY=0
if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi
if [[ ${1:-} == "--plan" ]]; then
  PLAN_ONLY=1
  shift
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INDEX=${INDEX:-"$ROOT/msmarco_reordered"}
ARCHIVE=${ARCHIVE:-"$ROOT/msmarco_pir_bundle.zip"}
WORK_ROOT=${WORK_ROOT:-"$ROOT/.msmarco_pir_bundle_work"}
R=${R:-128}
SCALE=${SCALE:-10}
K1=${K1:-0.9}
BM25_B=${BM25_B:-0.4}
PROGRESS_EVERY=${PROGRESS_EVERY:-100000}
PYSERINI_JAR=${PYSERINI_JAR:-"/home/snguye63/.local/lib/python3.8/site-packages/pyserini/resources/jars/anserini-0.22.1-fatjar.jar"}
CLASSES="$ROOT/build/pir_builder/classes"
ARCHIVE=$(realpath -m -- "$ARCHIVE")
WORK_ROOT=$(realpath -m -- "$WORK_ROOT")
PARTIAL_ARCHIVE="${ARCHIVE%.zip}.partial.zip"
DEFAULT_CONFIGURATIONS="64:${R}:4 64:${R}:8 64:${R}:16 16:${R}:8"

if (( $# > 0 )); then
  CONFIGURATIONS="$*"
else
  CONFIGURATIONS=${CONFIGURATIONS:-"$DEFAULT_CONFIGURATIONS"}
fi

gcd() {
  local left=$1
  local right=$2
  local remainder
  while (( right != 0 )); do
    remainder=$((left % right))
    left=$right
    right=$remainder
  done
  printf '%d' "$left"
}

builder_subblocks() {
  local requested=$1
  local -a values
  local base
  local result
  local value

  IFS=, read -r -a values <<< "$requested"
  base=${values[0]}
  for value in "${values[@]:1}"; do
    base=$(gcd "$base" "$value")
  done

  # BuildPirDatabases aggregates every requested s from its smallest input
  # size. Include the GCD when the requested sizes do not form a divisibility
  # chain (for example, s=6 and s=8) so arbitrary divisors of B can share a
  # single postings pass.
  result=$base
  for value in "${values[@]}"; do
    if [[ ",$result," != *",$value,"* ]]; then
      result+=",$value"
    fi
  done
  printf '%s' "$result"
}

declare -a SPECIFICATIONS=()
declare -a NORMALIZED_CONFIGURATIONS=()
declare -a GROUP_KEYS=()
declare -A CONFIG_SEEN=()
declare -A GROUP_B=()
declare -A GROUP_R=()
declare -A GROUP_SUBBLOCKS=()
declare -A GROUP_ANCHOR=()

CONFIGURATIONS=${CONFIGURATIONS//$'\n'/ }
read -r -a SPECIFICATIONS <<< "$CONFIGURATIONS"
if (( ${#SPECIFICATIONS[@]} == 0 )); then
  echo "No configurations requested." >&2
  usage >&2
  exit 2
fi

for specification in "${SPECIFICATIONS[@]}"; do
  if [[ ! $specification =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
    echo "Invalid configuration '$specification'; expected B:r:s." >&2
    exit 2
  fi

  B=$((10#${BASH_REMATCH[1]}))
  FANOUT=$((10#${BASH_REMATCH[2]}))
  SUBBLOCK=$((10#${BASH_REMATCH[3]}))
  if (( B <= 0 || FANOUT <= 1 || SUBBLOCK <= 0 || B % SUBBLOCK != 0 )); then
    echo "Invalid configuration '$specification': require B>0, r>1, s>0, and B divisible by s." >&2
    exit 2
  fi

  NORMALIZED="${B}:${FANOUT}:${SUBBLOCK}"
  if [[ -n ${CONFIG_SEEN[$NORMALIZED]+x} ]]; then
    continue
  fi
  CONFIG_SEEN[$NORMALIZED]=1
  NORMALIZED_CONFIGURATIONS+=("$NORMALIZED")

  GROUP="${B}:${FANOUT}"
  if [[ -z ${GROUP_SUBBLOCKS[$GROUP]+x} ]]; then
    GROUP_KEYS+=("$GROUP")
    GROUP_B[$GROUP]=$B
    GROUP_R[$GROUP]=$FANOUT
    GROUP_SUBBLOCKS[$GROUP]=$SUBBLOCK
    GROUP_ANCHOR[$GROUP]=$SUBBLOCK
  else
    GROUP_SUBBLOCKS[$GROUP]+=",$SUBBLOCK"
  fi
done

echo "Requested MS MARCO PIR configurations:"
for NORMALIZED in "${NORMALIZED_CONFIGURATIONS[@]}"; do
  IFS=: read -r B FANOUT SUBBLOCK <<< "$NORMALIZED"
  printf '  B=%s r=%s s=%s\n' "$B" "$FANOUT" "$SUBBLOCK"
done
echo "Grouped builds:"
for GROUP in "${GROUP_KEYS[@]}"; do
  printf '  B=%s r=%s requested_s=%s builder_s=%s\n' \
    "${GROUP_B[$GROUP]}" \
    "${GROUP_R[$GROUP]}" \
    "${GROUP_SUBBLOCKS[$GROUP]}" \
    "$(builder_subblocks "${GROUP_SUBBLOCKS[$GROUP]}")"
done

if (( PLAN_ONLY == 1 )); then
  exit 0
fi

if [[ ! -d "$INDEX" ]]; then
  echo "Missing MS MARCO Lucene index: $INDEX" >&2
  exit 1
fi
if [[ ! -f "$PYSERINI_JAR" ]]; then
  echo "Missing Anserini jar: $PYSERINI_JAR" >&2
  exit 1
fi
if [[ -e "$ARCHIVE" ]]; then
  echo "Refusing to overwrite existing archive: $ARCHIVE" >&2
  exit 1
fi

mkdir -p "$CLASSES" "$WORK_ROOT"
STATE_FILE="$WORK_ROOT/configurations.txt"
EXPECTED_STATE=$(printf '%s\n' "${NORMALIZED_CONFIGURATIONS[@]}")
if [[ -f "$STATE_FILE" ]]; then
  EXISTING_STATE=$(<"$STATE_FILE")
  if [[ "$EXISTING_STATE" != "$EXPECTED_STATE" ]]; then
    echo "Work directory belongs to a different configuration set: $WORK_ROOT" >&2
    echo "Existing configurations:" >&2
    printf '  %s\n' "$EXISTING_STATE" >&2
    echo "Requested configurations:" >&2
    printf '  %s\n' "$EXPECTED_STATE" >&2
    exit 1
  fi
elif [[ -e "$PARTIAL_ARCHIVE" ]]; then
  echo "Cannot safely resume partial archive without $STATE_FILE" >&2
  exit 1
else
  printf '%s\n' "${NORMALIZED_CONFIGURATIONS[@]}" > "$STATE_FILE"
fi

javac -proc:none -cp "$PYSERINI_JAR" \
  -d "$CLASSES" "$ROOT/tools/BuildPirDatabases.java"

build_database() {
  local block_size=$1
  local fanout=$2
  local subblocks=$3
  local output=$4
  mkdir -p "$output"
  java -Xms256m -Xmx4g -cp "$CLASSES:$PYSERINI_JAR" BuildPirDatabases \
    --index "$INDEX" \
    --output "$output" \
    --B "$block_size" \
    --r "$fanout" \
    --s "$subblocks" \
    --scale "$SCALE" \
    --k1 "$K1" \
    --b "$BM25_B" \
    --progress-every "$PROGRESS_EVERY"
}

stage_common() {
  local source=$1
  local destination=$2
  mkdir -p "$destination"
  ln "$source/layout.json" "$destination/layout.json"
  ln "$source/stage1_data.bin" "$destination/stage1_data.bin"
  ln "$source/stage1_idmap.bin" "$destination/stage1_idmap.bin"
  ln "$source/stage1_vocab.json" "$destination/stage1_vocab.json"
}

write_bundle_readme() {
  local destination=$1
  local configuration
  cp "$ROOT/MSMARCO_PIR_BUNDLE_README.txt" "$destination"
  {
    echo
    echo "Configurations included in this archive:"
    for configuration in "${NORMALIZED_CONFIGURATIONS[@]}"; do
      echo "  $configuration"
    done
  } >> "$destination"
}

for GROUP in "${GROUP_KEYS[@]}"; do
  B=${GROUP_B[$GROUP]}
  FANOUT=${GROUP_R[$GROUP]}
  REQUESTED_SUBBLOCKS=${GROUP_SUBBLOCKS[$GROUP]}
  ANCHOR_SUBBLOCK=${GROUP_ANCHOR[$GROUP]}
  BUILDER_SUBBLOCKS=$(builder_subblocks "$REQUESTED_SUBBLOCKS")
  GROUP_NAME="B${B}_r${FANOUT}"
  MARKER="$WORK_ROOT/${GROUP_NAME}.archived"

  if [[ -f "$MARKER" ]]; then
    echo "Already archived $GROUP_NAME; resuming with the next group."
    continue
  fi

  BUILD_ROOT="$WORK_ROOT/build_${GROUP_NAME}"
  ARCHIVE_ROOT="$WORK_ROOT/archive_${GROUP_NAME}"
  PIR_TREE="$ARCHIVE_ROOT/data/msmarco/pir"
  ANCHOR_NAME="${GROUP_NAME}_s${ANCHOR_SUBBLOCK}"
  ANCHOR_TREE="$PIR_TREE/$ANCHOR_NAME"

  rm -rf -- "$BUILD_ROOT" "$ARCHIVE_ROOT"
  build_database "$B" "$FANOUT" "$BUILDER_SUBBLOCKS" "$BUILD_ROOT"

  stage_common "$BUILD_ROOT" "$ANCHOR_TREE"
  mkdir -p "$ANCHOR_TREE/stage2"
  ln "$BUILD_ROOT/stage2_s${ANCHOR_SUBBLOCK}/data.bin" "$ANCHOR_TREE/stage2/data.bin"
  ln "$BUILD_ROOT/stage2_idmap.bin" "$ANCHOR_TREE/stage2/idmap.bin"

  IFS=, read -r -a SUBBLOCK_VALUES <<< "$REQUESTED_SUBBLOCKS"
  for SUBBLOCK in "${SUBBLOCK_VALUES[@]}"; do
    if (( SUBBLOCK == ANCHOR_SUBBLOCK )); then
      continue
    fi
    CONFIG_NAME="${GROUP_NAME}_s${SUBBLOCK}"
    CONFIG_TREE="$PIR_TREE/$CONFIG_NAME"
    mkdir -p "$CONFIG_TREE/stage2"
    ln -s "../${ANCHOR_NAME}/layout.json" "$CONFIG_TREE/layout.json"
    ln -s "../${ANCHOR_NAME}/stage1_data.bin" "$CONFIG_TREE/stage1_data.bin"
    ln -s "../${ANCHOR_NAME}/stage1_idmap.bin" "$CONFIG_TREE/stage1_idmap.bin"
    ln -s "../${ANCHOR_NAME}/stage1_vocab.json" "$CONFIG_TREE/stage1_vocab.json"
    ln "$BUILD_ROOT/stage2_s${SUBBLOCK}/data.bin" "$CONFIG_TREE/stage2/data.bin"
    ln -s "../../${ANCHOR_NAME}/stage2/idmap.bin" "$CONFIG_TREE/stage2/idmap.bin"
  done

  write_bundle_readme "$PIR_TREE/README.txt"
  (
    cd "$ARCHIVE_ROOT"
    zip -1 -r -y "$PARTIAL_ARCHIVE" data
  )
  unzip -tq "$PARTIAL_ARCHIVE"
  touch "$MARKER"
  rm -rf -- "$BUILD_ROOT" "$ARCHIVE_ROOT"
done

unzip -tq "$PARTIAL_ARCHIVE"
mv -- "$PARTIAL_ARCHIVE" "$ARCHIVE"
rm -- "$STATE_FILE"
for GROUP in "${GROUP_KEYS[@]}"; do
  rm -- "$WORK_ROOT/B${GROUP_B[$GROUP]}_r${GROUP_R[$GROUP]}.archived"
done
rmdir "$WORK_ROOT"

echo "Created: $ARCHIVE"
du -h "$ARCHIVE"
unzip -l "$ARCHIVE" | tail -n 5
