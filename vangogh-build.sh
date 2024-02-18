#! /bin/bash

set -x

setup_export() {
    export KERNEL_PATH=$PWD
    export KERNEL_DEFCONFIG=vendor/vangogh_user_defconfig
    export KERNEL_FILE=Image
    export CLANG_VERSION=r416183b
    export BUILD_EXTRA_COMMAND='LLVM=1'
    export USE_KERNELSU=true
    export USE_KPROBES=false
    export LTO_DISABLE=false
}

setup_build_kernel_env() {
    cd $KERNEL_PATH
    BUILD_TIME=$(TZ=Asia/Shanghai date "+%Y%m%d%H%M")
    if test ! -e ~/toolchains/gcc-aosp/env_is_setup; then
      sudo pacman -S zstd tar wget curl base-devel --noconfirm
      wget -O ./lib32-ncurses.pkg.tar.zst https://archlinux.org/packages/multilib/x86_64/lib32-ncurses/download/
      wget -O ./lib32-readline.pkg.tar.zst https://archlinux.org/packages/multilib/x86_64/lib32-readline/download/
      wget -O ./lib32-zlib.pkg.tar.zst https://archlinux.org/packages/multilib/x86_64/lib32-zlib/download/
      sudo pacman -U ./lib32-ncurses.pkg.tar.zst ./lib32-readline.pkg.tar.zst ./lib32-zlib.pkg.tar.zst --noconfirm
      rm ./*.zst
      yay -S lineageos-devel python2-bin --noconfirm
    fi
    git submodule init
    git submodule update --remote --recursive
}

aosp_clang_and_gcc() {
    if test ! -e ~/toolchains/clang-aosp/$CLANG_VERSION; then
        rm -rf ~/toolchains/clang-aosp && mkdir ~/toolchains/clang-aosp && cd ~/toolchains/clang-aosp
        wget https://android.googlesource.com/platform//prebuilts/clang/host/linux-x86/+archive/b669748458572622ed716407611633c5415da25c/clang-$CLANG_VERSION.tar.gz
        tar -C ~/toolchains/clang-aosp/ -zxvf clang-$CLANG_VERSION.tar.gz
        touch ~/toolchains/clang-aosp/$CLANG_VERSION
    fi
    if test ! -d ~/toolchains/gcc-aosp; then
        cd ~/toolchains/gcc-aosp
        mkdir ~/toolchains/gcc-aosp && cd ~/toolchains/gcc-aosp
        wget https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-11.0.0_r35.tar.gz
        tar -C ~/toolchains/gcc-aosp/ -zxvf android-11.0.0_r35.tar.gz
        touch ~/toolchains/gcc-aosp/env_is_setup
    fi
}

setup_kernelsu() {
    cd $KERNEL_PATH
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s main
    if test "$USE_KPROBES" == "true"; then
        echo "CONFIG_MODULES=y" >> $KERNEL_PATH/arch/arm64/configs/$KERNEL_DEFCONFIG
        echo "CONFIG_KPROBES=y" >> $KERNEL_PATH/arch/arm64/configs/$KERNEL_DEFCONFIG
        echo "CONFIG_HAVE_KPROBES=y" >> $KERNEL_PATH/arch/arm64/configs/$KERNEL_DEFCONFIG
        echo "CONFIG_KPROBE_EVENTS=y" >> $KERNEL_PATH/arch/arm64/configs/$KERNEL_DEFCONFIG
    fi
    if test "$LTO_DISABLE" == "true"; then
        sed -i 's/CONFIG_LTO=y/CONFIG_LTO=n/' $KERNEL_PATH/arch/arm64/configs/$KERNEL_DEFCONFIG
        sed -i 's/CONFIG_LTO_CLANG=y/CONFIG_LTO_CLANG=n/' $KERNEL_PATH/arch/arm64/configs/$KERNEL_DEFCONFIG
        sed -i 's/CONFIG_THINLTO=y/CONFIG_THINLTO=n/' $KERNEL_PATH/arch/arm64/configs/$KERNEL_DEFCONFIG
        echo "CONFIG_LTO_NONE=y" >> $KERNEL_PATH/arch/arm64/configs/$KERNEL_DEFCONFIG
    fi
}

build_kernel() {
    cd $KERNEL_PATH
    export PATH=~/toolchains/clang-aosp/bin:$PATH
    make -j$(nproc --all) O=out ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=~/toolchains/gcc-aosp/bin/aarch64-linux-android- CC="ccache clang" CXX="ccache clang++" $BUILD_EXTRA_COMMAND $KERNEL_DEFCONFIG
    make -j$(nproc --all) O=out ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=~/toolchains/gcc-aosp/bin/aarch64-linux-android- CC="ccache clang" CXX="ccache clang++" $BUILD_EXTRA_COMMAND
}

make_anykernel3() {
    cd $KERNEL_PATH
    test -d $KERNEL_PATH/AnyKernel3 || git clone https://github.com/osm0sis/AnyKernel3
    if test -e $KERNEL_PATH/out/arch/arm64/boot/$KERNEL_FILE && test -d $KERNEL_PATH/AnyKernel3; then
        sed -i 's/do.devicecheck=1/do.devicecheck=0/g' AnyKernel3/anykernel.sh
        sed -i 's!block=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;!block=auto;!g' AnyKernel3/anykernel.sh
        sed -i 's/is_slot_device=0;/is_slot_device=auto;/g' AnyKernel3/anykernel.sh
        cp $KERNEL_PATH/out/arch/arm64/boot/$KERNEL_FILE $KERNEL_PATH/AnyKernel3/$KERNEL_FILE
        rm -rf AnyKernel3/.git* AnyKernel3/README.md
        cd $KERNEL_PATH/AnyKernel3
        zip -r Anykernel3.zip *
        mv $KERNEL_PATH/AnyKernel3/Anykernel3.zip $KERNEL_PATH/out/arch/arm64/boot
        rm -r $KERNEL_PATH/AnyKernel3/$KERNEL_FILE
        cd $KERNEL_PATH
        echo [INFO] Products are put in $KERNEL_PATH/out/arch/arm64/boot
        echo [INFO] Done.
    fi
}

setup_export
setup_build_kernel_env
aosp_clang_and_gcc

if [ "${1-}" == "clean" ] || [ "${2-}" == "clean" ]; then
    test -d ~/.ccache && rm -rf ~/.ccache
    test -d ~/.cache/ccache && rm -rf ~/.cache/ccache
    test -d "$KERNEL_PATH/out" && rm -rf "$KERNEL_PATH/out"
fi

setup_kernelsu
build_kernel
make_anykernel3