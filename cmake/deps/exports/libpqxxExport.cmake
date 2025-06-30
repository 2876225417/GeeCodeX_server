include_guard(GLOBAL)

set(LIBPQXX_POSSIBLE_PATHS
    "${DEPENDENCY_ROOT_DIR}/libpqxx/libpqxx_linux"
    "${DEPENDENCY_ROOT_DIR}/libpqxx/build"
    "${DEPENDENCY_ROOT_DIR}/libpqxx/install"
    "${DEPENDENCY_ROOT_DIR}/libpqxx"
)

foreach(path ${LIBPQXX_POSSIBLE_PATHS})
    set(config_path "${path}/libpqxx/lib/cmake/libpqxx")
    if (EXISTS "${config_path}/libpqxx-config.cmake")
        pretty_message_kv(SUCCESS "Found libpqxx config at" "${config_path}")
        list(APPEND CMAKE_PREFIX_PATH ${path})
        find_package(libpqxx QUIET CONFIG PATHS ${path} NO_DEFAULT_PATH)
        if (libpqxx_FOUND)
            pretty_message_kv(SUCCESS "libpqxx loaded from" "${path}")
            pretty_message_kv(SUCCESS "libpqxx version" "${libpqxx_VERSION}")
            break()
        endif()
    endif()
endforeach()

if (NOT libpqxx_FOUND)
    pretty_message(OPTIONAL "libpqxx not found in local paths")
endif()

