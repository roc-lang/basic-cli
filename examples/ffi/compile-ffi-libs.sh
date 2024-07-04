#!/bin/sh

DIR="$( cd "$( dirname "$0" )" && pwd )"

clang++ $DIR/simple.cpp -o $DIR/simple.module -fPIC -shared \
  -Wl,-U,roc_alloc -Wl,-U,_roc_alloc \
  -Wl,-U,roc_dealloc -Wl,-U,_roc_dealloc

clang $DIR/vendor/sqlite3.c -o $DIR/vendor/sqlite3.o -fPIC -c
clang++ $DIR/sqlite-shim.cpp $DIR/vendor/sqlite3.o -o $DIR/sqlite.module -fPIC -shared \
  -Wl,-U,roc_alloc -Wl,-U,_roc_alloc \
  -Wl,-U,roc_dealloc -Wl,-U,_roc_dealloc
