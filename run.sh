#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${WORK:-$ROOT/work}
OUT=$ROOT/results/$(date +%Y%m%d-%H%M%S)
PLOT=1
QUICK=""
TOOLS=""
OBJECTIVES=gmm,ba,hand,lstm
TIMEOUT=180

usage() {
  cat <<EOF
Usage: $0 [options]

  --quick              run the smallest test of each objective
  --tools LIST         ADBench tools, comma separated
                       (default: every tool the setup supports)
  --objectives LIST    objectives (default: $OBJECTIVES)
  --timeout SECONDS    timeout per test (default: $TIMEOUT)
  --no-plot            do not draw the graphs
  --out DIR            results directory (default: results/<date>)

EnzymeCIR and EnzymeLLVM are built from the environment:
  CIR_RA="hand"        objectives EnzymeCIR differentiates with runtimeActivity
                       (default: hand, whose reverse derivative needs it)
  CIR_INLINE=1         EnzymeCIR inlines callees first
  CIR_OPT_CACHES=1     EnzymeCIR uses optimizeCaches
  CIR_EMIT_OPT=-O2     optimization level ClangIR is emitted at
  LLVM_RA="..."        objectives EnzymeLLVM differentiates with runtime activity
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --quick) QUICK=--quick; shift ;;
    --tools) TOOLS=$2; shift 2 ;;
    --objectives) OBJECTIVES=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --no-plot) PLOT=0; shift ;;
    --out) OUT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ ! -f "$WORK/env.sh" ]; then
  echo "$WORK/env.sh not found: run ./setup.sh first" >&2
  exit 1
fi
source "$WORK/env.sh"
export LLVM_PREFIX ENZYMEMLIR_OPT ENZYME_PLUGIN ADBENCH EIGEN_INCLUDE
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
status=0

echo "==> building EnzymeCIR and EnzymeLLVM"
env | grep -E "^(CIR_|LLVM_RA)" >"$OUT/config.txt" || true
"$ROOT/adbench/build_enzyme.sh" | tee "$OUT/build.log"

if [ -z "$TOOLS" ]; then
  TOOLS=Manual,ManualEigen,ManualEigenVector,Finite,FiniteEigen,Tapenade,EnzymeCIR,EnzymeLLVM
  [ -n "$PYTHON" ] && TOOLS=$TOOLS,PyTorch,Autograd
fi
python=${PYTHON:-python3}
rm -rf "$ADBENCH/tmp"
echo "==> $TOOLS on $OBJECTIVES"
(cd "$ADBENCH" && ADBENCH_PYTHON=$python "$python" ADBench/run_bench.py $QUICK \
  --tools "$TOOLS" --objectives "$OBJECTIVES" --timeout "$TIMEOUT") 2>&1 |
  tee "$OUT/adbench.log" || status=1
grep -qE "^[0-9]+ runs, 0 wrong or failed" "$OUT/adbench.log" || status=1
cp -r "$ADBENCH/tmp/Release" "$OUT/adbench"

if [ $PLOT -eq 1 ] && [ -n "$PYTHON" ]; then
  echo "==> graphs"
  (cd "$ADBENCH" && "$PYTHON" ADBench/plot_graphs.py --save --plotly) >"$OUT/plot.log" 2>&1 || status=1
  [ -d "$ADBENCH/tmp/graphs" ] && cp -r "$ADBENCH/tmp/graphs" "$OUT/graphs"
fi

echo "==> results in $OUT"
exit $status
