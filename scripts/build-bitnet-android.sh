#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
BITNET_DIR="${BITNET_DIR:-$WORK_DIR/BitNet}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist/bitnet-android-arm64}"

BITNET_REPO="${BITNET_REPO:-https://github.com/microsoft/BitNet.git}"
BITNET_REF="${BITNET_REF:-main}"
NDK_DIR="${ANDROID_NDK:-${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}}"

ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-28}"
BUILD_DIR="${BUILD_DIR:-build-android}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
MODEL_PROFILE="${MODEL_PROFILE:-BitNet-b1.58-2B-4T}"
QUANT_TYPE="${QUANT_TYPE:-i2_s}"
TARGETS="${TARGETS:-llama-cli llama-quantize}"

if [[ -z "$NDK_DIR" ]]; then
  echo "error: ANDROID_NDK, ANDROID_NDK_HOME, or ANDROID_NDK_ROOT must point to Android NDK" >&2
  exit 1
fi

TOOLCHAIN_FILE="$NDK_DIR/build/cmake/android.toolchain.cmake"
if [[ ! -f "$TOOLCHAIN_FILE" ]]; then
  echo "error: Android NDK toolchain file not found: $TOOLCHAIN_FILE" >&2
  exit 1
fi

case "$QUANT_TYPE" in
  i2_s)
    BITNET_ARM_TL1=OFF
    ;;
  tl1)
    BITNET_ARM_TL1=ON
    ;;
  *)
    echo "error: unsupported QUANT_TYPE=$QUANT_TYPE; use i2_s or tl1" >&2
    exit 1
    ;;
esac

jobs() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
  else
    echo 2
  fi
}
JOBS="${JOBS:-$(jobs)}"

clone_bitnet() {
  rm -rf "$BITNET_DIR"
  mkdir -p "$WORK_DIR"
  git clone --recursive "$BITNET_REPO" "$BITNET_DIR"
  git -C "$BITNET_DIR" checkout "$BITNET_REF"
  git -C "$BITNET_DIR" submodule update --init --recursive
}

prepare_arm_kernels() {
  cd "$BITNET_DIR"
  case "$MODEL_PROFILE" in
    bitnet_b1_58-large)
      python utils/codegen_tl1.py --model bitnet_b1_58-large --BM 256,128,256 --BK 128,64,128 --bm 32,64,32
      ;;
    bitnet_b1_58-3B|BitNet-b1.58-2B-4T)
      python utils/codegen_tl1.py --model bitnet_b1_58-3B --BM 160,320,320 --BK 64,128,64 --bm 32,64,32
      ;;
    Llama3-8B-1.58-100B-tokens|Falcon*)
      python utils/codegen_tl1.py --model Llama3-8B-1.58-100B-tokens --BM 256,128,256,128 --BK 128,64,128,64 --bm 32,64,32,64
      ;;
    *)
      echo "error: unsupported MODEL_PROFILE=$MODEL_PROFILE" >&2
      echo "supported: BitNet-b1.58-2B-4T, bitnet_b1_58-3B, bitnet_b1_58-large, Llama3-8B-1.58-100B-tokens, Falcon*" >&2
      exit 1
      ;;
  esac
}

build_bitnet() {
  cd "$BITNET_DIR"
  read -r -a TARGET_ARRAY <<< "$TARGETS"

  cmake -S . -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
    -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DBITNET_ARM_TL1="$BITNET_ARM_TL1" \
    -DBITNET_X86_TL2=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF \
    -DGGML_LLAMAFILE=OFF \
    -DLLAMA_CURL=OFF \
    -DBUILD_SHARED_LIBS=OFF

  cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" --target "${TARGET_ARRAY[@]}" -j "$JOBS"
}

package_artifact() {
  rm -rf "$OUT_DIR"
  mkdir -p "$OUT_DIR/bin"

  for target in $TARGETS; do
    if [[ -f "$BITNET_DIR/$BUILD_DIR/bin/$target" ]]; then
      cp "$BITNET_DIR/$BUILD_DIR/bin/$target" "$OUT_DIR/bin/"
    fi
  done

  cat > "$OUT_DIR/build-info.txt" <<EOF
BitNet repo: $BITNET_REPO
BitNet ref: $BITNET_REF
BitNet commit: $(git -C "$BITNET_DIR" rev-parse HEAD)
Android ABI: $ANDROID_ABI
Android platform: $ANDROID_PLATFORM
NDK: $NDK_DIR
Model profile: $MODEL_PROFILE
Quant type: $QUANT_TYPE
BITNET_ARM_TL1: $BITNET_ARM_TL1
Targets: $TARGETS
EOF
}

clone_bitnet
prepare_arm_kernels
build_bitnet
package_artifact

echo "Packaged artifact at: $OUT_DIR"
