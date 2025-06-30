#!/bin/bash
set -e

SCRIPT_DIR_REALPATH=$(dirname "$(realpath "$0")")

# 引入颜色输出配置
if [ -f "${SCRIPT_DIR_REALPATH}/common_color.sh" ]; then
    source "${SCRIPT_DIR_REALPATH}/common_color.sh"
else
    echo "Warning: NOT FOUND common_color.sh, the output will be without color." >&2
    NC='' RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN='' WHITE=''
    BBLACK='' BRED='' BGREEN='' BYELLOW='' BBLUE='' BPURPLE='' BCYAN='' BWHITE=''
fi

# 指定构建平台
print_usage() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo -e "${YELLOW}Options: ${NC}"
    echo -e "   ${CYAN}--target_platform=<platform>         ${NC}       Specify the target platform."
    echo -e "   Supported Platforms: ${GREEN}android, linux, all(both android and linux)${NC}"
}

TARGET_PLATFORM=""
for i in "$@"; do
    case $i in
        --target_platform=*)
        TARGET_PLATFORM="${i#*=}"
        shift
        ;;
        *)
        echo -e "${BRED}Error: Unknown option '$i'${NC}"
        print_usage
        exit 1
        ;;
    esac
done

if [ -z "$TARGET_PLATFORM" ]; then
    echo -e "${BRED}Error: Target platform must be specified.${NC}"
    print_usage
    exit 1
fi

ABIS_TO_BUILD=()
if [[ "$TARGET_PLATFORM" == "linux" || "$TARGET_PLATFORM" == "all" ]]; then
    ABIS_TO_BUILD+=("linux-x86_64")
fi

if [[ "$TARGET_PLATFORM" == "android" || "$TARGET_PLATFORM" == "all" ]]; then
    # 引入 NDK 工具链配置 export ANDROID_NDK_HOME
    if [ -f "${SCRIPT_DIR_REALPATH}/common_env.sh" ]; then
        source "${SCRIPT_DIR_REALPATH}/common_env.sh"
    else
        echo -e "${BRED}ERROR: NO ANDROID_NDK_HOME CONFIGURED.${NC}"
        echo -e "${BYELLOW}Tip: Try to export ANDROID_NDK_HOME=\"/path/to/your/ndk\"${NC}"
        exit 1
    fi

    # 配置构建 ABI 及相关的 API Level
    ABIS_TO_BUILD+=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")
    ANDROID_API_ARM32="21"
    ANDROID_API_ARM64="21"
    ANDROID_API_X86="21"
    ANDROID_API_X86_64="21"

    # NDK 工具链路径
    NDK_TOOLCHAIN_BIN_PATH="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
fi

# --- OpenSSL 配置 ---
OPENSSL_VERSION="3.5.0"
SCRIPT_BASE_DIR="$(pwd)"

# --- OpenSSL 源码目录 ---
OPENSSL_SOURCE_PARENT_DIR="${SCRIPT_BASE_DIR}/source/openssl"
OPENSSL_SOURCE_DIR_NAME="openssl-${OPENSSL_VERSION}"
OPENSSL_SOURCE_DIR_FULL_PATH="${OPENSSL_SOURCE_PARENT_DIR}/${OPENSSL_SOURCE_DIR_NAME}"

# --- OpenSSL 构建/安装/构建日志根目录 ---
OPENSSL_BUILD_ROOT_DIR="${SCRIPT_BASE_DIR}/build/openssl"
OPENSSL_INSTALL_ROOT_DIR="${SCRIPT_BASE_DIR}/openssl"
OPENSSL_LOG_DIR="${SCRIPT_BASE_DIR}/logs/openssl"

# ---- OpenSSL 源码准备 ----
echo -e "${YELLOW}--- Preparing OpenSSL source: $OPENSSL_SOURCE_PARENT_DIR ---${NC}"
mkdir -p "$OPENSSL_SOURCE_PARENT_DIR"

