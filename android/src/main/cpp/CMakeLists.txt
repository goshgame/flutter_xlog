cmake_minimum_required(VERSION 3.18.1)
project(flutter_xlog)

if(ANDROID)
    set(CMAKE_ANDROID_STL_TYPE c++_shared)
endif()

set(MARS_LIB_LOCAL_STN_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libmarsstn.so)
set(MARS_LIB_LOCAL_XLOG_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libmarsxlog.so)
set(MARS_INCLUDE_LOCAL_PATH ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(HAS_MARS_LIB OFF)
set(MARS_LIB_PATH "")

if(EXISTS ${MARS_LIB_LOCAL_STN_PATH})
    set(MARS_LIB_PATH ${MARS_LIB_LOCAL_STN_PATH})
    set(HAS_MARS_LIB ON)
elseif(EXISTS ${MARS_LIB_LOCAL_XLOG_PATH})
    set(MARS_LIB_PATH ${MARS_LIB_LOCAL_XLOG_PATH})
    set(HAS_MARS_LIB ON)
endif()

if(HAS_MARS_LIB)
    add_library(mars SHARED IMPORTED)
    set_target_properties(mars PROPERTIES IMPORTED_LOCATION ${MARS_LIB_PATH})
endif()

add_library(flutter_xlog SHARED xlog_bridge.cpp)

target_include_directories(
    flutter_xlog
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${MARS_INCLUDE_LOCAL_PATH}
)

if(HAS_MARS_LIB)
    target_compile_definitions(flutter_xlog PRIVATE FLUTTER_XLOG_HAS_MARS=1)
    target_link_libraries(flutter_xlog c++_shared mars log)
else()
    target_compile_definitions(flutter_xlog PRIVATE FLUTTER_XLOG_HAS_MARS=0)
    target_link_libraries(flutter_xlog c++_shared log)
endif()
