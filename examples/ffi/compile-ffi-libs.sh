#!/bin/sh

DIR="$( cd "$( dirname "$0" )" && pwd )"

clang++ $DIR/simple.cpp -o $DIR/simple.module -fPIC -shared \
  -Wl,-U,roc_alloc -Wl,-U,_roc_alloc \
  -Wl,-U,roc_dealloc -Wl,-U,_roc_dealloc