OPENSSL_TARBALL="openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_DOWNLOAD_URL="https://www.openssl.org/source/${OPENSSL_TARBALL}"

if [ ! -d "$OPENSSL_SOURCE_DIR_FULL_PATH" ]; then
    if [ ! -f "${OPENSSL_SOURCE_PARENT_DIR}/${OPENSSL_TARBALL}" ]; then
        echo -e "${BLUE}--- Downloading OpenSSL ${OPENSSL_VERSION} source ---${NC}"
        wget -O "${OPENSSL_SOURCE_PARENT_DIR}/${OPENSSL_TARBALL}" "$OPENSSL_DOWNLOAD_URL"
    else
        echo -e "${YELLOW}--- OpenSSL source tarball already existed ---${NC}"
    fi
    echo -e "${BLUE}--- Decompressing OpenSSL source ---${NC}"
    tar -xzf "${OPENSSL_SOURCE_PARENT_DIR}/${OPENSSL_TARBALL}" -C "$OPENSSL_SOURCE_PARENT_DIR"
else
    echo -e "${YELLOW}--- OpenSSL source directory already existed: $OPENSSL_SOURCE_DIR_FULL_PATH ---${NC}"
fi

# --- 创建构建和安装的根目录 ---
mkdir -p "$OPENSSL_BUILD_ROOT_DIR"
mkdir -p "$OPENSSL_INSTALL_ROOT_DIR"
mkdir -p "$OPENSSL_LOG_DIR"

