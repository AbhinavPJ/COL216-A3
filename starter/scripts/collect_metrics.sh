#!/usr/bin/env bash
set -euo pipefail

# Collect runtime + Cachegrind metrics for pointer vs CSR BFS and clean artifacts.
# Usage:
#   scripts/collect_metrics.sh [--out metrics.csv] [--n 20000] [--runtime-repeat 100] [--cg-repeat 50]
# Optional:
#   --keep-build      Keep graph_bench and object files after run
#   --keep-graph      Keep generated input graph under data/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_CSV="$ROOT_DIR/metrics.csv"
N=20000
RUNTIME_REPEAT=100
CG_REPEAT=50
KEEP_BUILD=0
KEEP_GRAPH=0

I1_CONF="32768,8,64"
LL_CONF="8388608,16,64"

usage() {
  cat <<'EOF'
Collect BFS metrics and write CSV.

Options:
  --out PATH             Output CSV path (default: metrics.csv)
  --n INT                Number of vertices for star graph (default: 20000)
  --runtime-repeat INT   Repeat count for runtime rows (default: 100)
  --cg-repeat INT        Repeat count for cachegrind rows (default: 50)
  --keep-build           Do not run make clean at end
  --keep-graph           Keep generated graph file
  -h, --help             Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_CSV="$2"
      shift 2
      ;;
    --n)
      N="$2"
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
    --keep-build)
      KEEP_BUILD=1
      shift
      ;;
    --keep-graph)
      KEEP_GRAPH=1
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi
if ! command -v valgrind >/dev/null 2>&1; then
  echo "valgrind is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_CSV")"
mkdir -p "$ROOT_DIR/data"

GRAPH_FILE="$ROOT_DIR/data/.metrics_star_${N}.txt"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
  rm -f "$ROOT_DIR"/cachegrind.out.*
  if [[ "$KEEP_GRAPH" -eq 0 ]]; then
    rm -f "$GRAPH_FILE"
  fi
  if [[ "$KEEP_BUILD" -eq 0 ]]; then
    make -C "$ROOT_DIR" clean >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

to_plain_int() {
  echo "$1" | tr -d ','
}

avg_ms() {
  local total_ms="$1"
  local repeat="$2"
  awk -v t="$total_ms" -v r="$repeat" 'BEGIN { printf "%.6f", t / r }'
}

run_graph_bench() {
  local impl="$1"
  local repeat="$2"
  "$ROOT_DIR/graph_bench" --impl="$impl" --graph="$GRAPH_FILE" --source=0 --repeat="$repeat"
}

collect_runtime_row() {
  local impl="$1"
  local output visited total_ms avg
  output="$(run_graph_bench "$impl" "$RUNTIME_REPEAT")"
  visited="$(echo "$output" | awk -F= '/^visited=/{print $2; exit}')"
  total_ms="$(echo "$output" | awk -F= '/^time_ms=/{print $2; exit}')"
  avg="$(avg_ms "$total_ms" "$RUNTIME_REPEAT")"

  printf 'runtime,bfs_only,%s,%s,%s,,%s,%s,,,,,,,\n' \
    "$impl" "$N" "$RUNTIME_REPEAT" "$visited" "$avg"
}

collect_cachegrind_row() {
  local scope="$1"
  local impl="$2"
  local d1_conf="$3"
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
    "$ROOT_DIR/graph_bench" --impl="$impl" --graph="$GRAPH_FILE" --source=0 --repeat="$CG_REPEAT" \
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
  d1_per_run="$(awk -v t="$d1_total" -v r="$CG_REPEAT" 'BEGIN { printf "%.2f", t / r }')"
  lld_per_run="$(awk -v t="$lld_total" -v r="$CG_REPEAT" 'BEGIN { printf "%.2f", t / r }')"

  local visited total_ms avg
  visited="$(awk -F= '/^visited=/{print $2; exit}' "$run_log")"
  total_ms="$(awk -F= '/^time_ms=/{print $2; exit}' "$run_log")"
  avg="$(avg_ms "$total_ms" "$CG_REPEAT")"

  printf 'cachegrind,%s,%s,%s,%s,"%s",%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$scope" "$impl" "$N" "$CG_REPEAT" "$cache_cfg" "$visited" "$avg" \
    "$d1_total" "$d1_per_run" "$lld_total" "$lld_per_run" \
    "$d1_rd" "$d1_wr" "$lld_rd" "$lld_wr"
}

echo "Building benchmark..."
make -C "$ROOT_DIR" clean >/dev/null
make -C "$ROOT_DIR" >/dev/null

echo "Generating star graph (n=$N)..."
python3 "$ROOT_DIR/scripts/gen_graph.py" --kind star --n "$N" --out "$GRAPH_FILE"

echo "Collecting metrics..."
{
  echo "measurement,scope,impl,n,repeat,cache_config,visited,time_ms_avg,d1_misses_total,d1_misses_per_run,lld_misses_total,lld_misses_per_run,d1_rd_misses_total,d1_wr_misses_total,lld_rd_misses_total,lld_wr_misses_total"

  collect_runtime_row "pointer"
  collect_runtime_row "csr"

  collect_cachegrind_row "baseline" "pointer" "32768,8,64"
  collect_cachegrind_row "baseline" "csr" "32768,8,64"

  collect_cachegrind_row "cache_size" "pointer" "16384,8,64"
  collect_cachegrind_row "cache_size" "csr" "16384,8,64"
  collect_cachegrind_row "cache_size" "pointer" "32768,8,64"
  collect_cachegrind_row "cache_size" "csr" "32768,8,64"
  collect_cachegrind_row "cache_size" "pointer" "65536,8,64"
  collect_cachegrind_row "cache_size" "csr" "65536,8,64"

  collect_cachegrind_row "associativity" "pointer" "32768,1,64"
  collect_cachegrind_row "associativity" "csr" "32768,1,64"
  collect_cachegrind_row "associativity" "pointer" "32768,2,64"
  collect_cachegrind_row "associativity" "csr" "32768,2,64"
  collect_cachegrind_row "associativity" "pointer" "32768,4,64"
  collect_cachegrind_row "associativity" "csr" "32768,4,64"
  collect_cachegrind_row "associativity" "pointer" "32768,8,64"
  collect_cachegrind_row "associativity" "csr" "32768,8,64"

  collect_cachegrind_row "line_size" "pointer" "32768,8,32"
  collect_cachegrind_row "line_size" "csr" "32768,8,32"
  collect_cachegrind_row "line_size" "pointer" "32768,8,64"
  collect_cachegrind_row "line_size" "csr" "32768,8,64"
  collect_cachegrind_row "line_size" "pointer" "32768,8,128"
  collect_cachegrind_row "line_size" "csr" "32768,8,128"
} > "$OUT_CSV"

echo "Wrote metrics: $OUT_CSV"