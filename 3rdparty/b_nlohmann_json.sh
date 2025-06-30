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

# 引入 GIT 配置
COMMON_GIT_SCRIPT="${SCRIPT_DIR_REALPATH}/common_git.sh"
if [ -f "$COMMON_GIT_SCRIPT" ]; then
    source "$COMMON_GIT_SCRIPT"
else
    echo -e "${RED}Error: NOT FOUND common_git.sh under ${COMMON_GIT_SCRIPT}${NC}" >&2 
    exit 1
fi

# 引入 NDK 工具链配置 export ANDROID_NDK_HOME
if [ -f "${SCRIPT_DIR_REALPATH}/common_env.sh" ]; then
    source "${SCRIPT_DIR_REALPATH}/common_env.sh"
else
    echo -e "${BRED}ERROR: NO ANDROID_NDK_HOME CONFIGURED.${NC}"
    echo -e "${BYELLOW}Tip: Try to export ANDROID_NDK_HOME="ANDROID NDK Dev Toolchain."${NC}"
    exit 1
fi

# 配置 nlohmann json 仓库
NLOHMANN_JSON_VERSION_TAG="develop"
NLOHMANN_JSON_REPO_URL="https://github.com/nlohmann/json.git"

# 配置 nlohmann json 相关路径
SCRIPT_BASE_DIR="$(pwd)"
NLOHMANN_JSON_SOURCE_DIR="${SCRIPT_BASE_DIR}/source/nlohmann_json"
NLOHMANN_JSON_BUILD_BASE_DIR="${SCRIPT_BASE_DIR}/build/nlohmann_json"
NLOHMANN_JSON_INSTALL_BASE_DIR="${SCRIPT_BASE_DIR}/nlohmann_json"

# --- 准备源码 ---
echo -e "${YELLOW}--- Preparing nlohmann_json source: ${NLOHMANN_JSON_SOURCE_DIR} ---${NC}"
mkdir -p "$NLOHMANN_JSON_SOURCE_DIR"
echo -e "${YELLOW}--- Handling nlohmann_json Source Repository ---${NC}"
git_clone_or_update "$NLOHMANN_JSON_REPO_URL" "$NLOHMANN_JSON_SOURCE_DIR" "$NLOHMANN_JSON_VERSION_TAG"

print_usage() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]${NC}"
    echo ""
    echo -e "${YELLOW}Options: ${NC}"
    echo -e "   ${CYAN}--target_platform=<platform>         ${NC}       Specify the target platform."
    echo -e "   Supported Platforms: ${GREEN}android, linux${NC}"
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

