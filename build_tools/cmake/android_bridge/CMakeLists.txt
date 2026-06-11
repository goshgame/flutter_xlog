cmake_minimum_required(VERSION 3.18.1)

project(flutter_xlog_android_bridge)

set(PLUGIN_DIR "" CACHE PATH "Absolute path to flutter_xlog plugin root")
if(NOT PLUGIN_DIR)
  message(FATAL_ERROR "PLUGIN_DIR is required")
endif()

set(MARS_ROOT "" CACHE PATH "Absolute path to mars source root")
if(NOT MARS_ROOT)
  message(FATAL_ERROR "MARS_ROOT is required")
endif()

set(MARS_LIB_PATH "" CACHE FILEPATH "Absolute path to libmarsxlog.so")
if(NOT MARS_LIB_PATH)
  message(FATAL_ERROR "MARS_LIB_PATH is required")
endif()

set(BRIDGE_STATE_ROOT "" CACHE PATH "Absolute path to generated bridge state root")
if(NOT BRIDGE_STATE_ROOT)
  message(FATAL_ERROR "BRIDGE_STATE_ROOT is required")
endif()

find_library(log_lib log)

add_library(mars SHARED IMPORTED)
set_target_properties(mars PROPERTIES IMPORTED_LOCATION "${MARS_LIB_PATH}")

add_library(
  flutter_xlog
  SHARED
  "${PLUGIN_DIR}/android/src/main/cpp/xlog_bridge.cpp"
)

target_include_directories(
  flutter_xlog
  PRIVATE
  "${PLUGIN_DIR}/android/src/main/cpp"
  "${BRIDGE_STATE_ROOT}"
  "${MARS_ROOT}"
  "${MARS_ROOT}/.."
)

target_compile_definitions(flutter_xlog PRIVATE FLUTTER_XLOG_HAS_MARS=1)
target_link_libraries(flutter_xlog c++_shared mars ${log_lib})
