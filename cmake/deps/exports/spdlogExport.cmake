include_guard(GLOBAL)

set(SPDLOG_POSSIBLE_PATHS
    "${DEPENDENCY_ROOT_DIR}/spdlog/spdlog_linux-x86_64"
    "${DEPENDENCY_ROOT_DIR}/spdlog/build"
    "${DEPENDENCY_ROOT_DIR}/spdlog/install"
    "${DEPENDENCY_ROOT_DIR}/spdlog"
)

foreach(path ${SPDLOG_POSSIBLE_PATHS})
    set(config_path "${path}/spdlog/lib/cmake/spdlog")
    if (EXISTS "${config_path}/spdlogConfig.cmake")
        pretty_message_kv(SUCCESS "Found spdlog config at" "${config_path}")
        list(APPEND CMAKE_PREFIX_PATH ${path})
        find_package(spdlog QUIET CONFIG PATHS ${path} NO_DEFAULT_PATH)
        if (spdlog_FOUND)
            pretty_message_kv(SUCCESS "spdlog loaded from" "${path}")
            pretty_message_kv(SUCCESS "spdlog version" "${spdlog_VERSION}")
            break()
        endif()
    endif()
endforeach()

if (NOT spdlog_FOUND)
    pretty_message(OPTIONAL "spdlog not found in local paths")
endif()