for CURRENT_ABI in "${ABIS_TO_BUILD[@]}"; do
    echo ""
    echo -e "${YELLOW}==============================================================================================${NC}"
    echo -e "${YELLOW}Building OpenSSL for ABI: $CURRENT_ABI ${NC}"
    echo -e "${YELLOW}==============================================================================================${NC}"

    INSTALL_DIR_ABI="${OPENSSL_INSTALL_ROOT_DIR}/openssl_${CURRENT_ABI}"
    LOG_FILE_FOR_ABI="${OPENSSL_LOG_DIR}/openssl_build_${CURRENT_ABI}.log"
    
    # 清理旧目录和日志
    rm -rf "$INSTALL_DIR_ABI"
    rm -f "$LOG_FILE_FOR_ABI"
    mkdir -p "$INSTALL_DIR_ABI"

    # 进入源码目录进行构建
    cd "$OPENSSL_SOURCE_DIR_FULL_PATH"
    
    # 清理上一次构建的产物
    make clean > /dev/null 2>&1 || true

    OPENSSL_TARGET=""
    CONFIGURE_EXTRA_ARGS=""

    if [ "$CURRENT_ABI" = "linux-x86_64" ]; then
        OPENSSL_TARGET="linux-x86_64"
    else
        # Android 交叉编译配置
        case "$CURRENT_ABI" in
            "arm64-v8a")
                OPENSSL_TARGET="android-arm64"
                CONFIGURE_EXTRA_ARGS="-D__ANDROID_API__=${ANDROID_API_ARM64}"
                ;;
            "armeabi-v7a")
                OPENSSL_TARGET="android-arm"
                CONFIGURE_EXTRA_ARGS="-D__ANDROID_API__=${ANDROID_API_ARM32}"
                ;;
            "x86_64")
                OPENSSL_TARGET="android-x86_64"
                CONFIGURE_EXTRA_ARGS="-D__ANDROID_API__=${ANDROID_API_X86_64}"
                ;;
            "x86")
                OPENSSL_TARGET="android-x86"
                CONFIGURE_EXTRA_ARGS="-D__ANDROID_API__=${ANDROID_API_X86}"
                ;;
            *)
                echo -e "${RED}Error: Unsupported Android ABI '$CURRENT_ABI'${NC}" >&2
                continue
                ;;
        esac
        # 将 NDK 工具链添加到 PATH，供 Configure 脚本查找
        export PATH=$NDK_TOOLCHAIN_BIN_PATH:$PATH
    fi
    
    echo -e "${YELLOW}--- Configuring OpenSSL for $CURRENT_ABI ---${NC}"
    echo "Configure Target: ${OPENSSL_TARGET}" >> "${LOG_FILE_FOR_ABI}"
    echo "Extra Args: ${CONFIGURE_EXTRA_ARGS}" >> "${LOG_FILE_FOR_ABI}"

    # 1. 配置 (Configure)
    # --prefix: 指定安装目录
    # --openssldir: 指定配置文件、证书等的存放目录, 通常与 prefix 相同
    # shared: 生成共享库 (.so)
    # no-tests: 不编译测试，加速构建
    # -Wl,-rpath,'$(LIBRPATH)': 将库的运行时搜索路径嵌入，以便在非标准位置也能找到
    ./Configure "$OPENSSL_TARGET" \
        --prefix="$INSTALL_DIR_ABI" \
        --openssldir="$INSTALL_DIR_ABI/ssl" \
        shared \
        no-tests \
        no-docs \
        -Wl,-rpath,'$(LIBRPATH)' \
        $CONFIGURE_EXTRA_ARGS >> "${LOG_FILE_FOR_ABI}" 2>&1

    echo -e "${YELLOW}--- Building OpenSSL for $CURRENT_ABI (make) ---${NC}"
    # 2. 编译 (make)
    if make -j$(nproc) >> "${LOG_FILE_FOR_ABI}" 2>&1; then
      echo -e "${YELLOW}--- Installing OpenSSL for $CURRENT_ABI (make install) ---${NC}"
      # 3. 安装 (make install_sw) 只安装库和头文件，不安装文档
      if make install_sw >> "${LOG_FILE_FOR_ABI}" 2>&1; then
        echo -e "${GREEN}OpenSSL for ABI $CURRENT_ABI built and installed successfully.${NC}"
        
        # 4. 生成构建报告
        REPORT_FILE="${INSTALL_DIR_ABI}/build_report_${CURRENT_ABI}.txt"
        echo "OpenSSL Build Report"             >> "$REPORT_FILE"
        echo "==============================="  >> "$REPORT_FILE"
        echo "Date: $(date)"                    >> "$REPORT_FILE"
        echo "ABI: $CURRENT_ABI"                >> "$REPORT_FILE"
        echo "OpenSSL Version: $OPENSSL_VERSION" >> "$REPORT_FILE"
        echo "Install Path: $INSTALL_DIR_ABI"   >> "$REPORT_FILE"
        if [[ "$CURRENT_ABI" != "linux-x86_64" ]]; then
            echo "Platform: Android"            >> "$REPORT_FILE"
            echo "NDK Path: $ANDROID_NDK_HOME"  >> "$REPORT_FILE"
        else
            echo "Platform: Linux"              >> "$REPORT_FILE"
        fi
        echo "Log File: ${LOG_FILE_FOR_ABI}"    >> "$REPORT_FILE"

      else
        echo -e "${BRED}Error: Failed to install OpenSSL for ABI $CURRENT_ABI${NC}" >&2
        echo -e "${BRED}Check detailed log: ${LOG_FILE_FOR_ABI}${NC}" >&2
      fi
    else
      echo -e "${BRED}Error: Failed to build OpenSSL for ABI $CURRENT_ABI${NC}" >&2
      echo -e "${BRED}Check detailed log: ${LOG_FILE_FOR_ABI}${NC}" >&2
    fi

    cd "$SCRIPT_BASE_DIR"

    echo -e "${YELLOW}--- OpenSSL for ABI $CURRENT_ABI installed to: $INSTALL_DIR_ABI---${NC}"
    echo -e "${YELLOW}--------------------------------------------------------------------------------------------------${NC}"
done

echo ""
echo -e "${YELLOW}==================================================${NC}"
echo -e "${BLUE}All selected OpenSSL ABIs have been processed.${NC}"
echo -e "${BLUE}Installation summary:${NC}"
ls -1 "$OPENSSL_INSTALL_ROOT_DIR"
echo -e "${YELLOW}==================================================${NC}"

