#!/bin/sh
# Builds filedirs for the host Linux platform with Free Pascal 3.2.2.
set -e
cd "$(dirname "$0")"
mkdir -p build
fpc -O2 -Xs -XX -CX -FUbuild -FE. filedirs.pas
