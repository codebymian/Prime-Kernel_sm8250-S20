#!/bin/sh

KERNEL_DIR=$(pwd)
DEVICE="$1"

# --- Platform setup ---
export PROJECT_NAME="${DEVICE}"
[ -z "${PLATFORM_VERSION}" ] && export PLATFORM_VERSION=11

# --- Build variables ---
export ARCH=arm64
export PATH="$KERNEL_DIR/llvm-21/bin:$PATH"
BUILD_VAR="-j$(nproc) -C $KERNEL_DIR O=$KERNEL_DIR/out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1"

build_kernel() {
    echo "-----------------------------------------------"
    echo "Beginning kernel compilation for $DEVICE..."
    echo "-----------------------------------------------"

    rm -rf out
    mkdir out

    # Merge configs safely
    scripts/kconfig/merge_config.sh \
        arch/arm64/configs/vendor/kona-sec-perf_defconfig \
        arch/arm64/configs/vendor/samsung/${DEVICE}.config \
        arch/arm64/configs/ksu.config \
        arch/arm64/configs/vendor/not/no_werror.config \
        arch/arm64/configs/vendor/debugfs.config

    # Extra overrides
    cat >> .config <<EOF
CONFIG_THINLTO=y
# CONFIG_LTO_NONE is not set
CONFIG_LTO_CLANG=y
CONFIG_LOCALVERSION="-PrimeKernel"
EOF

    make $BUILD_VAR olddefconfig || exit 1
}

build_dtb() {
    echo "-----------------------------------------------"
    echo "Building dtb..."
    echo "-----------------------------------------------"

    make $BUILD_VAR Image dtbs

    cat out/arch/arm64/boot/dts/vendor/qcom/kona.dtb \
        out/arch/arm64/boot/dts/vendor/qcom/kona-v2.dtb \
        out/arch/arm64/boot/dts/vendor/qcom/kona-v2.1.dtb \
        > out/arch/arm64/boot/dts/dtb
}

build_dtbo() {
    echo "-----------------------------------------------"
    echo "Building dtbo.img..."
    echo "-----------------------------------------------"

    chmod +x tools/mkdtimg
    DTBO_FILES=$(find out/arch/arm64/boot/dts/samsung/$DEVICE -name "kona-sec-$DEVICE-*.dtbo")
    tools/mkdtimg create out/dtbo.img --page_size=4096 ${DTBO_FILES}
}

prepare_ak3() {
    cd AnyKernel3/

    # Safety checks
    [ -f "$KERNEL_DIR/out/dtbo.img" ] || { echo "dtbo.img missing"; exit 1; }
    [ -f "$KERNEL_DIR/out/arch/arm64/boot/Image" ] || { echo "Image missing"; exit 1; }
    [ -f "$KERNEL_DIR/out/arch/arm64/boot/dts/dtb" ] || { echo "dtb missing"; exit 1; }

    mv "$KERNEL_DIR/out/dtbo.img" dtbo.img
    mv "$KERNEL_DIR/out/arch/arm64/boot/Image" Image
    mv "$KERNEL_DIR/out/arch/arm64/boot/dts/dtb" dtb

    sed -i "s/^device\.name1=.*/device.name1=${DEVICE}/" anykernel.sh

    ZIP_NAME="Astro-Kernel-${DEVICE}.zip"
    zip -r "../${ZIP_NAME}" *

    cd "$KERNEL_DIR"
}

build_kernel
build_dtb
build_dtbo
prepare_ak3
