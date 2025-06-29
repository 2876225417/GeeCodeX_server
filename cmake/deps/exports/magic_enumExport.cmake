include_guard(GLOBAL)

set(MAGIC_ENUM_POSSIBLE_PATHS
    "${DEPENDENCY_ROOT_DIR}/magic_enum/magic_enum_linux-x86_64"
    "${DEPENDENCY_ROOT_DIR}/magic_enum/build"
    "${DEPENDENCY_ROOT_DIR}/magic_enum/install"
    "${DEPENDENCY_ROOT_DIR}/magic_enum"
)

foreach(path ${MAGIC_ENUM_POSSIBLE_PATHS})
    set(config_path "${path}/magic_enum/share/cmake/magic_enum")
    if (EXISTS "${config_path}/magic_enumConfig.cmake")
        pretty_message_kv(SUCCESS "Found magic_enum config at" "${config_path}")
        list(APPEND CMAKE_PREFIX_PATH ${path})
        find_package(magic_enum QUIET CONFIG PATHS ${path} NO_DEFAULT_PATH)
        if (magic_enum_FOUND)
            pretty_message_kv(SUCCESS "magic_enum loaded from" "${path}")
            pretty_message_kv(SUCCESS "magic_enum version" "${magic_enum_VERSION}")
            break()
        endif()
    endif()
endforeach()

if (NOT magic_enum_FOUND)
    pretty_message(OPTIONAL "magic_enum not found in local paths")
endif()

