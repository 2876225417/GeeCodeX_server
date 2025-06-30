#!/bin/bash

# 使用自定义环境变量

SCRIPT_DIR_REALPATH=$(dirname "$(realpath "$0")")

# 引入颜色输出配置
if [ -f "${SCRIPT_DIR_REALPATH}/common_color.sh" ]; then
    source "${SCRIPT_DIR_REALPATH}/common_color.sh"
else
    echo "Warning: NOT FOUND common_color.sh, the output will be without color." >&2
    NC='' RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE=''
    BBLACK='' BRED='' BGREEN='' BYELLOW='' BBLUE='' BPURPLE='' BCYAN='' BWHITE=''
fi

# 配置 SDK路径 和 NDK 工具链 
# ANDROID_SDK_HOME
DEFAULT_SDK_HOME="$HOME/Android/Sdk"
if [ -d "$DEFAULT_SDK_HOME" ]; then 
    export ANDROID_SDK_HOME="$DEFAULT_SDK_HOME"
else 
    echo -e "${BRED}Error: ANDROID_SDK_HOME not set, and not found in common directory.${NC}"
    return 1
fi

# ANDROID_NDK_HOME
DEFAULT_NDK_PATH="$HOME/Android/Sdk/ndk/27.1.12297006" 
ALTERNATIVE_NDK_PATH="$HOME/Android/Sdk/ndk/29.0.13113456"

if [ -d "$ALTERNATIVE_NDK_PATH" ]; then
    export ANDROID_NDK_HOME="$ALTERNATIVE_NDK_PATH"
elif [ -d "$DEFAULT_NDK_PATH" ]; then 
    export ANDROID_NDK_HOME="$DEFAULT_NDK_PATH"
else 
    echo -e "${BRED}Error: Android_NDK_HOME not set, and not found in common directory.${NC}"
    return 1
fi

# 从 NDK 目录中的 source.properties 获取 NDK 版本
NDK_VERSION_STRING="Unknown"
if [ -f "$ANDROID_NDK_HOME/source.properties" ]; then
    NDK_VERSION_STRING=$(grep "Pkg.Revision" "$ANDROID_NDK_HOME/source.properties" | cut -d'=' -f2 | tr -d '[:space]')
fi

echo -e "${GREEN}NDK configuration loaded:${NC}"
echo -e "   ${CYAN}ANDROID_NDK_HOME:${NC} $ANDROID_NDK_HOME (version: $NDK_VERSION_STRING)"
echo -e "   ${CYAN}ANDROID_SDK_HOME:${NC} $ANDROID_SDK_HOME"

# 获取 NDK 中的编译器信息
if [ -n "$ANDROID_NDK_HOME" ]; then
    TOOLCHAIN_PREBUILT_PATH="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
    if [ ! -d "$TOOLCHAIN_PREBUILT_PATH" ]; then
        echo -e "${BRED}ERROR: NOT FOUND NDK PREBUILT COMPILING TOOLCHAIN: ${TOOLCHAIN_PREBUILT_PATH}${NC}"
        echo -e "${BRED}Please check ANDROID_NDK_HOME ('$ANDROID_NDK_HOME')${NC}"
        return 1
    fi
    export CLANG_COMPILER_PATH="${TOOLCHAIN_PREBUILT_PATH}/bin/clang++"
    export CLANG_C_COMPILER_PATH="${TOOLCHAIN_PREBUILT_PATH}/bin/clang"
else
    echo -e "${BRED}ERROR: ANDROID_NDK_HOME NOT SET, CAN NOT DEFINE COMPILER PATH${NC}"
    return 1
fi

echo -e "${GREEN}NDK Compiler loaded:${NC}"
echo -e "   ${CYAN}CLANG_C_COMPILER: ${CLANG_C_COMPILER_PATH} ${NC}"
echo -e "   ${CYAN}CLANG_CXX_COMPILER: ${CLANG_COMPILER_PATH} ${NC}"

CLANG_VERSION_STRING="Unknown"

if [ -x "$CLANG_COMPILER_PATH" ]; then
    _clang_version_output=$("$CLANG_COMPILER_PATH" --version 2>&1) || CLANG_VERSION_STRING="Failed to execute --version" 
    if [ -n "$_clang_version_output" ] && [[ "$_clang_version_output" != "Failed to execute --version" ]]; then
        CLANG_VERSION_STRING=$(echo "$_clang_version_output" | head -n 1)
        echo -e "   ${CYAN}Clang Version: $CLANG_VERSION_STRING${NC}"
    fi
else
    CLANG_VERSION_STRING="NOT FOUND clang++ IN SPECIFIED PATH: $CLANG_COMPILER_PATH OR NOT EXECUTABLE" 
fi
export CLANG_VERSION_STRING

echo ""
echo -e "${BGREEN}--- Loading Host Compiler Information ---${NC}"
HOST_GCC_PATH=$(which gcc || echo "Not Found")
HOST_GXX_PATH=$(which g++ || echo "Not Found")
HOST_CLANG_PATH=$(which clang || echo "Not Found")
HOST_CLANGXX_PATH=$(which clang++ || echo "Not Found")

HOST_GCC_VERSION="Unknown"
HOST_CLANG_VERSION="Unknown"

if [ "$HOST_GCC_PATH" != "Not Found" ] && [ -x "$HOST_GXX_PATH" ]; then
    HOST_GCC_VERSION=$("$HOST_GXX_PATH" --version | head -n 1)
fi

if [ "$HOST_CLANG_PATH" != "Not Found" ] && [ -x "$HOST_CLANGXX_PATH" ]; then
    HOST_CLANG_VERSION=$("$HOST_CLANGXX_PATH" --version | head -n 1)
fi

export HOST_GCC_PATH
export HOST_GXX_PATH
export HOST_GCC_VERSION
export HOST_CLANG_PATH
export HOST_CLANGXX_PATH
export HOST_CLANG_VERSION




return 0






