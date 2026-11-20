#!/usr/bin/env bash
set -euo pipefail

: "${ADBENCH:?}" "${LLVM_PREFIX:?}" "${EIGEN_INCLUDE:?}"
CXX=$LLVM_PREFIX/bin/clang++
CC=$LLVM_PREFIX/bin/clang
BIN=$ADBENCH/build
M=$ADBENCH/src/cpp/modules
S=$ADBENCH/src/cpp/shared
FLAGS="-O2 -w -std=c++17 -I$EIGEN_INCLUDE -I$S"

mkdir -p "$BIN/src/cpp/runner"
(cd "$ADBENCH/src/cpp/runner" && $CXX $FLAGS -o "$BIN/src/cpp/runner/CppRunner.exe" \
  GMMBenchmark.cpp BABenchmark.cpp HandBenchmark.cpp LSTMBenchmark.cpp Filepaths.cpp \
  ModuleLoader.cpp OutputSave.cpp ../shared/utils.cpp main.cpp -ldl)
echo "built CppRunner.exe"

build_module() {
  local name=$1 dir=$2
  shift 2
  local out=$BIN/src/cpp/modules/$dir objs=()
  mkdir -p "$out"
  pushd "$M/$dir" >/dev/null
  for f in "$@"; do
    case $f in
      *.c)
        $CC -O2 -w -fPIC -c "$f" -o "$out/$(basename "$f").o"
        objs+=("$out/$(basename "$f").o") ;;
      *) objs+=("$f") ;;
    esac
  done
  $CXX $FLAGS -fPIC -shared -o "$out/$name.dll" "${objs[@]}" "$S/utils.cpp"
  popd >/dev/null
  echo "built $name.dll"
}

build_module Manual manual gmm_d.cpp ba_d.cpp hand_d.cpp lstm_d.cpp \
  ManualGMM.cpp ManualBA.cpp ManualHand.cpp ManualLSTM.cpp
build_module Finite finite FiniteGMM.cpp FiniteBA.cpp FiniteHand.cpp FiniteLSTM.cpp
build_module ManualEigen manualEigen gmm_d.cpp gmm_scalar_d.cpp ba_d.cpp hand_eigen_d.cpp \
  lstm_eigen_d.cpp ManualEigenGMM.cpp ManualEigenBA.cpp ManualEigenHand.cpp ManualEigenLSTM.cpp
build_module FiniteEigen finiteEigen FiniteEigenHand.cpp
build_module ManualEigenVector manualEigenVector ../manualEigen/gmm_d.cpp gmm_vector_d.cpp \
  memory_size.cpp ManualEigenVectorGMM.cpp
build_module Tapenade tapenade utils/adBuffer.c utils/adStack.c lstm/lstm.c lstm/lstm_b.c \
  TapenadeLSTM.cpp gmm/gmm.c gmm/gmm_b.c TapenadeGMM.cpp ba/ba.c ba/ba_b.c TapenadeBA.cpp \
  hand/hand.c hand/hand_d.c TapenadeHand.cpp
