
cmake_minimum_required(VERSION 3.16)

find_package(Boost REQUIRED)

FILE(GLOB HTTP_HEADER ${CMAKE_SOURCE_DIR}/include/http/*.h)
FILE(GLOB HTTP_TEMPLATE ${CMAKE_SOURCE_DIR}/include/http/*.hpp)
FILE(GLOB HTTP_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/*.cpp)


add_library(http 
    SHARED
    ${HTTP_SOURCE}
    ${HTTP_HEADER}
    ${HTTP_TEMPLATE}
    ${CMAKE_SOURCE_DIR}/include/json.hpp
)

# target_include_directories(http 
#     PUBLIC
#     ${OpenCV_INCLUDE_DIRS}
# )

target_link_libraries(http
    PRIVATE
    Boost::boost
    spdlog::spdlog
    # ${OpenCV_LIBS}
    spdlog::spdlog
)



target_link_libraries(http PUBLIC pqxx)
