#!/usr/bin/env bash
set -euo pipefail

# Collect runtime + Cachegrind metrics for pointer vs CSR BFS and clean artifacts.
# Supports graph generation or using an existing graph file, repeat sweeps,
# and reduced/full cache-parameter runs.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_CSV="$ROOT_DIR/metrics.csv"

# Graph selection
GRAPH_PATH=""
GRAPH_KIND="star"
N=20000
ROWS=0
COLS=0
DEG=4
SEED=1
SOURCE=0

# Repeat configuration (single values by default)
RUNTIME_REPEAT=100
CG_REPEAT=50
RUNTIME_REPEAT_LIST=""
CG_REPEAT_LIST=""

# Execution configuration
IMPLS="both"
CACHE_PROFILE="full"
KEEP_BUILD=0
KEEP_GRAPH=0
RUN_CACHEGRIND=1

# Cache hierarchy configuration
I1_CONF="32768,8,64"
LL_CONF="8388608,16,64"

GRAPH_FILE=""
GRAPH_N=0
TMP_DIR=""

usage() {
  cat <<'EOF'
Collect BFS metrics and write CSV.

Options:
  --out PATH             Output CSV path (default: metrics.csv)
  --graph PATH           Use existing graph file instead of generating one
  --kind KIND            Generated graph kind: star|chain|grid|er (default: star)
  --n INT                Number of vertices for star/chain/er graphs (default: 20000)
  --rows INT             Rows for grid graphs
  --cols INT             Cols for grid graphs
  --deg INT              Out-degree for er graphs (default: 4)
  --seed INT             RNG seed for er graphs (default: 1)
  --source INT           BFS source vertex (default: 0)
  --impl IMPL            pointer|csr|both (default: both)
  --runtime-repeat INT   Single repeat count for runtime rows (default: 100)
  --cg-repeat INT        Single repeat count for cachegrind rows (default: 50)
  --runtime-repeat-list L  Comma-separated runtime repeat sweep (overrides --runtime-repeat)
  --cg-repeat-list L       Comma-separated cachegrind repeat sweep (overrides --cg-repeat)
  --cache-profile P      baseline|full cache sweeps (default: full)
  --keep-build           Do not run make clean at end
  --keep-graph           Keep generated graph file (ignored when --graph is used)
  --skip-cachegrind      Collect runtime rows only (no valgrind required)
  -h, --help             Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_CSV="$2"
      shift 2
      ;;
    --graph)
      GRAPH_PATH="$2"
      shift 2
      ;;
    --kind)
      GRAPH_KIND="$2"
      shift 2
      ;;
    --n)
      N="$2"
      shift 2
      ;;
    --rows)
      ROWS="$2"
      shift 2
      ;;
    --cols)
      COLS="$2"
      shift 2
      ;;
    --deg)
      DEG="$2"
      shift 2
      ;;
    --seed)
      SEED="$2"
      shift 2
      ;;
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --impl)
      IMPLS="$2"
      shift 2
      ;;
    --runtime-repeat)
      RUNTIME_REPEAT="$2"
      shift 2
      ;;
    --cg-repeat)
      CG_REPEAT="$2"
      shift 2
      ;;
    --runtime-repeat-list)
      RUNTIME_REPEAT_LIST="$2"
      shift 2
      ;;
    --cg-repeat-list)
      CG_REPEAT_LIST="$2"
      shift 2
      ;;
    --cache-profile)
      CACHE_PROFILE="$2"
      shift 2
      ;;
    --keep-build)
      KEEP_BUILD=1
      shift
      ;;
    --keep-graph)
      KEEP_GRAPH=1
      shift
      ;;
    --skip-cachegrind)
      RUN_CACHEGRIND=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$GRAPH_KIND" in
  star|chain|grid|er) ;;
  *)
    echo "--kind must be one of: star, chain, grid, er" >&2
    exit 1
    ;;
esac

case "$IMPLS" in
  pointer|csr|both) ;;
  *)
    echo "--impl must be one of: pointer, csr, both" >&2
    exit 1
    ;;
esac