build_nlohmann_json_for_platform() {
    local abi="$1"
    local platform_version="$2"
    local extra_cmake_flags="$3"

    # 编译、安装和编译日志路径(删除再重新创建)
    NLOHMANN_JSON_BUILD_DIR="${NLOHMANN_JSON_BUILD_BASE_DIR}/nlohmann_json_$abi"
    echo -e "${GREEN}--- Creating and cleaning nlohmann_json build directory ---${NC}"
    rm -rf "$NLOHMANN_JSON_BUILD_DIR"
    mkdir -p "$NLOHMANN_JSON_BUILD_DIR"

    NLOHMANN_JSON_INSTALL_PREFIX_DIR="${NLOHMANN_JSON_INSTALL_BASE_DIR}/nlohmann_json_$abi/nlohmann_json"
    echo -e "${GREEN}--- Creating and cleaning nlohmann_json install directory ---${NC}"
    rm -rf "$NLOHMANN_JSON_INSTALL_PREFIX_DIR"
    mkdir -p "$NLOHMANN_JSON_INSTALL_PREFIX_DIR"

    NLOHMANN_JSON_LOG_DIR="${SCRIPT_BASE_DIR}/logs/nlohmann_json"
    mkdir -p "$NLOHMANN_JSON_LOG_DIR"
    NLOHMANN_JSON_LOG_FILE="${NLOHMANN_JSON_LOG_DIR}/nlohmann_json_$abi.txt"

    CMAKE_ARGS=(
        "-DCMAKE_INSTALL_PREFIX"="${NLOHMANN_JSON_INSTALL_PREFIX_DIR}"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DNLOHMANN_JSON_BUILD_EXAMPLES=OFF"
        "-DNLOHMANN_JSON_BUILD_TESTS=OFF"
        # "-DNLOHMANN_JSON_BUILD_SHARED=OFF"
    )
    
    if [ "$TARGET_PLATFORM" = "android" ]; then
        CMAKE_ARGS+=(
            "-DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
            "-DANDROID_ABI=${abi}"
            "-DANDROID_PLATFORM=android-${platform_version}"
            "-DCMAKE_ANDROID_ARCH_ABI=${abi}"
            "-DCMAKE_EXE_LINKER_FLAGS=-llog" # 解决链接时的错误信息
        )
    fi

    if [ -n "$extra_cmake_flags" ]; then
        CMAKE_ARGS+=($extra_cmake_flags)
    fi

    cd "$NLOHMANN_JSON_BUILD_DIR"
    echo -e "${YELLOW}--- Configuring nlohmann_json for platform: $abi ---${NC}"

    echo "CMake Configurations:" > "$NLOHMANN_JSON_LOG_FILE"
    echo "cmake -S \"$NLOHMANN_JSON_SOURCE_DIR\" -B \"$NLOHMANN_JSON_BUILD_DIR\" ${CMAKE_ARGS[*]}" >> "$NLOHMANN_JSON_LOG_FILE"

    if cmake -S "$NLOHMANN_JSON_SOURCE_DIR" -B "$NLOHMANN_JSON_BUILD_DIR" "${CMAKE_ARGS[@]}" >> "$NLOHMANN_JSON_LOG_FILE"; then
        CMAKE_CONFIG_EXIT_CODE=0
    else
        CMAKE_CONFIG_EXIT_CODE=$?
    fi

    if [ "$CMAKE_CONFIG_EXIT_CODE" -ne 0 ]; then
        echo -e "${BRED}Error: Failed to configure cmake for nlohmann_json(platform: $abi), EXIT CODE: $CMAKE_CONFIG_EXIT_CODE${NC}" >&2
        echo -e "${BRED}Please check detailed log: ${NLOHMANN_JSON_LOG_FILE}${NC}" >&2
        return 1
    fi

    echo -e "${YELLOW}--- Building nlohmann_json for platform: $abi... --- ${NC}"
    if cmake --build "$NLOHMANN_JSON_BUILD_DIR" --config Release --parallel $(nproc) >> "$NLOHMANN_JSON_LOG_FILE"; then
        CMAKE_BUILD_EXIT_CODE=0
    else
        CMAKE_BUILD_EXIT_CODE=$?
    fi

    if [ "$CMAKE_BUILD_EXIT_CODE" -ne 0 ]; then
        echo -e "${BRED}Error: Failed to build nlohmann_json for platform: $abi, EXIT CODE: $CMAKE_BUILD_EXIT_CODE${NC}" >&2
        echo -e "${BRED}Please check detailed log: ${NLOHMANN_JSON_LOG_FILE} ${NC}" >&2
        return 1
    else
        echo -e "${GREEN}nlohmann_json built for platform: $abi successfully${NC}"
        BUILD_SUCCESSFUL_FLAG=true
    fi

    if [ "$BUILD_SUCCESSFUL_FLAG" = true ]; then
        echo -e "${YELLOW}--- Installing nlohmann_json for platform: $abi ---${NC}"
        if cmake --install . --config Release >> "$NLOHMANN_JSON_LOG_FILE" 2>&1; then
            CMAKE_INSTALL_EXIT_CODE=0
        else
            CMAKE_INSTALL_EXIT_CODE=$?
        fi

        if [ "$CMAKE_INSTALL_EXIT_CODE" -ne 0 ]; then
            echo -e "${BRED}Error: Failed to install nlohmann_json for platform: $abi, EXIT CODE: $CMAKE_INSTALL_EXIT_CODE ${NC}" >&2
            echo -e "${BRED}Please check detailed log: ${NLOHMANN_JSON_LOG_FILE} ${NC}" >&2
            BUILD_SUCCESSFUL_FLAG=false
            return 1
        else
            echo -e "${YELLOW}--- nlohmann_json for platform: $abi installed to $NLOHMANN_JSON_INSTALL_PREFIX_DIR ${NC}"

            REPORT_FILE="${NLOHMANN_JSON_INSTALL_PREFIX_DIR}/build_report_${abi}.txt"
            echo "nlohmann_json Build Report" > "$REPORT_FILE"
            echo "========================================================"     >> "$REPORT_FILE"
            echo "Date: $(date)"                                                >> "$REPORT_FILE"
            echo "Platform: $abi"                                               >> "$REPORT_FILE"
            echo "nlohmann_json Version (Git Tag/Branch): $NLOHMANN_JSON_VERSION_TAG"         >> "$REPORT_FILE"
            if [ -d "$NLOHMANN_JSON_SOURCE_DIR/.git" ]; then
                GIT_COMMIT_HASH=$(cd "$NLOHMANN_JSON_SOURCE_DIR" && git rev-parse --short HEAD)
                echo "nlohmann_json Git Commit: $GIT_COMMIT_HASH"                      >> "$REPORT_FILE"
            fi
            echo "Build Configuration: Release (via CMake)"                     >> "$REPORT_FILE"
            if [ "$abi" = "android" ]; then
                echo "NDK Path: $ANDROID_NDK_HOME"                              >> "$REPORT_FILE"
                echo "NDK Version (fom source.properties): $NDK_VERSION_STRING" >> "$REPORT_FILE"
                echo "CLANG_CXX_COMPILER: $CLANG_COMPILER_PATH"                 >> "$REPORT_FILE"
                echo "CLANG_C_COMPILER: $CLANG_C_COMPILER_PATH"                 >> "$REPORT_FILE"
                echo "Clang Version: $CLANG_VERSION_STRING"                     >> "$REPORT_FILE"
            else
                echo "HOST_GCC_PATH: $HOST_GCC_PATH"                            >> "$REPORT_FILE"
                echo "HOST_GXX_PATH: $HOST_GXX_PATH"                            >> "$REPORT_FILE"
                echo "HOST_GCC_VERSION: $HOST_GCC_VERSION"                      >> "$REPORT_FILE"
                echo "HOST_CLANG_PATH: $HOST_CLANG_PATH"                        >> "$REPORT_FILE"
                echo "HOST_CLANGXX_PATH: $HOST_CLANGXX_PATH"                    >> "$REPORT_FILE"
                echo "HOST_CLANG_VERSION: $HOST_CLANG_VERSION"                  >> "$REPORT_FILE"
            fi
            echo ""                                                             >> "$REPORT_FILE"
            echo "CMake Arguments Used: "                                       >> "$REPORT_FILE"
            printf "    %s\n" "${CMAKE_ARGS[@]}"                                >> "$REPORT_FILE"
            echo ""                                                             >> "$REPORT_FILE"
            echo -e "${GREEN}Build Report Generated: ${REPORT_FILE}${NC}"    
        fi
    fi
    cd "${SCRIPT_BASE_DIR}"
}

