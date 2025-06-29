include_guard(GLOBAL)

include(PrettySymbols)

# 彩色输出 
option(USE_CMAKE_COLORED_MESSAGES   "Enable colored messages in CMake output for this project" ON)
option(USE_CPP_COLORED_DEBUG_OUTPUT "Enable colored messages in Debug output for this project" ON)
option(ENABLE_EXTERNAL_FMT          "Enable external {fmt} (even though std fmt is available)" ON)
option(MESSAGE_PADDED               "Enable padded to align prefixes for pretty message"       ON)

set(_PRETTY_MESSAGE_MAX_LENGTH 105 CACHE STRING "Max message length for pretty_message"                         FORCE)
set(BANNER_WIDTH               80  CACHE STRING "Banner width affecting all pretty_message with banner or title" FORCE)
set(PRETTY_KV_ALIGN_COLUMN     40  CACHE STRING "The column where values start in pretty_message"               FORCE)

# 使用 string(ASCII <n>) 生成字符以解决 “/0” 无效转义序列问题
string(ASCII 27 ESC) # ESC: 
                     #   ASCII Code: 27
                     #   HEX:        0x1B
                     #   OCT:        033
                     
# --- ANSI 颜色代码定义 ----
if (USE_CMAKE_COLORED_MESSAGES AND (NOT WIN32 OR CMAKE_GENERATOR STREQUAL "Ninja" OR CMAKE_COLOR_MAKEFILE))
    set(C_RESET     "${ESC}[0m" )
    set(C_BLACK     "${ESC}[30m")
    set(C_RED       "${ESC}[31m")
    set(C_GREEN     "${ESC}[32m")
    set(C_YELLOW    "${ESC}[33m")
    set(C_BLUE      "${ESC}[34m")
    set(C_MAGENTA   "${ESC}[35m")
    set(C_CYAN      "${ESC}[36m")
    set(C_WHITE     "${ESC}[37m")

    # 粗体/高亮 Bold/Bright
    set(C_B_BLACK   "${ESC}[1;30m")
    set(C_B_RED     "${ESC}[1;31m")
    set(C_B_GREEN   "${ESC}[1;32m")
    set(C_B_YELLOW  "${ESC}[1;33m")
    set(C_B_BLUE    "${ESC}[1;34m")
    set(C_B_MAGENTA "${ESC}[1;35m")
    set(C_B_CYAN    "${ESC}[1;36m")
    set(C_B_WHITE   "${ESC}[1;37m")
else()
    # 如果环境不支持彩色输出
    set(C_RESET     "")
    set(C_BLACK     "")
    set(C_RED       "")
    set(C_GREEN     "")
    set(C_YELLOW    "")
    set(C_BLUE      "")
    set(C_MAGENTA   "")
    set(C_CYAN      "")
    set(C_WHITE     "")

    set(C_B_BLACK   "")
    set(C_B_RED     "")
    set(C_B_GREEN   "")
    set(C_B_YELLOW  "")
    set(C_B_BLUE    "")
    set(C_B_MAGENTA "")
    set(C_B_CYAN    "")
    set(C_B_WHITE   "")
endif()


# 设置等宽前缀
function(_pretty_message_get_padded_prefix _type _output_var)
    set(_MAX_WIDTH 11)
    set(_SEPARATOR " | ")
    set(_prefix_str "[${_type}]")
    string(LENGTH "${_prefix_str}" _prefix_len)
    math(EXPR _padding_len "${_MAX_WIDTH} - ${_prefix_len}")
    if (_padding_len LESS 0) 
        set(_padding_len 0)
    endif()

    set(_SPACES "                                        ")
    string(SUBSTRING "${_SPACES}" 0 ${_padding_len} _padding_spaces)
    set(${_output_var} "${_prefix_str}${_padding_spaces}${_SEPARATOR}" PARENT_SCOPE)
endfunction()

# 重复字符串行
function(_pretty_message_create_line char length output_var)
    set(line "")
    foreach(i RANGE ${length})
        string(APPEND line "${char}")
    endforeach()
    set(${output_var} "${line}" PARENT_SCOPE)
endfunction()

# 标题行
function(_pretty_message_create_banner title char length output_var)
    set(content " ${title} ")
    string(LENGTH "${content}" content_len)

    if (${content_len} GREATER ${length})
        set(${output_var} "${content}" PARENT_SCOPE)
        return()
    endif()

    math(EXPR padding_total "${length} - ${content_len}")
    math(EXPR padding_left  "${padding_total} / 2")
    math(EXPR padding_right "${padding_tatal} - ${padding_left}")

    _pretty_message_create_line("${char}" ${padding_left}  left_str)
    _pretty_message_create_line("${char}" ${padding_right} right_str)

    set(banner "${left_str}${content}${right_str}")
    set(${output_var} "${banner}" PARENT_SCOPE)
endfunction()

