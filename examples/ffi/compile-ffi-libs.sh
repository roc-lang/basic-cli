#!/bin/sh

DIR="$( cd "$( dirname "$0" )" && pwd )"

clang++ $DIR/simple.cpp -o $DIR/simple.module -fPIC -shared
