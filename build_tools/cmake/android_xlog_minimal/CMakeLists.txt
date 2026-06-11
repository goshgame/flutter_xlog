cmake_minimum_required(VERSION 3.6)

project(mars_xlog_android_minimal)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}" CACHE PATH "Installation directory" FORCE)
message(STATUS "CMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}")

set(MARS_ROOT "" CACHE PATH "Absolute path to mars source root")
if(NOT MARS_ROOT)
  message(FATAL_ERROR "MARS_ROOT is required")
endif()

include_directories("${MARS_ROOT}/openssl/include")

add_subdirectory("${MARS_ROOT}/comm" comm)
add_subdirectory("${MARS_ROOT}/boost" boost)
add_subdirectory("${MARS_ROOT}/xlog" xlog)

option(ZSTD_BUILD_STATIC "BUILD STATIC LIBRARIES" ON)
option(ZSTD_BUILD_SHARED "BUILD SHARED LIBRARIES" OFF)
set(ZSTD_SOURCE_DIR "${MARS_ROOT}/zstd")
set(LIBRARY_DIR ${ZSTD_SOURCE_DIR}/lib)
include(GNUInstallDirs)
add_subdirectory("${MARS_ROOT}/zstd/build/cmake/lib" zstd)

include("${MARS_ROOT}/comm/utils.cmake")

include_directories("${MARS_ROOT}")
include_directories("${MARS_ROOT}/..")

find_library(log-lib log)
find_library(z-lib z)

file(GLOB SELF_SRC_FILES
  "${MARS_ROOT}/libraries/mars_android_sdk/jni/JNI_OnLoad.cc"
  "${MARS_ROOT}/libraries/mars_xlog_sdk/jni/import.cc"
)

add_library(marsxlog SHARED ${SELF_SRC_FILES})
install(TARGETS marsxlog LIBRARY DESTINATION . ARCHIVE DESTINATION .)

get_filename_component(EXPORT_XLOG_EXP_FILE "${MARS_ROOT}/libraries/mars_android_sdk/jni/export.exp" ABSOLUTE)
set(SELF_XLOG_LINKER_FLAG "-Wl,--gc-sections -Wl,--version-script='${EXPORT_XLOG_EXP_FILE}' -Wl,--undefined-version")
if(ANDROID_ABI STREQUAL "x86_64" OR ANDROID_ABI STREQUAL "x86")
  set(SELF_XLOG_LINKER_FLAG "-Wl,--gc-sections -Wl,--version-script='${EXPORT_XLOG_EXP_FILE}' -Wl,--undefined-version -Wl,--no-warn-shared-textrel")
endif()

target_link_libraries(marsxlog
  "${SELF_XLOG_LINKER_FLAG}"
  xlog
  mars-boost
  comm
  libzstd_static
  ${log-lib}
  ${z-lib}
)
