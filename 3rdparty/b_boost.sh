#!/bin/bash

SCRIPT_DIR_REALPATH=$(dirname "$(realpath "$0")")

###### ! Warning ! #########
#  该脚本当前既能够完成        #  
#  Linux x86_64 架构的编译   #
#  对于 NDK 的交叉编译尚不支持 #
#   Boost Version: 1.88.0  #
# # # # # # # # # # # # # #


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

 ABIS_TO_BUILD=("linux-x86_64")

if [[ "$TARGET_PLATFORM" == "android" || "$TARGET_PLATFORM" == "all" ]]; then 
    # 引入 NDK 工具链配置 export ANDROID_NDK_HOME
    if [ -f "${SCRIPT_DIR_REALPATH}/common_env.sh" ]; then
        source "${SCRIPT_DIR_REALPATH}/common_env.sh"
    else
        echo -e "${BRED}ERROR: NO ANDROID_NDK_HOME CONFIGURED.${NC}"
        echo -e "${BYELLOW}Tip: Try to export ANDROID_NDK_HOME="ANDROID NDK Dev Toolchain."${NC}"
        exit 1
    fi

    # 配置构建 ABI 及相关的 API Level
    ABIS_TO_BUILD+=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")
    ANDROID_API_ARM32="21"
    ANDROID_API_ARM64="24"
    ANDROID_API_X86="24"
    ANDROID_API_X86_64="24"
    CLANG_VERSION_FOR_JAM="20.0"
    HOST_TAG_FOR_JAM="linux-x86_64"

    # 配置 NDK 工具链
    NDK_TOOLCHAIN_BIN_PATH="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
fi

BOOST_VERSION="1.88.0"
BOOST_VERSION_UNDERSCORE="${BOOST_VERSION//./_}"

SCRIPT_BASE_DIR="$(pwd)"

# --- Boost 源码目录 ---
BOOST_SOURCE_PARENT_DIR="${SCRIPT_BASE_DIR}/source/boost"
BOOST_SOURCE_DIR_NAME="boost_${BOOST_VERSION_UNDERSCORE}"
BOOST_SOURCE_DIR_FULL_PATH="${BOOST_SOURCE_PARENT_DIR}/${BOOST_SOURCE_DIR_NAME}"

echo -e "${YELLOW}--- Clearing Boost source---${NC}"
rm -rf "$BOOST_SOURCE_DIR_FULL_PATH"

# --- Boost 构建目录 ---
BOOST_BUILD_ROOT_DIR="${SCRIPT_BASE_DIR}/build/boost"

# --- Boost 安装目录 ---
BOOST_INSTALL_ROOT_DIR="${SCRIPT_BASE_DIR}/boost"

# ---- Boost 源码 ----
echo -e "${YELLOW}--- Preparing Boost source: $BOOST_SOURCE_PARENT_DIR ---${NC}"
mkdir -p "$BOOST_SOURCE_PARENT_DIR"

BOOST_TARBALL="boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2"
BOOST_DOWNLOAD_URL="https://sourceforge.net/projects/boost/files/boost/${BOOST_VERSION}/${BOOST_TARBALL}/download"

if [ ! -d "$BOOST_SOURCE_DIR_FULL_PATH" ]; then
    if [ ! -f "${BOOST_SOURCE_PARENT_DIR}/${BOOST_TARBALL}" ]; then
        echo -e "${BLUE}--- Downloading Boost ${BOOST_VERSION} source ---${NC}"
        wget -O "${BOOST_SOURCE_PARENT_DIR}/${BOOST_TARBALL}" "$BOOST_DOWNLOAD_URL"
    else
        echo -e "${YELLOW}--- Boost source tarball existed ---${NC}"
    fi
    echo -e "${BLUE}--- Decompressing Boost source ---${NC}"
    tar -xjf "${BOOST_SOURCE_PARENT_DIR}/${BOOST_TARBALL}" -C "$BOOST_SOURCE_PARENT_DIR"
else
    echo -e "${YELLOW}--- Boost source directory existed: $BOOST_SOURCE_DIR_FULL_PATH ---${NC}"
fi

# ---- 自举编译 Boost ----
cd "$BOOST_SOURCE_DIR_FULL_PATH"
if [ ! -f "./b2" ]; then
    echo -e "${BLUE}--- Running Boost bootstrap.sh ---${NC}"
    ./bootstrap.sh
