cmake_minimum_required(VERSION 3.16)


find_package(Boost REQUIRED)
find_package(OpenSSL REQUIRED)

add_subdirectory(http)
add_subdirectory(database)
add_subdirectory(utils)

add_executable(inf_qwq_backend main.cpp)

target_include_directories(inf_qwq_backend
    PUBLIC
)

target_link_libraries(inf_qwq_backend 
    PRIVATE 
    db
    Boost::boost
    OpenSSL::SSL
    OpenSSL::Crypto
)