# 输出项目构建配置中的变量
# 用法: pretty_message_kv(<TYPE> <变量名> <变量值>) 
function(pretty_message_kv TYPE KEY VALUE)
    set(key_part "  ${SYM_POINT_R} ${KEY}")

    string(LENGTH "${key_part}" key_len)

    math(EXPR padding_len "${PRETTY_KV_ALIGN_COLUMN} - ${key_len}")

    if (padding_len LESS 0)
        set(padding_len 1)
    endif()

    set(_SPACES "                                                                  ")
    string(SUBSTRING "${_SPACES}" 0 ${padding_len} padding_spaces)

    set(aligned_message "${key_part}:${padding_spaces}${VALUE}")

    pretty_message(${TYPE} "${aligned_message}")
endfunction()



# --- 自定义消息函数 ---
# 1. 简单消息输出
# 用法: pretty_message(<TYPE> "消息内容...")
# Defined Type:
#   STATUS      (蓝色粗体) -  常规状态, 比默认 message(STATUS) 更醒目
#   INFO        (青色)    -  提供参考信息
#   VINFO       (黄色)    -  CMake中的变量信息
#   SUCCESS     (绿色粗体) -  操作成功
#   WARNING     (黄色粗体) -  警告
#   ERROR       (红色粗体) -  非致命错误 (使用message(SEND_ERROR))
#   FATAL_ERROR (红色粗体) -  致命错误 (使用message(FATAL_ERROR))
#   DEBUG       (洋红色)   -  调试信息 (仅在 CMAKE_BUILD_TYPE 为 Debug 时输出)
#   IMPORTANT   (洋红粗体)  - 重要提示
#   DEFAULT     (无颜色)   -  使用 message(STATUS) 默认行为
# 2. 输出固定长度标题（标题居中）
# 用法: pretty_message(<TYPE>_BANNER <标题内容> <填充内容> <标题行长度>)
# 3. 输出固定长度分割线
# 用法: pretty_message(<TYPE>_LINE <分割线内容> <分割线长度>)
function(pretty_message TYPE MESSAGE)
    # ARGN 用来获取除 TYPE 和 MESSAGE 外的所有参数
    string(REGEX MATCH "(.+)_LINE$" _match_base_type ${TYPE})
    if (_match_base_type)
        set(BASE_TYPE ${CMAKE_MATCH_1})
        set(char "${MESSAGE}")
        list(GET ARGN 0 length)

        _pretty_message_create_line("${char}" ${length} line_str)
        pretty_message(${BASE_TYPE} "${line_str}")
        return()
    endif()
    
    string(REGEX MATCH "(.+)_BANNER$" _match_base_type ${TYPE})
    if (_match_base_type)
        set(BASE_TYPE ${CMAKE_MATCH_1})
        SET(title "${MESSAGE}")
        list(GET ARGN 0 char)
        list(GET ARGN 1 length)

        _pretty_message_create_banner("${title}" "${char}" ${length} banner_str)
        pretty_message(${BASE_TYPE} "${banner_str}")
        return()
    endif()

    if (${TYPE} STREQUAL "DEFAULT")
        message(STATUS "${MESSAGE}")
        return()
    endif()

    set(PREFIX "")
    set(COLOR  "")
    set(MSG_CMD "STATUS")

    if (MESSAGE_PADDED)
        if (${TYPE} STREQUAL "OPTIONAL")
            _pretty_message_get_padded_prefix("WARNING" PREFIX)
        else()
            _pretty_message_get_padded_prefix(${TYPE}   PREFIX)
        endif()
    else()
        if (${TYPE} STREQUAL "OPTIONAL")
            set(PREFIX "[WARNING]  | ")
        else()
            set(PREFIX "[${TYPE}]  | ")
        endif()
    endif()

        if (${TYPE} STREQUAL "STATUS")
            set(COLOR   "${C_B_BLUE}")
        elseif (${TYPE} STREQUAL "INFO")
            set(COLOR   "${C_CYAN}")
        elseif (${TYPE} STREQUAL "VINFO")
            set(COLOR   "${C_YELLOW}")
        elseif (${TYPE} STREQUAL "SUCCESS")
            set(COLOR   "${C_B_GREEN}")
        elseif (${TYPE} STREQUAL "OPTIONAL")
            set(COLOR   "${C_YELLOW}")
        elseif (${TYPE} STREQUAL "TIP")
            set(COLOR   "${C_MAGENTA}")
        elseif (${TYPE} STREQUAL "WARNING")
            set(COLOR   "${C_B_YELLOW}")
            set(MSG_CMD "WARNING")
        elseif (${TYPE} STREQUAL "ERROR")
            set(COLOR   "${C_B_RED}")
            set(MSG_CMD "SEND_ERROR")
        elseif (${TYPE} STREQUAL "FATAL_ERROR")
            set(COLOR   "${C_B_RED}")
            set(MSG_CMD "FATAL_ERROR")
        elseif (${TYPE} STREQUAL "IMPORTANT")
            set(COLOR   "${C_B_MAGENTA}")
        elseif (${TYPE} STREQUAL "DEBUG")
            string(TOLOWER "${CMAKE_BUILD_TYPE}" _build_type_lower)
            if (NOT (_build_type_lower STREQUAL "debug" OR _build_type_lower STREQUAL "debug_mode"))
                return()
            endif()
            set(COLOR   "${C_MAGENTA}")
        else () # 没有定义的输出类型
            set(COLOR   "")
        endif()

        string(LENGTH "${MESSAGE}" _total_len)
        set(_current_pos 0)

        if (_total_len EQUAL 0)
            set(_total_len 1)
        endif()

        while (_current_pos LESS _total_len)
            math(EXPR _len_remaining "${_total_len} - ${_current_pos}")

            if (_len_remaining GREATER _PRETTY_MESSAGE_MAX_LENGTH)
                set(_chunk_len ${_PRETTY_MESSAGE_MAX_LENGTH})
            else()
                set(_chunk_len ${_len_remaining})
            endif()

            string(SUBSTRING "${MESSAGE}" ${_current_pos} ${_chunk_len} _current_line_message)

            if (USE_CMAKE_COLORED_MESSAGES)
                message(${MSG_CMD} "${COLOR}${PREFIX}${_current_line_message}${C_RESET}")
            else()
                message(${MSG_CMD} "${PREFIX}${_current_line_message}")
            endif()

            math(EXPR _current_pos "${_current_pos} + ${_chunk_len}")
        endwhile()
