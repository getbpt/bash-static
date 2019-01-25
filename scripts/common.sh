#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/build"
BUILD_BASH_DIR="$BUILD_DIR/bash"
DOWNLOAD_DIR="$ROOT_DIR/download"

function verbose() { echo -e "$*"; }
function error() { echo -e "ERROR: $*" 1>&2; }
function fatal() { echo -e "ERROR: $*" 1>&2; exit 1; }
function pushd () { command pushd "$@" > /dev/null; }
function popd () { command popd > /dev/null; }

eval "$(cat "$ROOT_DIR/versions.txt")"
if [[ -z "$BASH_BUILD_VERSION" ]]; then
  if [[ "$TRAVIS_BRANCH" != "master" ]]; then
    verbose "building happens in branches.  exiting..."
    exit 0
  else
    fatal "versions.txt does not specify a bash version"
  fi
fi

function get_platform() {
  local unameOut
  unameOut="$(uname -s)" || fatal "unable to get platform type: $?"
  case "${unameOut}" in
    Linux*)
      echo "linux"
    ;;
    Darwin*)
      echo "darwin"
    ;;
    *)
      fatal "Unsupported machine type :${unameOut}"
    ;;
  esac
}

function prepare() {
  if [[ -d $DIST_DIR ]]; then
    verbose "--> Cleaning up dist directory..."
    rm -rf $DIST_DIR || fatal "failed to cleanup dist directory: $?"
  fi
  mkdir $DIST_DIR || fatal "failed to create dist directory: $?"
  if [[ -d $BUILD_DIR ]]; then
    verbose "    --> Cleaning up build directory..."
    rm -rf $BUILD_DIR || fatal "failed to cleanup build directory: $?"
  fi
  mkdir -p $BUILD_BASH_DIR || fatal "failed to create build directory: $?"
  if [[ -d $DOWNLOAD_DIR ]]; then
    verbose "    --> Cleaning up download directory..."
    rm -rf $DOWNLOAD_DIR || fatal "failed to cleanup download directory: $?"
  fi
  mkdir $DOWNLOAD_DIR || fatal "failed to create download directory: $?"
  download_upx
  download_musl
  download_bash
}

function download_upx() {
  verbose "    --> Downloading upx..."
  local platform
  platform="$(get_platform)" || fatal "failed to get platform: $?"
  local upx_url="https://github.com/kadaan/upx/releases/download/20181231/upx_$platform"
  verbose "            --> Downloading $upx_url..."
  curl -o "$BUILD_DIR/upx" -sLO ${upx_url} || fatal "failed to download upx: $?"
  chmod +x "$BUILD_DIR/upx"
}

function download_musl() {
  local platform
  platform="$(get_platform)" || fatal "failed to get platform: $?"
  if [ "$platform" = "linux" ]; then
    local musl_version="1.1.21"
    verbose "        --> Downloading musl ${musl_version:?} archive..."
    local musl_url="http://www.musl-libc.org/releases/musl-${musl_version}.tar.gz"
    verbose "            --> Downloading $musl_url..."
    curl -o "$DOWNLOAD_DIR/musl.tar.gz" -sLO "$musl_url"  || fatal "failed to download musl archive: $?"
    verbose "        --> Extracing musl archive..."
    mkdir $BUILD_DIR/musl || fatal "failed to create musl build directory: $?"
    tar --strip-components 1 -xf "$DOWNLOAD_DIR/musl.tar.gz" -C "$BUILD_DIR/musl" || fatal "failed to extract musl archive: $?"]
    cd $BUILD_DIR/musl || fatal "failed to change to musl build directory: $?"
    verbose "        --> Configuring musl..."
    mkdir $BUILD_DIR/stdlib || fatal "failed to change to stdlib build directory: $?"
    ./configure --prefix=$BUILD_DIR/stdlib || fatal "failed to configure musl: $?"
    make install || fatal "failed to build musl: $?"
  fi
}

function download_bash() {
  verbose "    --> Downloading bash ${BASH_BUILD_VERSION:?} archive..."
  local bash_url="http://ftp.gnu.org/gnu/bash/bash-${BASH_BUILD_VERSION}.tar.gz"
  verbose "        --> Downloading $bash_url..."
  curl -o "$DOWNLOAD_DIR/bash.tar.gz" -sLO "$bash_url"  || fatal "failed to download bash archive: $?"
  verbose "    --> Extracing bash archive..."
  tar --strip-components 1 -xf "$DOWNLOAD_DIR/bash.tar.gz" -C "$BUILD_BASH_DIR" || fatal "failed to extract bash archive: $?"]
  if [[ "$BASH_BUILD_PATCH_LEVEL" != "" ]]; then
    verbose "    --> Patching bash..."
    local bash_patch_prefix
    bash_patch_prefix=$(echo "bash${BASH_BUILD_VERSION}" | sed -e 's/\.//g') || fatal "failed to determine bash prefix: $?"
    for lvl in $(seq ${BASH_BUILD_PATCH_LEVEL:?}); do
      verbose "        --> Applying patch $lvl..."
      local patch_name
      patch_name="${bash_patch_prefix}-$(printf '%03d' $lvl)" || fatal "failed to construct patch name: $?"
      local patch_url="http://ftp.gnu.org/gnu/bash/bash-${BASH_BUILD_VERSION}-patches/${patch_name}"
      verbose "            --> Downloading $patch_url..."
      curl -o "$DOWNLOAD_DIR/$patch_name" -sLO "$patch_url" || fatal "failed to download patch $patch_name: $?"
      verbose "            --> Applying $patch_name..."
      patch -p0 -d $BUILD_BASH_DIR -s <$DOWNLOAD_DIR/$patch_name || fatal "failed to apply patch $lvl: $?"
    done
  fi
}

function build() {
  verbose "--> Building bash ${BASH_BUILD_VERSION}.${BASH_BUILD_PATCH_LEVEL}..."
  local platform
  platform="$(get_platform)" || fatal "failed to get platform: $?"
  cd $BUILD_BASH_DIR || fatal "failed to change to bash build directory: $?"
  verbose "    --> Configuring bash..."
  if [[ -f $BUILD_DIR/stdlib/bin/musl-gcc ]]; then
    CC="$BUILD_DIR/stdlib/bin/musl-gcc" CFLAGS="-static -Os" ./configure --without-bash-malloc || fatal "failed to configure bash: $?"
  else
    CFLAGS="-Os" ./configure --without-bash-malloc || fatal "failed to configure bash: $?"
  fi
  verbose "    --> Building bash..."
  make || fatal "failed to build bash: $?"
  verbose "    --> Testing bash..."
  make tests || fatal "failed to successfully complete bash tests: $?"
  local bash_release_name="bash_${BASH_BUILD_VERSION}"
  if [[ "$BASH_BUILD_PATCH_LEVEL" != "" ]]; then
    bash_release_name="${bash_release_name}.${BASH_BUILD_PATCH_LEVEL}"
  fi
  bash_release_name="${bash_release_name}_${platform}"
  verbose "    --> Compressing bash...$"
  $BUILD_DIR/upx -9 $BUILD_BASH_DIR/bash || fatal "failed to compress bash: $?"
  verbose "    --> Copying bash $bash_release_name to dist..."
  cp $BUILD_BASH_DIR/bash $DIST_DIR/$bash_release_name || fatal "failed to copy $bash_release_name to dist: $?"
  cd $SCRIPT_DIR || fatal "failed to change back to root directory: $?"
}
