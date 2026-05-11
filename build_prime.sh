#!/bin/bash
set -euo pipefail

KERNEL_DIR=$(pwd)
DEVICE="$1"

# --- Toolchain setup ---
if [ -z "${KERNEL_LLVM_BIN:-}" ] || [ ! -x "$KERNEL_LLVM_BIN" ]; then
    echo "Error: Neutron Clang toolchain not found. Exiting."
    exit 1
fi

export PATH="$(dirname "$KERNEL_LLVM_BIN"):$PATH"
export LD=ld.lld

# --- Platform setup ---
export PROJECT_NAME="${DEVICE}"
export PLATFORM_VERSION="${PLATFORM_VERSION:-11}"

# --- Build variables ---
export ARCH=arm64
mkdir -p out

# Safer flags for Neutron Clang
export KBUILD_CFLAGS="-O2 -Wno-default-const-init-var-unsafe"

BUILD_VAR="-j$(nproc) -C $KERNEL_DIR O=$KERNEL_DIR/out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1"

# --- Functions ---
build_kernel() {
    echo ">>> Building kernel for $DEVICE"

    cat arch/arm64/configs/vendor/kona-sec-perf_defconfig \
        arch/arm64/configs/vendor/samsung/${DEVICE}.config \
        arch/arm64/configs/vendor/not/no_werror.config \
        arch/arm64/configs/vendor/debugfs.config > arch/arm64/configs/temp_defconfig

    cat >> arch/arm64/configs/temp_defconfig <<EOF
# Disable LTO for stability
CONFIG_LTO_NONE=y
# CONFIG_THINLTO is not set
# CONFIG_LTO_CLANG is not set

CONFIG_LOCALVERSION="-PrimeKernel"
EOF

    make $BUILD_VAR temp_defconfig
    rm arch/arm64/configs/temp_defconfig
}

build_dtb() {
    echo ">>> Building dtb"
    make $BUILD_VAR
    make $BUILD_VAR dtbs

    cat out/arch/arm64/boot/dts/vendor/qcom/kona*.dtb > out/arch/arm64/boot/dts/dtb
}

build_dtbo() {
    echo ">>> Building dtbo.img"
    DTBO_FILES=$(find out/arch/arm64/boot/dts/samsung/$DEVICE -name "kona-sec-$DEVICE-*.dtbo")
    tools/mkdtimg create out/dtbo.img --page_size=4096 ${DTBO_FILES}
}

prepare_ak3() {
    echo ">>> Packaging AnyKernel3"
    cd AnyKernel3/

    cp "$KERNEL_DIR/out/dtbo.img" dtbo.img
    cp "$KERNEL_DIR/out/arch/arm64/boot/Image" Image
    cp "$KERNEL_DIR/out/arch/arm64/boot/dts/dtb" dtb

    sed -i "s/^device\.name1=.*/device.name1=${DEVICE}/" anykernel.sh

    ZIP_NAME="Astro-Kernel-${DEVICE}.zip"
    zip -r "../${ZIP_NAME}" *
    cd "$KERNEL_DIR"
}

# --- Execution ---
build_kernel
build_dtb
build_dtbo
prepare_ak3

echo ">>> Build complete: Astro-Kernel-${DEVICE}.zip"