endfunction()

if (CMAKE_CXX_STANDARD GREATER_EQUAL 20)
    include(CheckCXXSourceCompiles)
    set(STD_FORMAT_TEST
    "
    #include <format>
    #include <string>
    #if !defined(__cpp_lib_format) || __cpp_lib_format < 201907L
    #endif

    int main() {
        std::string s = std::format(\"Hello, {}!\", \"world\");
        (void)s;
        return 0;
    }
    "
    )
    # Store them in case of 'check_cxx_source_compiles's side effect 
    set(CMAKE_REQUIRED_FLAGS_     ${CMAKE_REQUIRED_FLAGS})
    set(CMAKE_REQUIRED_LIBRARIES_ ${CMAKE_REQUIRED_LIBRARIES})

    check_cxx_source_compiles("${STD_FORMAT_TEST}" _HAS_STD_FORMAT)

    # Restore
    set(CMAKE_REQUIRED_FLAGS      ${CMAKE_REQUIRED_FLAGS_})
    set(CMAKE_REQUIRED_LIBRARIES  ${CMAKE_REQUIRED_LIBRARIES_})

    if (_HAS_STD_FORMAT)    # Enable cpp std format 
        set(HAVE_STD_FORMAT ON CACHE INTERNAL "std::format is avaible")
    else() 
        set(HAVE_STD_FORMAT OFF CACHE INTERNAL "std::format is unavaible")
    endif()
endif()


if (HAVE_STD_FORMAT)
    if (ENABLE_EXTERNAL_FMT)
        add_compile_definitions(USE_EXTERNAL_FMT=1)
    else()
        add_compile_definitions(USE_STD_FMT=1)
    endif()
else()
    add_compile_definitions(USE_EXTERNAL_FMT=1)
endif()

if (USE_CPP_COLORED_DEBUG_OUTPUT)
    add_compile_definitions(USE_CPP_COLORED_DEBUG_OUTPUT=1)
endif()


# Debug
function(print_pretty_debug_info)
    pretty_message(DEBUG "PrettyPrint.cmake module loaded.")
    pretty_message(VINFO_BANNER "Pretty Message Info" "=" ${BANNER_WIDTH})
    pretty_message_kv(VINFO "USE_CMAKE_COLORED_MESSAGES"      "${USE_CMAKE_COLORED_MESSAGES} ")
    pretty_message_kv(VINFO "USE_CPP_COLORED_DEBUG_OUTPUT"    "${USE_CPP_COLORED_DEBUG_OUTPUT} ")
    pretty_message_kv(VINFO "ENABLE_EXTERNAL_FMT"             "${ENABLE_EXTERNAL_FMT}")
    pretty_message_kv(VINFO "PRETTY_MESSAGE_MAX_LENGTH"       "${_PRETTY_MESSAGE_MAX_LENGTH}")
    pretty_message_kv(VINFO "BANNER_WIDTH"                    "${BANNER_WIDTH}")    
    pretty_message_kv(VINFO "PRETTY_KV_ALIGN_COLUMN"          "${PRETTY_KV_ALIGN_COLUMN}")
    pretty_message_kv(VINFO "PRETTY_PRINT_USE_ASCII_FALLBACK" "${PRETTY_PRINT_USE_ASCII_FALLBACK}")
    if (NOT ENABLE_EXTERNAL_FMT)
    pretty_message(VINFO "  HAVE_STD_FORMAT:                ${HAVE_STD_FORMAT}")
    endif()
    pretty_message(VINFO_LINE "=" ${BANNER_WIDTH})
endfunction()