case "$CACHE_PROFILE" in
  baseline|full) ;;
  *)
    echo "--cache-profile must be one of: baseline, full" >&2
    exit 1
    ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi
if [[ "$RUN_CACHEGRIND" -eq 1 ]] && ! command -v valgrind >/dev/null 2>&1; then
  echo "valgrind is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_CSV")"
mkdir -p "$ROOT_DIR/data"

cleanup() {
  rm -rf "$TMP_DIR"
  rm -f "$ROOT_DIR"/cachegrind.out.*
  if [[ "$KEEP_GRAPH" -eq 0 && -n "$GRAPH_FILE" && -z "$GRAPH_PATH" ]]; then
    rm -f "$GRAPH_FILE"
  fi
  if [[ "$KEEP_BUILD" -eq 0 ]]; then
    make -C "$ROOT_DIR" clean >/dev/null 2>&1 || true
  fi
}

TMP_DIR="$(mktemp -d)"
trap cleanup EXIT

avg_bfs_only_ms() {
  local total_ms="$1"
  local conversion_ms="$2"
  local repeat="$3"
  awk -v t="$total_ms" -v c="$conversion_ms" -v r="$repeat" '
    BEGIN {
      bfs_total = t - c;
      if (bfs_total < 0) bfs_total = 0;
      printf "%.6f", bfs_total / r;
    }
  '
}

run_graph_bench() {
  local impl="$1"
  local repeat="$2"
  "$ROOT_DIR/graph_bench" --impl="$impl" --graph="$GRAPH_FILE" --source="$SOURCE" --repeat="$repeat"
}

collect_runtime_row() {
  local impl="$1"
  local repeat="$2"
  local scope="$3"
  local output visited total_ms conversion_ms avg
  output="$(run_graph_bench "$impl" "$repeat")"
  visited="$(echo "$output" | awk -F= '/^visited=/{print $2; exit}')"
  conversion_ms="$(echo "$output" | awk -F= '/^conversion_ms=/{print $2; exit}')"
  if [[ -z "$conversion_ms" ]]; then
    conversion_ms="0"
  fi
  total_ms="$(echo "$output" | awk -F= '/^time_ms=/{print $2; exit}')"
  avg="$(avg_bfs_only_ms "$total_ms" "$conversion_ms" "$repeat")"

  printf 'runtime,%s,%s,%s,%s,%s,%s,%s,,%s,%s,,,,,,,\n' \
    "$scope" "$GRAPH_KIND" "$(basename "$GRAPH_FILE")" "$impl" "$GRAPH_N" "$SOURCE" "$repeat" "$visited" "$avg"
}