echo -e "${GREEN}Target platform set to: ${CYAN}$TARGET_PLATFORM${NC}"
if [ "$TARGET_PLATFORM" == "linux" ]; then
    echo -e "${YELLOW}Build target is linux. Only 'linux-x86_64' will be built.${NC}"
    build_nlohmann_json_for_platform "linux-x86_64"
elif [ "$TARGET_PLATFORM" == "android" ]; then
    echo -e "${YELLOW}Build target is android. All Android ABIS and 'linux-x86_64' will be built.${NC}"
    build_nlohmann_json_for_platform "arm64-v8a"    "21" ""
    build_nlohmann_json_for_platform "armeabi-v7a"  "19" ""
    build_nlohmann_json_for_platform "x86_64"       "21" ""
    build_nlohmann_json_for_platform "x86"          "19" ""
    build__for_platform "linux-x86_64" 
else 
    echo -e "${BRED}Error: Unsupported target platform: '$TARGET_PLATFORM'.${NC}"
    print_usage
    exit 1
fi

echo ""
echo -e "${YELLOW}===========================================================${NC}"
echo -e "${YELLOW}nlohmann_json has been installed: ${NLOHMANN_JSON_INSTALL_BASE_DIR}${NC}"
ls -1 "$NLOHMANN_JSON_INSTALL_BASE_DIR"
echo -e "${YELLOW}Now you can use find_package(nlohmann_json) in cmake.${NC}"
echo -e "${YELLOW}===========================================================${NC}"


