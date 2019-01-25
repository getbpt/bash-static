#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
source $SCRIPT_DIR/common.sh

function run() {
  if [[ "$TRAVIS_BRANCH" != "master" ]]; then
    git config --local user.name "$USERNAME" || fatal "failed to configure username"
    git config --local user.email "$EMAIL" || fatal "failed to configure email"
    export TRAVIS_TAG=$TRAVIS_BRANCH
    git tag $TRAVIS_TAG || fatal "failed to tag"
  fi
  exit 0
}

run "$@"
