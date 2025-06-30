include_guard(GLOBAL)

set(OPENSSL_POSSIBLE_PATHS
    "${DEPENDENCY_ROOT_DIR}/openssl/openssl_linux-x86_64"
    "${DEPENDENCY_ROOT_DIR}/openssl/build"
    "${DEPENDENCY_ROOT_DIR}/openssl/install"
    "${DEPENDENCY_ROOT_DIR}/openssl"
)


foreach(path ${OPENSSL_POSSIBLE_PATHS})
    set(config_path "${path}/lib64/cmake/OpenSSL")
    if (EXISTS "${config_path}/OpenSSLConfig.cmake")
        pretty_message_kv(SUCCESS "Found OpenSSL config at" "${config_path}")
        list(APPEND CMAKE_PREFIX_PATH ${path})
        find_package(OpenSSL QUIET CONFIG PATHS ${path} NO_DEFAULT_PATH)
        if (OpenSSL_FOUND)
            pretty_message_kv(SUCCESS "OpenSSL loaded from" "${path}")
            pretty_message_kv(SUCCESS "OpenSSL version" "${OpenSSL_VERSION}")
            break()
        endif()
    endif()
endforeach()

if (NOT OpenSSL_FOUND)
    pretty_message(OPTIONAL "openssl not found in local paths")
endif()

