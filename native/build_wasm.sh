#!/usr/bin/env bash
# Builds server/src/studio/luau.mjs (+ .wasm) with Emscripten (source emsdk_env.sh first).
set -euo pipefail
cd "$(dirname "$0")"
L=third_party/luau
SRC="core/mvm.cpp wasm/bindings.cpp $(ls $L/VM/src/*.cpp $L/Compiler/src/*.cpp $L/Ast/src/*.cpp $L/Bytecode/src/*.cpp $L/Common/src/*.cpp)"
INC="-I$L/VM/include -I$L/VM/src -I$L/Compiler/include -I$L/Ast/include -I$L/Common/include -I$L/Bytecode/include"
mkdir -p ../server/src/studio
em++ -O2 -std=c++17 -fexceptions $INC $SRC -lembind \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sENVIRONMENT=node -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=512MB \
  -sDISABLE_EXCEPTION_CATCHING=0 -sEXPORT_NAME=createLuau \
  -o ../server/src/studio/luau.mjs
ls -la ../server/src/studio/luau.*