collect_cachegrind_row() {
  local scope="$1"
  local impl="$2"
  local d1_conf="$3"
  local repeat="$4"
  local cache_cfg="I1=${I1_CONF};D1=${d1_conf};LL=${LL_CONF}"
  local d1_tag
  d1_tag="$(echo "$d1_conf" | tr ',' '_')"

  local run_log="$TMP_DIR/run_${scope}_${impl}.log"
  local cg_out="$TMP_DIR/cachegrind.out.${scope}.${impl}.${d1_tag}.%p"

  valgrind --tool=cachegrind \
    --cache-sim=yes \
    --cachegrind-out-file="$cg_out" \
    --I1="$I1_CONF" \
    --D1="$d1_conf" \
    --LL="$LL_CONF" \
    "$ROOT_DIR/graph_bench" --impl="$impl" --graph="$GRAPH_FILE" --source="$SOURCE" --repeat="$repeat" \
    >"$run_log" 2>&1

  local resolved_cg
  resolved_cg="$(find "$TMP_DIR" -type f -name "cachegrind.out.${scope}.${impl}.${d1_tag}.*" | head -n 1)"
  if [[ -z "$resolved_cg" ]]; then
    echo "Failed to locate cachegrind output for ${scope}/${impl}" >&2
    exit 1
  fi

  # Parse raw cachegrind.out directly based on the "events:" mapping
  local totals
  totals="$(awk '
    /^events:/ {
      for(i=2; i<=NF; i++) ev[i] = $i;
    }
    /^summary:/ {
      for(i=2; i<=NF; i++) val[ev[i]] = $i;
      if (!("D1mr" in val) || !("D1mw" in val) || !("DLmr" in val) || !("DLmw" in val)) {
        exit 2;
      }
      print val["D1mr"]+0, val["D1mw"]+0, val["DLmr"]+0, val["DLmw"]+0;
      exit
    }
  ' "$resolved_cg")"

  if [[ -z "$totals" ]]; then
    echo "Failed to parse cachegrind miss counters for ${scope}/${impl}. Ensure cache simulation is enabled." >&2
    exit 1
  fi

  local d1_rd d1_wr lld_rd lld_wr
  read -r d1_rd d1_wr lld_rd lld_wr <<<"$totals"

  local d1_total lld_total d1_per_run lld_per_run
  d1_total=$((d1_rd + d1_wr))
  lld_total=$((lld_rd + lld_wr))
  d1_per_run="$(awk -v t="$d1_total" -v r="$repeat" 'BEGIN { printf "%.2f", t / r }')"
  lld_per_run="$(awk -v t="$lld_total" -v r="$repeat" 'BEGIN { printf "%.2f", t / r }')"

  local visited total_ms conversion_ms avg
  visited="$(awk -F= '/^visited=/{print $2; exit}' "$run_log")"
  conversion_ms="$(awk -F= '/^conversion_ms=/{print $2; exit}' "$run_log")"
  if [[ -z "$conversion_ms" ]]; then
    conversion_ms="0"
  fi
  total_ms="$(awk -F= '/^time_ms=/{print $2; exit}' "$run_log")"
  avg="$(avg_bfs_only_ms "$total_ms" "$conversion_ms" "$repeat")"

  printf 'cachegrind,%s,%s,%s,%s,%s,%s,%s,"%s",%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$scope" "$GRAPH_KIND" "$(basename "$GRAPH_FILE")" "$impl" "$GRAPH_N" "$SOURCE" "$repeat" "$cache_cfg" "$visited" "$avg" \
    "$d1_total" "$d1_per_run" "$lld_total" "$lld_per_run" \
    "$d1_rd" "$d1_wr" "$lld_rd" "$lld_wr"
}

emit_for_impls_runtime() {
  local repeat="$1"
  local scope="$2"
  if [[ "$IMPLS" == "both" || "$IMPLS" == "pointer" ]]; then
    collect_runtime_row "pointer" "$repeat" "$scope"
  fi
  if [[ "$IMPLS" == "both" || "$IMPLS" == "csr" ]]; then
    collect_runtime_row "csr" "$repeat" "$scope"
  fi
}

emit_for_impls_cachegrind() {
  local scope="$1"
  local d1_conf="$2"
  local repeat="$3"
  if [[ "$IMPLS" == "both" || "$IMPLS" == "pointer" ]]; then
    collect_cachegrind_row "$scope" "pointer" "$d1_conf" "$repeat"
  fi
  if [[ "$IMPLS" == "both" || "$IMPLS" == "csr" ]]; then
    collect_cachegrind_row "$scope" "csr" "$d1_conf" "$repeat"
  fi
}

