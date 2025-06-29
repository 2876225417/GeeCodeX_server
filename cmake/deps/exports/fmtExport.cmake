include_guard(GLOBAL)

set(FMT_POSSIBLE_PATHS
    "${DEPENDENCY_ROOT_DIR}/fmt/fmt_linux-x86_64"
    "${DEPENDENCY_ROOT_DIR}/fmt/build"
    "${DEPENDENCY_ROOT_DIR}/fmt/install"
    "${DEPENDENCY_ROOT_DIR}/fmt"
)

foreach(path ${FMT_POSSIBLE_PATHS})
    set(config_path "${path}/lib/cmake/fmt")
    
    if (EXISTS "${config_path}/fmt-config.cmake")
        pretty_message_kv(SUCCESS "Found fmt config at" "${config_path}")
        list(APPEND CMAKE_PREFIX_PATH ${path})
        find_package(fmt QUIET CONFIG PATHS ${path} NO_DEFAULT_PATH)
        if (fmt_FOUND)
            pretty_message_kv(SUCCESS "fmt loaded from" "${path}")
            pretty_message_kv(SUCCESS "fmt version" "${fmt_VERSION}")
            break()
        endif()
    endif()
endforeach()

if (NOT fmt_FOUND)
    pretty_message(OPTIONAL "fmt not found in local paths")
endif()

