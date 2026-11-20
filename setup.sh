#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${WORK:-$ROOT/work}

LLVM_URL=${LLVM_URL:-https://github.com/Ringo-Leo/llvm-project.git}
LLVM_BRANCH=${LLVM_BRANCH:-cir}
LLVM_REF=${LLVM_REF-f6fcdedcbf20eed4891ec4bd1709f5012cb7fae6}
ENZYME_URL=${ENZYME_URL:-https://github.com/Ringo-Leo/Enzyme-CIR.git}
ENZYME_BRANCH=${ENZYME_BRANCH:-users/aokblast/cir/finalize_pipeline}
ENZYME_REF=${ENZYME_REF-0569045cf31f2073e4e2183883db79e86af95514}
ADBENCH_URL=${ADBENCH_URL:-https://github.com/microsoft/ADBench.git}
ADBENCH_BRANCH=${ADBENCH_BRANCH:-master}
ADBENCH_REF=${ADBENCH_REF-38cb7931303a830c3700ca36ba9520868327ac87}
EIGEN_INCLUDE=${EIGEN_INCLUDE:-/usr/include/eigen3}
JOBS=${JOBS:-$(nproc)}
LLVM_PREFIX=""
WITH_PYTHON=1

usage() {
  cat <<EOF
Usage: $0 [--llvm-prebuilt DIR] [--jobs N] [--no-python]

  --llvm-prebuilt DIR  use an installed LLVM (clang, mlir, ClangIR) at DIR
                       instead of cloning and building $LLVM_URL
  --jobs N             parallel build jobs (default: $JOBS)
  --no-python          do not set up the Python tools (PyTorch, Autograd, plots)

Environment overrides:
  WORK                                    work directory (default: $ROOT/work)
  LLVM_URL LLVM_BRANCH LLVM_REF
  ENZYME_URL ENZYME_BRANCH ENZYME_REF
  ADBENCH_URL ADBENCH_BRANCH ADBENCH_REF  an empty *_REF uses the branch tip
  EIGEN_INCLUDE                           Eigen headers (default: $EIGEN_INCLUDE)
  CC CXX                                  host compiler for LLVM and Enzyme
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --llvm-prebuilt) LLVM_PREFIX=$(cd "$2" && pwd); shift 2 ;;
    --jobs) JOBS=$2; shift 2 ;;
    --no-python) WITH_PYTHON=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

log() { printf '\n==> %s\n' "$*"; }

clone() {
  local url=$1 branch=$2 ref=$3 dir=$4
  if [ ! -d "$dir/.git" ]; then
    git clone --depth 1 --single-branch --branch "$branch" "$url" "$dir"
  fi
  if [ -n "$ref" ] && [ "$(git -C "$dir" rev-parse HEAD)" != "$ref" ]; then
    git -C "$dir" fetch --depth 1 origin "$ref"
    git -C "$dir" checkout -q --detach FETCH_HEAD
  fi
  echo "$dir at $(git -C "$dir" rev-parse --short HEAD)"
}

check_llvm() {
  local missing=0
  for f in bin/clang bin/clang++ bin/cir-translate bin/opt bin/llvm-config \
           lib/cmake/llvm lib/cmake/mlir lib/cmake/clang; do
    if [ ! -e "$LLVM_PREFIX/$f" ]; then
      echo "missing $LLVM_PREFIX/$f" >&2
      missing=1
    fi
  done
  [ $missing -eq 0 ] || { echo "$LLVM_PREFIX is not an LLVM install with clang, mlir and ClangIR" >&2; exit 1; }
}

build_llvm() {
  log "LLVM"
  clone "$LLVM_URL" "$LLVM_BRANCH" "$LLVM_REF" "$WORK/src/llvm-project"
  cmake -G Ninja -S "$WORK/src/llvm-project/llvm" -B "$WORK/build/llvm" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$WORK/install/llvm" \
    -DLLVM_ENABLE_PROJECTS="clang;mlir" \
    -DCLANG_ENABLE_CIR=ON \
    -DLLVM_TARGETS_TO_BUILD=host \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_PARALLEL_LINK_JOBS=2 \
    -DMLIR_ENABLE_BINDINGS_PYTHON=OFF
  ninja -C "$WORK/build/llvm" -j "$JOBS" install
  LLVM_PREFIX=$WORK/install/llvm
}

llvm_uses_libcxx() {
  local lib
  for lib in "$LLVM_PREFIX"/lib/libLLVMSupport.a "$LLVM_PREFIX"/lib/libLLVM.so "$LLVM_PREFIX"/lib/libLLVM-*.so; do
    if [ -e "$lib" ]; then
      [ "$(nm -C "$lib" 2>/dev/null | grep -c 'std::__1::' || true)" -gt 0 ]
      return
    fi
  done
  return 1
}

build_enzyme() {
  log "Enzyme"
  clone "$ENZYME_URL" "$ENZYME_BRANCH" "$ENZYME_REF" "$WORK/src/Enzyme"
  LLVM_MAJOR=$("$LLVM_PREFIX/bin/llvm-config" --version | cut -d. -f1)
  local compiler=() stdlib=()
  if llvm_uses_libcxx; then
    echo "LLVM at $LLVM_PREFIX uses libc++: building Enzyme with clang and -stdlib=libc++"
    compiler=(-DCMAKE_C_COMPILER="${CC:-$LLVM_PREFIX/bin/clang}"
              -DCMAKE_CXX_COMPILER="${CXX:-$LLVM_PREFIX/bin/clang++}")
    stdlib=(-DCMAKE_CXX_FLAGS=-stdlib=libc++
            -DCMAKE_EXE_LINKER_FLAGS=-stdlib=libc++
            -DCMAKE_SHARED_LINKER_FLAGS=-stdlib=libc++
            -DCMAKE_MODULE_LINKER_FLAGS=-stdlib=libc++)
  fi
  cmake --fresh -G Ninja -S "$WORK/src/Enzyme/enzyme" -B "$WORK/build/enzyme" \
    "${compiler[@]}" "${stdlib[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_DIR="$LLVM_PREFIX/lib/cmake/llvm" \
    -DMLIR_DIR="$LLVM_PREFIX/lib/cmake/mlir" \
    -DClang_DIR="$LLVM_PREFIX/lib/cmake/clang" \
    -DENZYME_MLIR=ON \
    -DENZYME_CLANG=OFF
  ninja -C "$WORK/build/enzyme" -j "$JOBS" enzymemlir-opt "LLVMEnzyme-$LLVM_MAJOR"
  ENZYMEMLIR_OPT=$WORK/build/enzyme/Enzyme/MLIR/enzymemlir-opt
  ENZYME_PLUGIN=$WORK/build/enzyme/Enzyme/LLVMEnzyme-$LLVM_MAJOR.so
  [ -x "$ENZYMEMLIR_OPT" ] && [ -f "$ENZYME_PLUGIN" ] || { echo "Enzyme build did not produce enzymemlir-opt and the plugin" >&2; exit 1; }
}

setup_adbench() {
  log "ADBench"
  ADBENCH=$WORK/src/ADBench
  clone "$ADBENCH_URL" "$ADBENCH_BRANCH" "$ADBENCH_REF" "$ADBENCH"
  git -C "$ADBENCH" checkout -q -- .
  git -C "$ADBENCH" apply "$ROOT/adbench/adbench.patch"
  rm -rf "$ADBENCH/src/cpp/modules/enzyme"
  cp -r "$ROOT/adbench/modules/enzyme" "$ADBENCH/src/cpp/modules/enzyme"
  cp "$ROOT/adbench/run_bench.py" "$ADBENCH/ADBench/run_bench.py"
  [ -d "$EIGEN_INCLUDE" ] || { echo "Eigen headers not found at $EIGEN_INCLUDE; set EIGEN_INCLUDE" >&2; exit 1; }
  ADBENCH=$ADBENCH LLVM_PREFIX=$LLVM_PREFIX EIGEN_INCLUDE=$EIGEN_INCLUDE \
    "$ROOT/adbench/build_tools.sh"
}

setup_python() {
  PYTHON=""
  [ $WITH_PYTHON -eq 1 ] || return 0
  log "Python"
  python3 -m venv --system-site-packages "$WORK/venv"
  "$WORK/venv/bin/python" -m pip install -q --upgrade pip
  "$WORK/venv/bin/python" -m pip install -q numpy scipy matplotlib plotly autograd
  "$WORK/venv/bin/python" -c "import torch" 2>/dev/null ||
    "$WORK/venv/bin/python" -m pip install -q torch --index-url https://download.pytorch.org/whl/cpu
  PYTHON=$WORK/venv/bin/python
}

mkdir -p "$WORK/src" "$WORK/build"
if [ -n "$LLVM_PREFIX" ]; then
  log "LLVM: using $LLVM_PREFIX"
else
  build_llvm
fi
check_llvm
build_enzyme
setup_adbench
setup_python

cat > "$WORK/env.sh" <<EOF
LLVM_PREFIX=$LLVM_PREFIX
ENZYMEMLIR_OPT=$ENZYMEMLIR_OPT
ENZYME_PLUGIN=$ENZYME_PLUGIN
ADBENCH=$ADBENCH
EIGEN_INCLUDE=$EIGEN_INCLUDE
PYTHON=$PYTHON
EOF
log "done: $WORK/env.sh"
cat "$WORK/env.sh"