prepare_graph() {
  if [[ -n "$GRAPH_PATH" ]]; then
    if [[ ! -f "$GRAPH_PATH" ]]; then
      echo "Graph file does not exist: $GRAPH_PATH" >&2
      exit 1
    fi
    GRAPH_FILE="$GRAPH_PATH"
    GRAPH_KIND="custom"
    GRAPH_N="$(head -n 1 "$GRAPH_FILE")"
    return
  fi

  case "$GRAPH_KIND" in
    grid)
      if [[ "$ROWS" -le 0 || "$COLS" -le 0 ]]; then
        echo "Grid generation requires --rows > 0 and --cols > 0" >&2
        exit 1
      fi
      GRAPH_N=$((ROWS * COLS))
      GRAPH_FILE="$ROOT_DIR/data/.metrics_grid_${ROWS}x${COLS}.txt"
      echo "Generating grid graph (${ROWS}x${COLS})..."
      python3 "$ROOT_DIR/scripts/gen_graph.py" --kind grid --rows "$ROWS" --cols "$COLS" --out "$GRAPH_FILE"
      ;;
    er)
      if [[ "$N" -le 0 ]]; then
        echo "ER generation requires --n > 0" >&2
        exit 1
      fi
      GRAPH_N="$N"
      GRAPH_FILE="$ROOT_DIR/data/.metrics_er_n${N}_deg${DEG}_seed${SEED}.txt"
      echo "Generating er graph (n=$N, deg=$DEG, seed=$SEED)..."
      python3 "$ROOT_DIR/scripts/gen_graph.py" --kind er --n "$N" --deg "$DEG" --seed "$SEED" --out "$GRAPH_FILE"
      ;;
    star|chain)
      if [[ "$N" -le 0 ]]; then
        echo "Graph generation requires --n > 0" >&2
        exit 1
      fi
      GRAPH_N="$N"
      GRAPH_FILE="$ROOT_DIR/data/.metrics_${GRAPH_KIND}_${N}.txt"
      echo "Generating $GRAPH_KIND graph (n=$N)..."
      python3 "$ROOT_DIR/scripts/gen_graph.py" --kind "$GRAPH_KIND" --n "$N" --out "$GRAPH_FILE"
      ;;
  esac
}

repeats_to_words() {
  local list="$1"
  local fallback="$2"
  if [[ -z "$list" ]]; then
    echo "$fallback"
  else
    echo "$list" | tr ',' ' '
  fi
}

echo "Building benchmark..."
make -C "$ROOT_DIR" clean >/dev/null
make -C "$ROOT_DIR" >/dev/null

prepare_graph

RUNTIME_REPEATS_WORDS="$(repeats_to_words "$RUNTIME_REPEAT_LIST" "$RUNTIME_REPEAT")"
CG_REPEATS_WORDS="$(repeats_to_words "$CG_REPEAT_LIST" "$CG_REPEAT")"

echo "Collecting metrics..."
{
  echo "measurement,scope,graph_kind,graph_file,impl,n,source,repeat,cache_config,visited,time_ms_avg,d1_misses_total,d1_misses_per_run,lld_misses_total,lld_misses_per_run,d1_rd_misses_total,d1_wr_misses_total,lld_rd_misses_total,lld_wr_misses_total"

  for repeat in $RUNTIME_REPEATS_WORDS; do
    runtime_scope="bfs_only"
    if [[ -n "$RUNTIME_REPEAT_LIST" ]]; then
      runtime_scope="repeat_sweep"
    fi
    emit_for_impls_runtime "$repeat" "$runtime_scope"
  done

  if [[ "$RUN_CACHEGRIND" -eq 1 ]]; then
    for repeat in $CG_REPEATS_WORDS; do
      if [[ "$CACHE_PROFILE" == "baseline" ]]; then
        cache_scope="baseline"
        if [[ -n "$CG_REPEAT_LIST" ]]; then
          cache_scope="repeat_sweep_cache"
        fi
        emit_for_impls_cachegrind "$cache_scope" "32768,8,64" "$repeat"
      else
        emit_for_impls_cachegrind "baseline" "32768,8,64" "$repeat"

        emit_for_impls_cachegrind "cache_size" "16384,8,64" "$repeat"
        emit_for_impls_cachegrind "cache_size" "32768,8,64" "$repeat"
        emit_for_impls_cachegrind "cache_size" "65536,8,64" "$repeat"

        emit_for_impls_cachegrind "associativity" "32768,1,64" "$repeat"
        emit_for_impls_cachegrind "associativity" "32768,2,64" "$repeat"
        emit_for_impls_cachegrind "associativity" "32768,4,64" "$repeat"
        emit_for_impls_cachegrind "associativity" "32768,8,64" "$repeat"

        emit_for_impls_cachegrind "line_size" "32768,8,32" "$repeat"
        emit_for_impls_cachegrind "line_size" "32768,8,64" "$repeat"
        emit_for_impls_cachegrind "line_size" "32768,8,128" "$repeat"
      fi
    done
  fi
} > "$OUT_CSV"

echo "Wrote metrics: $OUT_CSV"