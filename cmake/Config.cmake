cmake_minimum_required(VERSION 3.16)

list(APPEND CMAKE_MODULE_PATH
    "${CMAKE_CURRENT_LIST_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/core"
    "${CMAKE_CURRENT_LIST_DIR}/deps"
    "${CMAKE_CURRENT_LIST_DIR}/misc"
)

# 交叉编译
# include(mingw-w64-toolchain)

include(PrettyPrint)

# core
include(ProjectVerbose)
include(ProjectInfo)
include(PCH)

# deps
include(DependencyManager)

# misc
include(ModuleInfo)

include(QtInfo)



