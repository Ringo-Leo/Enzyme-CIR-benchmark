#!/usr/bin/env bash
set -euo pipefail

: "${ADBENCH:?}" "${LLVM_PREFIX:?}" "${ENZYMEMLIR_OPT:?}" "${ENZYME_PLUGIN:?}" "${EIGEN_INCLUDE:?}"
B=$LLVM_PREFIX/bin
S=$ADBENCH/src/cpp/shared
E=$ADBENCH/src/cpp/modules/enzyme
INC="-std=c++17 -I$S -I$E -I$EIGEN_INCLUDE"
has() { [[ " $1 " == *" $2 "* ]]; }
CIR_RA=${CIR_RA-hand}

build_tool() {
  local tool=$1
  local out=$ADBENCH/build/src/cpp/modules/${tool,}
  local work=$out/obj
  mkdir -p "$work"
  "$B/clang++" $INC -O2 -fPIC -w -c "$E/EnzymeModule.cpp" -o "$work/EnzymeModule.o"
  local objs=("$work/EnzymeModule.o")
  for obj in gmm ba hand lstm; do
    local src=$E/grads_$obj.cpp
    if [ "$tool" = EnzymeCIR ]; then
      local opts=""
      has "${CIR_RA:-}" $obj && opts="runtimeActivity=true"
      [ -n "${CIR_INLINE:-}" ] && opts="$opts inline=true"
      [ -n "${CIR_OPT_CACHES:-}" ] && opts="$opts optimizeCaches=true"
      opts=${opts# }
      local pipe="--cir-autodiff-pipeline${opts:+=$opts}"
      "$B/clang++" $INC -fclangir -emit-cir ${CIR_EMIT_OPT:--O0} -fno-exceptions \
        -fno-math-errno -w "$src" -o "$work/$obj.cir"
      "$ENZYMEMLIR_OPT" "$pipe" "$work/$obj.cir" -o "$work/$obj.2.cir" 2>"$work/$obj.enzyme.log"
      "$B/cir-translate" --cir-to-llvmir "$work/$obj.2.cir" -o "$work/$obj.ll"
      sed -i '/^target datalayout/d' "$work/$obj.ll"
    else
      local ra=""
      has "${LLVM_RA:-}" $obj && ra=-enzyme-runtime-activity
      "$B/clang++" $INC -O2 -fno-vectorize -fno-slp-vectorize -fno-unroll-loops \
        -fno-exceptions -fno-math-errno -fPIC -w -S -emit-llvm "$src" -o "$work/$obj.pre.ll"
      "$B/opt" -load-pass-plugin="$ENZYME_PLUGIN" -passes=enzyme $ra "$work/$obj.pre.ll" \
        -S -o "$work/$obj.ll" 2>"$work/$obj.enzyme.log"
    fi
    "$B/clang++" -O2 -fPIC -w -c "$work/$obj.ll" -o "$work/$obj.o"
    objs+=("$work/$obj.o")
  done
  "$B/clang++" $INC -O2 -fPIC -shared -w "${objs[@]}" "$S/utils.cpp" -o "$out/$tool.dll"
  echo "built $out/$tool.dll"
}

for tool in ${TOOLS:-EnzymeCIR EnzymeLLVM}; do
  build_tool "$tool"
done
