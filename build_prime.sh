#!/bin/sh

set -e  # Exit immediately on error
set -u  # Treat unset variables as errors

KERNEL_DIR=$(pwd)
IMG_DIR="$KERNEL_DIR/images"
DEVICE="${1:-}"
DEVICE2="${2:-}"
DEVICE3="${3:-}"

mkdir -p "$IMG_DIR"
mkdir -p out

# Ensure temp_defconfig is always cleaned up
trap 'rm -f arch/arm64/configs/temp_defconfig' EXIT

build_kernel() {
    echo "-----------------------------------------------"
    echo "Beginning kernel compilation for $DEVICE..."
    echo "-----------------------------------------------"

    export ARCH=arm64
    export PATH="$KERNEL_DIR/llvm-21/bin:$PATH"

    BUILD_VAR="-j$(nproc) -C $KERNEL_DIR O=$KERNEL_DIR/out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1"

    cat arch/arm64/configs/vendor/kona-sec-perf_defconfig \
        arch/arm64/configs/vendor/samsung/$DEVICE.config \
        arch/arm64/configs/ksu.config > arch/arm64/configs/temp_defconfig

    cat >> arch/arm64/configs/temp_defconfig <<EOF
CONFIG_THINLTO=y
# CONFIG_LTO_NONE is not set
CONFIG_LTO_CLANG=y
CONFIG_LOCALVERSION="-PrimeKernel"
EOF

    make $BUILD_VAR temp_defconfig
}

build_dtb() {
    echo "-----------------------------------------------"
    echo "Building dtb..."
    echo "-----------------------------------------------"
    make $BUILD_VAR
    make $BUILD_VAR dtbs

    DTB_OUT="$KERNEL_DIR/out/arch/arm64/boot/dts/dtb"
    > "$DTB_OUT"
    for dtb in kona.dtb kona-v2.dtb kona-v2.1.dtb; do
        dtb_path="$KERNEL_DIR/out/arch/arm64/boot/dts/vendor/qcom/$dtb"
        if [ -f "$dtb_path" ]; then
            cat "$dtb_path" >> "$DTB_OUT"
        fi
    done
}

build_dtbo() {
    echo "-----------------------------------------------"
    echo "Building dtbo.img..."
    echo "-----------------------------------------------"
    DTBO_FILES=$(find "$KERNEL_DIR/out/arch/arm64/boot/dts/samsung/$DEVICE" -name "kona-sec-$DEVICE-*.dtbo" || true)
    if [ -n "$DTBO_FILES" ]; then
        "$KERNEL_DIR/tools/mkdtimg" create "$KERNEL_DIR/out/dtbo.img" --page_size=4096 ${DTBO_FILES}
        cp "$KERNEL_DIR/out/dtbo.img" "$IMG_DIR/dtbo.img"
    else
        echo "Warning: No DTBO files found for $DEVICE"
    fi
}

build_boot() {
    echo "-----------------------------------------------"
    echo "Building boot.img..."
    echo "-----------------------------------------------"
    MKBOOTIMG="$KERNEL_DIR/mkbootimg/mkbootimg.py"
    OUT_KERNEL="$KERNEL_DIR/out/arch/arm64/boot/Image"
    DTB_OUT="$KERNEL_DIR/out/arch/arm64/boot/dts/dtb"
    RAMDISK="$KERNEL_DIR/boot/ramdisk"
    MONTH="$(date +%Y-%m)"

    if [ ! -d "$RAMDISK" ]; then
        echo "Error: Ramdisk directory not found at $RAMDISK"
        exit 1
    fi

    $MKBOOTIMG \
        --header_version 2 \
        --kernel "$OUT_KERNEL" \
        --ramdisk "$RAMDISK" \
        --dtb "$DTB_OUT" \
        --cmdline "console=null androidboot.hardware=qcom androidboot.memcg=1 lpm_levels.sleep_disabled=1 video=vfb:640x400,bpp=32,memsize=3072000 msm_rtb.filter=0x237 service_locator.enable=1 androidboot.usbcontroller=a600000.dwc3 swiotlb=2048 printk.devkmsg=on firmware_class.path=/vendor/firmware_mnt/image loop.max_part=7" \
        --base "0x00000000" \
        --kernel_offset "0x00008000" \
        --ramdisk_offset "0x02000000" \
        --second_offset "0x00000000" \
        --dtb_offset "0x01f00000" \
        --tags_offset "0x01e00000" \
        --board "SRPUB26A012" \
        --pagesize "4096" \
        --os_version 16.0.0 \
        --os_patch_level "$MONTH" \
        --output "$IMG_DIR/boot.img"
}

prepare_ak3() {
    cd AnyKernel3/

    mv "$KERNEL_DIR/out/dtbo.img" dtbo.img || true
    mv "$KERNEL_DIR/out/arch/arm64/boot/Image" Image
    mv "$KERNEL_DIR/out/arch/arm64/boot/dts/dtb" dtb

    sed -i "s/^device\.name1=.*/device.name1=${DEVICE}/" anykernel.sh

    if [ -n "$DEVICE2" ]; then
        sed -i "s/^device\.name2=.*/device.name2=${DEVICE2}/" anykernel.sh
    fi

    if [ -n "$DEVICE3" ]; then
        sed -i "s/^device\.name3=.*/device.name3=${DEVICE3}/" anykernel.sh
    fi

    cd "$KERNEL_DIR"
}

# Run all steps
build_kernel
build_dtb
build_dtbo
build_boot
prepare_ak3