else
    echo -e "${BLUE}--- b2 EXISTED ---${NC}"
fi

if [[ "$TARGET_PLATFORM" == "android" || "$TARGET_PLATFORM" == "all" ]]; then 
    # ---- 生成 project-config.jam ----
    PYTHON_JAM_GENERATOR="${SCRIPT_DIR_REALPATH}/gen_boost_jam.py"
    echo -e "${BLUE}--- Generating project-config.jam ---${NC}"
    export ENV_ANDROID_NDK_HOME="${ANDROID_NDK_HOME}"
    export ENV_ANDROID_API_ARM64="${ANDROID_API_ARM64}"
    export ENV_ANDROID_API_ARM32="${ANDROID_API_ARM32}"
    export ENV_ANDROID_API_X86="${ANDROID_API_X86}"
    export ENV_ANDROID_API_X86_64="${ANDROID_API_X86_64}"
    export ENV_HOST_TAG="${HOST_TAG_FOR_JAM}"
    export ENV_CLANG_VERSION_FOR_JAM="${CLANG_VERSION_FOR_JAM}"
    CLANG_MAJOR_VERSION_SHORT=$(echo $CLANG_VERSION_FOR_JAM | cut -d. -f1)
fi

# --- 构建和安装的根目录 ---
mkdir -p "$BOOST_BUILD_ROOT_DIR"
mkdir -p "$BOOST_INSTALL_ROOT_DIR"

cd "$SCRIPT_BASE_DIR"

