#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
source $SCRIPT_DIR/scripts/common.sh

function run() {
  prepare
  build
}

run "$@"