for CURRENT_ABI in "${ABIS_TO_BUILD[@]}"; do
    echo ""
    echo -e "${YELLOW}==============================================================================================${NC}"
    TOOLSET_NAME_FOR_B2_VERSION_SUFFIX=""

    B2_PROP_ARCHITECTURE=""
    B2_PROP_ADDRESS_MODEL=""
    B2_PROP_ABI=""

    CURRENT_API_LEVEL_FOR_B2=""
    B2_EXTRA_DEFINES_FOR_B2=""

    if [[ "$TARGET_PLATFORM" == "android" || "$TARGET_PLATFORM" == "all" ]]; then 
        echo -e "${YELLOW}Building Boost for ABI: $CURRENT_ABI, Toolchain: clang-${TOOLSET_NAME_FOR_B2_VERSION_SUFFIX}, Target API: $CURRENT_API_LEVEL_FOR_B2${NC}"
    else 
        echo -e "${YELLOW}Building Boost for $CURRENT_ABI${NC}"
    fi
    echo -e "${YELLOW}==============================================================================================${NC}"

    if [[ "$TARGET_PLATFORM" == "android" || "$TARGET_PLATFORM" == "all" ]]; then 
        INSTALL_DIR_ABI="${BOOST_INSTALL_ROOT_DIR}/boost_android_${CURRENT_ABI}"
        B2_BUILD_DIR_ABI="${BOOST_BUILD_ROOT_DIR}/boost_build_android_${CURRENT_ABI}"
    else
        INSTALL_DIR_ABI="${BOOST_INSTALL_ROOT_DIR}/boost_${CURRENT_ABI}"
        B2_BUILD_DIR_ABI="${BOOST_BUILD_ROOT_DIR}/boost_build_${CURRENT_ABI}"
    fi
    mkdir -p "$B2_BUILD_DIR_ABI"
    mkdir -p "$INSTALL_DIR_ABI"

    cd "$BOOST_SOURCE_DIR_FULL_PATH"

    echo -e "${YELLOW}--- Building and installing Boost for ABI $CURRENT_ABI(It will take a long time...) ---${NC}"
    if [ -d "$B2_BUILD_DIR_ABI" ]; then
      echo -e "${YELLOW}--- Clearing b2 build directory: $B2_BUILD_DIR_ABI ---${NC}"
      rm -rf "$B2_BUILD_DIR_ABI"
    fi
    mkdir -p "$B2_BUILD_DIR_ABI"

    # Boost 构建日志
    BOOST_BUILD_LOG_FILE_DIR="${SCRIPT_BASE_DIR}/logs/boost"
    mkdir -p "${BOOST_BUILD_LOG_FILE_DIR}"
    LOG_FILE_FOR_ABI="${BOOST_BUILD_LOG_FILE_DIR}/boost_build_${CURRENT_ABI}.log"
    rm -rf "$LOG_FILE_FOR_ABI"
    if [ "$CURRENT_ABI" = "linux-x86_64" ]; then
        B2_ARGS=(
            "install"
            "--prefix=${INSTALL_DIR_ABI}"
            "--build-dir=${B2_BUILD_DIR_ABI}"
            "toolset=gcc"
            "link=shared"
            "threading=multi"
            "cxxstd=17"
            "variant=release"
            "--layout=system"
            "-j$(nproc)"
        )
    else
        # 生成 project-config.jam文件用于 b2 的编译
        # if ! python3 "$PYTHON_JAM_GENERATOR"; then
        # echo -e "${BRED}Error: Failed to run gen_boost_jam.py ${NC}" >&2
        # exit 1 
        # fi

        # if [ ! -f "./project-config.jam" ]; then
        # echo -e "${BRED}Error: NOT GENERATE project-config.jam ${NC}" >&2
        # exit 1
        # fi

        unset ENV_ANDROID_NDK_HOME
        unset ENV_ANDROID_API_ARM64
        unset ENV_ANDROID_API_ARM32
        unset ENV_ANDROID_API_X86
        unset ENV_ANDROID_API_X86_64
        unset ENV_HOST_TAG
        unset ENV_CLANG_VERSION_FOR_JAM

        if [ "$CURRENT_ABI" = "arm64-v8a" ]; then
            TOOLSET_NAME_FOR_B2_VERSION_SUFFIX="${CLANG_MAJOR_VERSION_SHORT}_android64"
            
            B2_PROP_ARCHITECTURE="architecture=arm"
            B2_PROP_ADDRESS_MODEL="address-model=64"
            B2_PROP_ABI="abi=aapcs"
            
            CURRENT_API_LEVEL_FOR_B2=$ANDROID_API_ARM64
        elif [ "$CURRENT_ABI" = "armeabi-v7a" ]; then
            TOOLSET_NAME_FOR_B2_VERSION_SUFFIX="${CLANG_MAJOR_VERSION_SHORT}_android32"
            
            B2_PROP_ARCHITECTURE="architecture=arm"
            B2_PROP_ADDRESS_MODEL="address-model=32"
            B2_PROP_ABI="abi=aapcs"
            
            CURRENT_API_LEVEL_FOR_B2=$ANDROID_API_ARM32
            B2_EXTRA_DEFINES_FOR_B2="define=BOOST_ASIO_DISABLE_CONCEPTS"
        elif [ "$CURRENT_ABI" = "x86" ]; then
            TOOLSET_NAME_FOR_B2_VERSION_SUFFIX="${CLANG_MAJOR_VERSION_SHORT}_androidx86"
            
            B2_PROP_ARCHITECTURE="architecture=x86"
            B2_PROP_ADDRESS_MODEL="address-model=32"
            
            CURRENT_API_LEVEL_FOR_B2=$ANDROID_API_X86
        elif [ "$CURRENT_ABI" = "x86_64" ]; then
            TOOLSET_NAME_FOR_B2_VERSION_SUFFIX="${CLANG_MAJOR_VERSION_SHORT}_androidx86_64"
            
            B2_PROP_ARCHITECTURE="architecture=x86"
            B2_PROP_ADDRESS_MODEL="address-model=64"
            
            CURRENT_API_LEVEL_FOR_B2=$ANDROID_API_X86_64
        else
            echo -e "${RED}Error: Not suported ABI $CURRENT_ABI ${NC}" >&2
            continue
        fi

        B2_ARGS=(
            "install"
            "--prefix=${INSTALL_DIR_ABI}"
            "--build-dir=${B2_BUILD_DIR_ABI}"
            "toolset=clang-${TOOLSET_NAME_FOR_B2_VERSION_SUFFIX}"
            "target-os=android"
            "${B2_PROP_ARCHITECTURE}"
            "${B2_PROP_ADDRESS_MODEL}"
        )

        if [ -n "$B2_PROP_ABI" ]; then B2_ARGS+=("${B2_PROP_ABI}"); fi
        B2_ARGS+=(
            link=shared
            variant=release
            threading=multi
            --layout=system
            "-j$(nproc)"
            define=BOOST_SYSTEM_NO_DEPRECATED
            define=BOOST_ERROR_CODE_HEADER_ONLY
            define=BOOST_COROUTINES_NO_DEPRECATION_WARNINGS        
            --without-python                      # 减少编译错误
            --without-mpi                         # 减少编译错误
            "boost.stacktrace.from_exception=off" #减少编译错误         
            # --enable-static-runtime
        )
    fi
    if [ -n "$B2_EXTRA_DEFINES_FOR_B2" ]; then B2_ARGS+=("${B2_EXTRA_DEFINES_FOR_B2}"); fi
    
    echo "Execute b2: ./b2 ${B2_ARGS[*]}" >> "${LOG_FILE_FOR_ABI}"

    BUILD_SUCCESSFUL_FLAG=false
    if ./b2 "${B2_ARGS[@]}" >> "${LOG_FILE_FOR_ABI}" 2>&1; then
        B2_REAL_EXIT_CODE=0
        BUILD_SUCCESSFUL_FLAG=true
    else
        B2_REAL_EXIT_CODE=$?
    fi

    if [ "$BUILD_SUCCESSFUL_FLAG" = true ]; then
        echo -e "${GREEN}Boost ABI $CURRENT_ABI built successfully. Log file: ${LOG_FILE_FOR_ABI}${NC}"

        REPORT_FILE="${INSTALL_DIR_ABI}/build_report_${CURRENT_ABI}.txt"
        rm -rf "${REPORT_FILE}"
        echo "Boost Build Report"               >> "$REPORT_FILE"
        echo "==============================="  >> "$REPORT_FILE"
        echo "Date: $(date)"                    >> "$REPORT_FILE"
        echo "ABI: $CURRENT_ABI"                >> "$REPORT_FILE"
        echo "Boost Version: $BOOST_VERSION"    >> "$REPORT_FILE"
        echo "Build Configuration (b2 variant): release"    >> "$REPORT_FILE"
        echo "Linkage: shared"                  >> "$REPORT_FILE"
        echo "Threading: multi"                 >> "$REPORT_FILE"
        if [[ "$TARGET_PLATFORM" == "android" || "$TARGET_PLATFORM" == "all" ]]; then 
            echo "Android API Level (configured in project-config.jam): $CURRENT_API_LEVEL_FOR_B2" >> "$REPORT_FILE"
            echo "NDK Path: $ENV_ANDROID_NDK_HOME"  >> "$REPORT_FILE"
            echo "NDK Version (from source.properties): $NDK_VERSION_STRING" >> "$REPORT_FILE"
            echo "CLANG_CXX_COMPILER_PATH: $CLANG_COMPILER_PATH"    >> "$REPORT_FILE"
            echo "CLANG_C_COMPILER: $CLANG_C_COMPILER_PATH"         >> "$REPORT_FILE"
            echo "Clang Version: $CLANG_VERSION_STRING"             >> "$REPORT_FILE"
        fi
        echo ""                                 >> "$REPORT_FILE"
        echo "b2 Arguments Used: "              >> "$REPORT_FILE"
        printf "    %s\n" "${B2_ARGS[@]}"       >> "$REPORT_FILE"
        echo ""                                 >> "$REPORT_FILE"
    fi

    if [ $B2_REAL_EXIT_CODE -ne 0 ]; then
      echo -e "${BRED}Error: Failed to build Boost for ABI $CURRENT_ABI, EXIT CODE: $B2_REAL_EXIT_CODE${NC}"
      echo -e "${BRED}Check detailed log: ${LOG_FILE_FOR_ABI}${NC}" >&2
    fi

    cd "$SCRIPT_BASE_DIR"

    echo -e "${YELLOW}--- Boost for ABI $CURRENT_ABI installed: $INSTALL_DIR_ABI---${NC}"
    echo -e "${YELLOW}--------------------------------------------------------------------------------------------------${NC}"
done

echo -e ""
echo -e "${YELLOW}==================================================${NC}"
echo -e "${BLUE}All Boost ABI built.${NC}"
ls -1 "$BOOST_INSTALL_ROOT_DIR"
echo -e "${YELLOW}==================================================${NC}"
