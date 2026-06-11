#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"
FORMATTER_PATCH_CONFIG="${SCRIPT_DIR}/mars_formatter_patch.conf"
FORMATTER_PATCHER="${SCRIPT_DIR}/patch_mars_formatter.py"
ANDROID_XLOG_CMAKE_DIR="${SCRIPT_DIR}/cmake/android_xlog_minimal"
ANDROID_BRIDGE_CMAKE_DIR="${SCRIPT_DIR}/cmake/android_bridge"
MARS_SOURCE_DIR="${PLUGIN_DIR}/build_tools/.cache/mars"
MARS_ROOT="${MARS_SOURCE_DIR}/mars"
MARS_GIT_URL="${MARS_GIT_URL:-https://github.com/Tencent/mars.git}"
MARS_GIT_REF="${MARS_GIT_REF:-}"
IOS_BRIDGE_LIB_NAME="libflutter_xlog_bridge.a"
IOS_DYNAMIC_FRAMEWORK_NAME="flutter_xlog.framework"
IOS_DYNAMIC_XCFRAMEWORK_NAME="flutter_xlog.xcframework"

BUILD_ANDROID=1
BUILD_IOS=1
CLEAN_BEFORE_BUILD=0
SYNC_LOCAL_MODE="auto"
ANDROID_SDK_DIR=""
NDK_ROOT_PATH=""
NDK_SHIM_PATH=""
ANDROID_ARCHS=("armeabi-v7a" "arm64-v8a")
ANDROID_16K_REQUIRED_ARCHS=("arm64-v8a")
ANDROID_PAGE_SIZE_CMAKE_ARGS=()
ANDROID_16K_PAGE_SIZE=16384
ANDROID_16K_LINKER_FLAGS="-Wl,-z,max-page-size=16384"
ANDROID_NDK_16K_DEFAULT_MAJOR=28
ANDROID_NDK_FLEXIBLE_PAGE_MAJOR=27

android_abi_to_target_triple() {
  case "$1" in
    arm64-v8a)
      echo "aarch64-linux-android"
      ;;
    armeabi-v7a)
      echo "arm-linux-androideabi"
      ;;
    x86)
      echo "i686-linux-android"
      ;;
    x86_64)
      echo "x86_64-linux-android"
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_android_shared_stl_path() {
  local ndk_root="$1"
  local abi="$2"
  local llvm_prebuilt_root="${ndk_root}/toolchains/llvm/prebuilt"
  local host_tag
  host_tag="$(find "${llvm_prebuilt_root}" -mindepth 1 -maxdepth 1 -type d | head -n 1 | xargs basename)"
  if [[ -z "${host_tag}" ]]; then
    return 1
  fi

  local triple
  triple="$(android_abi_to_target_triple "${abi}")" || return 1
  echo "${llvm_prebuilt_root}/${host_tag}/sysroot/usr/lib/${triple}/libc++_shared.so"
}

ensure_android_runtime_outputs() {
  local libs_root="$1"
  local abi

  for abi in "${ANDROID_ARCHS[@]}"; do
    if [[ ! -f "${libs_root}/${abi}/libmarsxlog.so" ]]; then
      echo "Android 构建失败: 缺少 ABI 产物 ${libs_root}/${abi}/libmarsxlog.so"
      exit 1
    fi

    if [[ ! -f "${libs_root}/${abi}/libc++_shared.so" ]]; then
      echo "Android 构建失败: 缺少 ABI 运行时 ${libs_root}/${abi}/libc++_shared.so"
      exit 1
    fi
  done
}

ensure_android_bridge_outputs() {
  local libs_root="$1"
  local abi

  for abi in "${ANDROID_ARCHS[@]}"; do
    if [[ ! -f "${libs_root}/${abi}/libflutter_xlog.so" ]]; then
      echo "Android 构建失败: 缺少 ABI bridge 产物 ${libs_root}/${abi}/libflutter_xlog.so"
      exit 1
    fi
  done
}

resolve_android_llvm_prebuilt_root() {
  local ndk_root="$1"
  local llvm_prebuilt_root="${ndk_root}/toolchains/llvm/prebuilt"
  local host_tag
  host_tag="$(find "${llvm_prebuilt_root}" -mindepth 1 -maxdepth 1 -type d | head -n 1 | xargs basename)"
  if [[ -z "${host_tag}" ]]; then
    return 1
  fi

  echo "${llvm_prebuilt_root}/${host_tag}"
}

resolve_android_strip_cmd() {
  local ndk_root="$1"
  local llvm_prebuilt_root
  llvm_prebuilt_root="$(resolve_android_llvm_prebuilt_root "${ndk_root}")" || return 1
  echo "${llvm_prebuilt_root}/bin/llvm-strip"
}

resolve_android_readelf_cmd() {
  local ndk_root="$1"
  local llvm_prebuilt_root
  llvm_prebuilt_root="$(resolve_android_llvm_prebuilt_root "${ndk_root}")" || return 1
  echo "${llvm_prebuilt_root}/bin/llvm-readelf"
}

usage() {
  cat <<'EOF'
用法:
  bash package/flutter_xlog/build_tools/build_mars_xlog.sh [选项]

选项:
  --android       仅构建 Android xlog
  --ios           仅构建 iOS xlog
  --all           构建 Android + iOS（默认）
  --clean         构建前清理 mars 构建产物目录
  --sync-local    强制将本次构建产物同步到 flutter_xlog 的本地默认目录
  --no-sync-local 仅构建，不同步本地产物
  -h, --help      显示帮助

说明:
  1) Mars 源码缓存目录:
     package/flutter_xlog/build_tools/.cache/mars
  2) Android 原始输出目录:
     build_tools/.cache/mars/mars/libraries/mars_xlog_sdk/libs/<abi>/{libmarsxlog.so,libflutter_xlog.so,libc++_shared.so}
  3) iOS 原始输出目录:
     build_tools/.cache/mars/mars/cmake_build/iOS/iOS.out/flutter_xlog.xcframework
  4) 默认会把 xcframework / so 同步回 flutter_xlog 目录，作为 FFI 可直接使用的本地产物
     Android 会同步 libmarsxlog.so / libflutter_xlog.so / libc++_shared.so，冲突由应用层 Gradle 处理
  5) 若本地没有 Mars 源码，脚本会自动下载；源码缓存目录默认已被 git ignore
EOF
}

log() {
  echo "[flutter_xlog] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1"
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --android)
        BUILD_ANDROID=1
        BUILD_IOS=0
        ;;
      --ios)
        BUILD_ANDROID=0
        BUILD_IOS=1
        ;;
      --all)
        BUILD_ANDROID=1
        BUILD_IOS=1
        ;;
      --clean)
        CLEAN_BEFORE_BUILD=1
        ;;
      --sync-local)
        SYNC_LOCAL_MODE="always"
        ;;
      --no-sync-local)
        SYNC_LOCAL_MODE="never"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "未知参数: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

ensure_mars_source() {
  if [[ -d "${MARS_ROOT}" ]]; then
    return 0
  fi

  require_cmd git

  mkdir -p "$(dirname "${MARS_SOURCE_DIR}")"
  rm -rf "${MARS_SOURCE_DIR}"

  log "未检测到 Mars 源码，开始下载到 ${MARS_SOURCE_DIR} ..."
  if [[ -n "${MARS_GIT_REF}" ]]; then
    git clone --depth 1 --branch "${MARS_GIT_REF}" "${MARS_GIT_URL}" "${MARS_SOURCE_DIR}"
  else
    git clone --depth 1 "${MARS_GIT_URL}" "${MARS_SOURCE_DIR}"
  fi
}

patch_mars_time_formatter() {
  local formatter_file="${MARS_ROOT}/xlog/src/formater.cc"
  if [[ ! -f "${formatter_file}" ]]; then
    echo "未找到 Mars formatter 源码: ${formatter_file}"
    exit 1
  fi

  if [[ ! -f "${FORMATTER_PATCH_CONFIG}" ]]; then
    echo "未找到 formatter patch 配置: ${FORMATTER_PATCH_CONFIG}"
    exit 1
  fi

  if [[ ! -f "${FORMATTER_PATCHER}" ]]; then
    echo "未找到 formatter patch 脚本: ${FORMATTER_PATCHER}"
    exit 1
  fi

  log "应用 Mars formatter 时区补丁..."
  python3 "${FORMATTER_PATCHER}" \
    --formatter "${formatter_file}" \
    --config "${FORMATTER_PATCH_CONFIG}"
}

patch_mars_android_warning_flags() {
  local flags_file="${MARS_ROOT}/comm/CMakeExtraFlags.txt"
  if [[ ! -f "${flags_file}" ]]; then
    echo "未找到 Mars Android 编译参数文件: ${flags_file}"
    exit 1
  fi

  log "应用 Mars Android Clang 兼容补丁..."
  python3 - "${flags_file}" <<'PY'
from pathlib import Path
import sys

flags_path = Path(sys.argv[1])
source = flags_path.read_text()
needle = "-Wno-error=tautological-type-limit-compare"
extra_flags = f"{needle} -Wno-error=deprecated-builtins -Wno-error=deprecated-declarations"

if extra_flags in source:
    raise SystemExit(0)

if needle not in source:
    raise SystemExit(f"未找到可插入的编译参数锚点: {flags_path}")

flags_path.write_text(source.replace(needle, extra_flags, 1))
PY
}

prepare() {
  require_cmd python3
  ensure_mars_source
  patch_mars_time_formatter
  patch_mars_android_warning_flags
}

read_android_sdk_from_local_properties() {
  local local_properties="${REPO_ROOT}/android/local.properties"
  if [[ ! -f "${local_properties}" ]]; then
    return 1
  fi

  local sdk_line
  sdk_line="$(grep '^sdk.dir=' "${local_properties}" | head -n 1 || true)"
  if [[ -z "${sdk_line}" ]]; then
    return 1
  fi

  local sdk_path="${sdk_line#sdk.dir=}"
  sdk_path="${sdk_path//\\\\/\\/}"
  echo "${sdk_path%/}"
  return 0
}

read_ndk_source_property() {
  local ndk_root="$1"
  local key="$2"
  local source_properties="${ndk_root}/source.properties"

  if [[ ! -f "${source_properties}" ]]; then
    return 1
  fi

  local line
  line="$(grep "^${key} *= *" "${source_properties}" | head -n 1 || true)"
  if [[ -z "${line}" ]]; then
    return 1
  fi

  line="${line#*=}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  echo "${line}"
}

read_ndk_major_version() {
  local ndk_root="$1"
  local release_name
  release_name="$(read_ndk_source_property "${ndk_root}" "Pkg.ReleaseName" || true)"
  if [[ "${release_name}" =~ ^r([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  local revision
  revision="$(read_ndk_source_property "${ndk_root}" "Pkg.Revision" || true)"
  if [[ "${revision}" =~ ^([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  local dir_name
  dir_name="$(basename "${ndk_root}")"
  if [[ "${dir_name}" =~ ^([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

is_ndk_prerelease() {
  local ndk_root="$1"
  local descriptor
  descriptor="$(
    printf '%s %s' \
      "$(read_ndk_source_property "${ndk_root}" "Pkg.ReleaseName" || true)" \
      "$(read_ndk_source_property "${ndk_root}" "Pkg.Revision" || true)"
  )"
  descriptor="$(printf '%s' "${descriptor}" | tr '[:upper:]' '[:lower:]')"

  [[ "${descriptor}" == *alpha* || "${descriptor}" == *beta* || "${descriptor}" == *preview* || "${descriptor}" == *rc* ]]
}

configure_android_page_size_cmake_args() {
  local ndk_root="$1"
  local ndk_major
  ndk_major="$(read_ndk_major_version "${ndk_root}" || true)"

  ANDROID_PAGE_SIZE_CMAKE_ARGS=("-DCMAKE_SHARED_LINKER_FLAGS=${ANDROID_16K_LINKER_FLAGS}")

  if [[ -n "${ndk_major}" && "${ndk_major}" -ge "${ANDROID_NDK_FLEXIBLE_PAGE_MAJOR}" ]]; then
    ANDROID_PAGE_SIZE_CMAKE_ARGS+=("-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
  fi
}

resolve_ndk_root() {
  if [[ -n "${NDK_ROOT:-}" && -f "${NDK_ROOT}/source.properties" ]]; then
    NDK_ROOT_PATH="${NDK_ROOT}"
    return 0
  fi

  for candidate in "${ANDROID_NDK_ROOT:-}" "${ANDROID_NDK_HOME:-}"; do
    if [[ -n "${candidate}" && -f "${candidate}/source.properties" ]]; then
      NDK_ROOT_PATH="${candidate}"
      return 0
    fi
  done

  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    ANDROID_SDK_DIR="${ANDROID_SDK_ROOT%/}"
  elif [[ -n "${ANDROID_HOME:-}" ]]; then
    ANDROID_SDK_DIR="${ANDROID_HOME%/}"
  else
    ANDROID_SDK_DIR="$(read_android_sdk_from_local_properties || true)"
  fi

  if [[ -z "${ANDROID_SDK_DIR}" ]]; then
    return 1
  fi

  local ndk_dir="${ANDROID_SDK_DIR}/ndk"
  if [[ ! -d "${ndk_dir}" ]]; then
    return 1
  fi

  local selected_ndk
  local ndk_candidates
  ndk_candidates="$(
    find "${ndk_dir}" -mindepth 1 -maxdepth 1 -type d \
      | while read -r dir; do
          if [[ -f "${dir}/source.properties" ]]; then
            basename "${dir}"
          fi
        done \
      | sort -V
  )"

  while read -r candidate; do
    [[ -z "${candidate}" ]] && continue
    local candidate_root="${ndk_dir}/${candidate}"
    local candidate_major
    candidate_major="$(read_ndk_major_version "${candidate_root}" || true)"
    if [[ -z "${candidate_major}" || "${candidate_major}" -lt "${ANDROID_NDK_16K_DEFAULT_MAJOR}" ]]; then
      continue
    fi
    if is_ndk_prerelease "${candidate_root}"; then
      continue
    fi
    selected_ndk="${candidate}"
  done <<< "${ndk_candidates}"

  if [[ -z "${selected_ndk}" ]]; then
    while read -r candidate; do
      [[ -z "${candidate}" ]] && continue
      local candidate_root="${ndk_dir}/${candidate}"
      local candidate_major
      candidate_major="$(read_ndk_major_version "${candidate_root}" || true)"
      if [[ -z "${candidate_major}" || "${candidate_major}" -lt "${ANDROID_NDK_16K_DEFAULT_MAJOR}" ]]; then
        continue
      fi
      selected_ndk="${candidate}"
    done <<< "${ndk_candidates}"
  fi

  if [[ -z "${selected_ndk}" ]]; then
    while read -r candidate; do
      [[ -z "${candidate}" ]] && continue
      local candidate_root="${ndk_dir}/${candidate}"
      if is_ndk_prerelease "${candidate_root}"; then
        continue
      fi
      selected_ndk="${candidate}"
    done <<< "${ndk_candidates}"
  fi

  if [[ -z "${selected_ndk}" ]]; then
    selected_ndk="$(echo "${ndk_candidates}" | tail -n 1)"
  fi

  if [[ -z "${selected_ndk}" ]]; then
    return 1
  fi

  NDK_ROOT_PATH="${ndk_dir}/${selected_ndk}"
  return 0
}

ensure_cmake_available() {
  if command -v cmake >/dev/null 2>&1; then
    return 0
  fi

  local sdk_dir="${ANDROID_SDK_DIR}"
  if [[ -z "${sdk_dir}" ]]; then
    if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
      sdk_dir="${ANDROID_SDK_ROOT%/}"
    elif [[ -n "${ANDROID_HOME:-}" ]]; then
      sdk_dir="${ANDROID_HOME%/}"
    elif [[ -n "${NDK_ROOT_PATH}" ]]; then
      sdk_dir="$(cd "${NDK_ROOT_PATH}/../.." && pwd)"
    fi
  fi

  if [[ -z "${sdk_dir}" ]]; then
    return 1
  fi

  local cmake_root="${sdk_dir}/cmake"
  if [[ ! -d "${cmake_root}" ]]; then
    return 1
  fi

  local cmake_version
  cmake_version="$(
    find "${cmake_root}" -mindepth 1 -maxdepth 1 -type d \
      | while read -r dir; do
          if [[ -x "${dir}/bin/cmake" ]]; then
            basename "${dir}"
          fi
        done \
      | sort -V \
      | tail -n 1
  )"

  if [[ -z "${cmake_version}" ]]; then
    return 1
  fi

  export PATH="${cmake_root}/${cmake_version}/bin:${PATH}"
  command -v cmake >/dev/null 2>&1
}

prepare_mars_android_ndk_compat() {
  local ndk_root="$1"
  local llvm_prebuilt_root="${ndk_root}/toolchains/llvm/prebuilt"
  if [[ ! -d "${llvm_prebuilt_root}" ]]; then
    echo "无法找到 NDK llvm 工具链目录: ${llvm_prebuilt_root}"
    return 1
  fi

  local host_tag
  host_tag="$(find "${llvm_prebuilt_root}" -mindepth 1 -maxdepth 1 -type d | head -n 1 | xargs basename)"
  if [[ -z "${host_tag}" ]]; then
    echo "无法识别 NDK host tag: ${llvm_prebuilt_root}"
    return 1
  fi

  local llvm_strip="${llvm_prebuilt_root}/${host_tag}/bin/llvm-strip"
  if [[ ! -f "${llvm_strip}" ]]; then
    echo "未找到 llvm-strip: ${llvm_strip}"
    return 1
  fi

  local strip_targets=(
    "${ndk_root}/toolchains/arm-linux-androideabi-4.9/prebuilt/${host_tag}/bin/arm-linux-androideabi-strip"
    "${ndk_root}/toolchains/aarch64-linux-android-4.9/prebuilt/${host_tag}/bin/aarch64-linux-android-strip"
    "${ndk_root}/toolchains/x86-4.9/prebuilt/${host_tag}/bin/i686-linux-android-strip"
    "${ndk_root}/toolchains/x86_64-4.9/prebuilt/${host_tag}/bin/x86_64-linux-android-strip"
  )

  local strip_target
  for strip_target in "${strip_targets[@]}"; do
    mkdir -p "$(dirname "${strip_target}")"
    if [[ ! -e "${strip_target}" ]]; then
      ln -s "${llvm_strip}" "${strip_target}"
    fi
  done

  local stl_root="${ndk_root}/sources/cxx-stl/llvm-libc++/libs"
  local abi src dst
  for abi in "${ANDROID_ARCHS[@]}" x86 x86_64; do
    src="$(resolve_android_shared_stl_path "${ndk_root}" "${abi}" || true)"
    dst="${stl_root}/${abi}/libc++_shared.so"
    if [[ -n "${src}" && -f "${src}" ]]; then
      mkdir -p "$(dirname "${dst}")"
      if [[ ! -e "${dst}" ]]; then
        ln -s "${src}" "${dst}"
      fi
    fi
  done
}

create_ndk_shim() {
  local real_ndk_root="$1"
  local shim_root="${PLUGIN_DIR}/.ndk_shim/$(basename "${real_ndk_root}")"

  rm -rf "${shim_root}"
  mkdir -p "${shim_root}"

  local entry name
  for entry in "${real_ndk_root}"/*; do
    name="$(basename "${entry}")"
    case "${name}" in
      toolchains|sources)
        ;;
      *)
        ln -s "${entry}" "${shim_root}/${name}"
        ;;
    esac
  done

  mkdir -p "${shim_root}/toolchains"
  if [[ -d "${real_ndk_root}/toolchains/llvm" ]]; then
    ln -s "${real_ndk_root}/toolchains/llvm" "${shim_root}/toolchains/llvm"
  fi

  mkdir -p "${shim_root}/sources/cxx-stl"
  echo "${shim_root}"
}

copy_android_shared_stl() {
  local ndk_root="$1"
  local libs_root="$2"
  local abi src dst
  for abi in "${ANDROID_ARCHS[@]}"; do
    src="$(resolve_android_shared_stl_path "${ndk_root}" "${abi}" || true)"
    dst="${libs_root}/${abi}/libc++_shared.so"
    if [[ -z "${src}" || ! -f "${src}" ]]; then
      echo "Android 构建失败: 未找到 ABI=${abi} 的 libc++_shared.so"
      return 1
    fi
    if [[ ! -d "${libs_root}/${abi}" ]]; then
      echo "Android 构建失败: 未找到 ABI 输出目录 ${libs_root}/${abi}"
      return 1
    fi
    cp -f "${src}" "${dst}"
  done
}

ensure_android_so_16k_alignment() {
  local readelf_cmd="$1"
  local so_path="$2"
  local so_name
  so_name="$(basename "${so_path}")"

  if [[ ! -x "${readelf_cmd}" ]]; then
    echo "Android 构建失败: 未找到 llvm-readelf ${readelf_cmd}"
    exit 1
  fi

  local align
  local has_load_segment=0
  while read -r align; do
    [[ -z "${align}" ]] && continue
    has_load_segment=1
    local align_hex="${align#0x}"
    if (( 16#${align_hex} < ANDROID_16K_PAGE_SIZE )); then
      echo "Android 构建失败: ${so_name} 的 LOAD 段对齐为 ${align}，未达到 16KB 要求"
      echo "请优先使用 NDK r28+ 重新构建，并确认宿主 APK/AAB 也满足 16KB 打包要求。"
      exit 1
    fi
  done < <("${readelf_cmd}" -l "${so_path}" | awk '$1 == "LOAD" { print $NF }')

  if [[ "${has_load_segment}" -eq 0 ]]; then
    echo "Android 构建失败: 无法从 ${so_path} 解析 LOAD 段信息"
    exit 1
  fi
}

ensure_android_runtime_16k_alignment() {
  local ndk_root="$1"
  local libs_root="$2"
  local readelf_cmd
  readelf_cmd="$(resolve_android_readelf_cmd "${ndk_root}")" || {
    echo "Android 构建失败: 未找到 llvm-readelf"
    exit 1
  }

  local abi
  local so_name
  for abi in "${ANDROID_16K_REQUIRED_ARCHS[@]}"; do
    for so_name in libmarsxlog.so libflutter_xlog.so libc++_shared.so; do
      ensure_android_so_16k_alignment "${readelf_cmd}" "${libs_root}/${abi}/${so_name}"
    done
  done
}

copy_android_xlog_binary() {
  local build_dir="$1"
  local abi="$2"
  local libs_root="$3"
  local symbols_root="$4"
  local strip_cmd="$5"
  local built_lib="${build_dir}/libmarsxlog.so"
  local stripped_output="${libs_root}/${abi}/libmarsxlog.so"
  local symbol_output="${symbols_root}/${abi}/libmarsxlog.so"

  if [[ ! -f "${built_lib}" ]]; then
    echo "Android 构建失败: 未找到 ABI=${abi} 的 libmarsxlog.so，期望路径 ${built_lib}"
    exit 1
  fi

  mkdir -p "${libs_root}/${abi}" "${symbols_root}/${abi}"
  cp -f "${built_lib}" "${symbol_output}"
  cp -f "${built_lib}" "${stripped_output}"
  "${strip_cmd}" "${stripped_output}"
}

copy_android_bridge_binary() {
  local build_dir="$1"
  local abi="$2"
  local libs_root="$3"
  local symbols_root="$4"
  local strip_cmd="$5"
  local built_lib="${build_dir}/libflutter_xlog.so"
  local stripped_output="${libs_root}/${abi}/libflutter_xlog.so"
  local symbol_output="${symbols_root}/${abi}/libflutter_xlog.so"

  if [[ ! -f "${built_lib}" ]]; then
    echo "Android 构建失败: 未找到 ABI=${abi} 的 libflutter_xlog.so，期望路径 ${built_lib}"
    exit 1
  fi

  mkdir -p "${libs_root}/${abi}" "${symbols_root}/${abi}"
  cp -f "${built_lib}" "${symbol_output}"
  cp -f "${built_lib}" "${stripped_output}"
  "${strip_cmd}" "${stripped_output}"
}

build_android_xlog_for_abi() {
  local abi="$1"
  local build_dir="${MARS_ROOT}/cmake_build/AndroidXlog/${abi}"

  rm -rf "${build_dir}"
  mkdir -p "${build_dir}"

  cmake -S "${ANDROID_XLOG_CMAKE_DIR}" -B "${build_dir}" \
    -DMARS_ROOT="${MARS_ROOT}" \
    -DANDROID_ABI="${abi}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${NDK_SHIM_PATH}/build/cmake/android.toolchain.cmake" \
    -DANDROID_TOOLCHAIN=clang \
    -DANDROID_NDK="${NDK_SHIM_PATH}" \
    -DANDROID_PLATFORM=android-21 \
    -DANDROID_STL="c++_shared" \
    "${ANDROID_PAGE_SIZE_CMAKE_ARGS[@]}" \
    -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="${build_dir}"

  cmake --build "${build_dir}" --target libzstd_static marsxlog --config Release -- -j8
}

build_android_bridge_for_abi() {
  local abi="$1"
  local sync_token="$2"
  local bridge_state_root="$3"
  local build_dir="${MARS_ROOT}/cmake_build/AndroidBridge/${abi}"
  local mars_lib_path="${MARS_ROOT}/libraries/mars_xlog_sdk/libs/${abi}/libmarsxlog.so"

  rm -rf "${build_dir}"
  mkdir -p "${build_dir}"

  if [[ ! -f "${mars_lib_path}" ]]; then
    echo "Android bridge 构建失败: 未找到 ABI=${abi} 的 mars 动态库 ${mars_lib_path}"
    exit 1
  fi

  write_build_state_header "${bridge_state_root}/include" "android" "${sync_token}_${abi}"

  cmake -S "${ANDROID_BRIDGE_CMAKE_DIR}" -B "${build_dir}" \
    -DPLUGIN_DIR="${PLUGIN_DIR}" \
    -DMARS_ROOT="${MARS_ROOT}" \
    -DMARS_LIB_PATH="${mars_lib_path}" \
    -DBRIDGE_STATE_ROOT="${bridge_state_root}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="${NDK_SHIM_PATH}/build/cmake/android.toolchain.cmake" \
    -DANDROID_TOOLCHAIN=clang \
    -DANDROID_NDK="${NDK_SHIM_PATH}" \
    -DANDROID_PLATFORM=android-21 \
    -DANDROID_ABI="${abi}" \
    -DANDROID_STL="c++_shared" \
    "${ANDROID_PAGE_SIZE_CMAKE_ARGS[@]}" \
    -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="${build_dir}"

  cmake --build "${build_dir}" --target flutter_xlog --config Release -- -j8
}

write_build_state_header() {
  local target_dir="$1"
  local platform_label="$2"
  local sync_token="$3"

  mkdir -p "${target_dir}"
  cat > "${target_dir}/flutter_xlog_build_state.h" <<EOF
#ifndef FLUTTER_XLOG_BUILD_STATE_H_
#define FLUTTER_XLOG_BUILD_STATE_H_

// 每次脚本同步产物后都会更新该 token，强制 native bridge 重新编译，
// 避免 __has_include 条件变化后继续复用旧的 stub 对象文件。
#define FLUTTER_XLOG_BUILD_PLATFORM "${platform_label}"
#define FLUTTER_XLOG_BUILD_SYNC_TOKEN "${sync_token}"

#endif  // FLUTTER_XLOG_BUILD_STATE_H_
EOF
}

prepare_bridge_build_state_root() {
  local platform_label="$1"
  local sync_token="$2"
  local state_root="${MARS_ROOT}/cmake_build/flutter_xlog_bridge_state/${platform_label}"

  rm -rf "${state_root}"
  mkdir -p "${state_root}/include"
  write_build_state_header "${state_root}/include" "${platform_label}" "${sync_token}"
  echo "${state_root}"
}

validate_synced_artifacts() {
  local ios_framework_target="${PLUGIN_DIR}/ios/Frameworks/${IOS_DYNAMIC_XCFRAMEWORK_NAME}"
  local abi

  if [[ "${BUILD_ANDROID}" -eq 1 ]]; then
    for abi in "${ANDROID_ARCHS[@]}"; do
      if [[ ! -f "${PLUGIN_DIR}/android/src/main/jniLibs/${abi}/libmarsxlog.so" ]]; then
        echo "同步失败: Android 目标产物缺失 ${PLUGIN_DIR}/android/src/main/jniLibs/${abi}/libmarsxlog.so"
        exit 1
      fi
      if [[ ! -f "${PLUGIN_DIR}/android/src/main/jniLibs/${abi}/libflutter_xlog.so" ]]; then
        echo "同步失败: Android 目标 bridge 缺失 ${PLUGIN_DIR}/android/src/main/jniLibs/${abi}/libflutter_xlog.so"
        exit 1
      fi
      if [[ ! -f "${PLUGIN_DIR}/android/src/main/jniLibs/${abi}/libc++_shared.so" ]]; then
        echo "同步失败: Android 目标运行时缺失 ${PLUGIN_DIR}/android/src/main/jniLibs/${abi}/libc++_shared.so"
        exit 1
      fi
    done
  fi

  if [[ "${BUILD_IOS}" -eq 1 ]]; then
    if [[ ! -f "${PLUGIN_DIR}/ios/Classes/xlog_bridge.h" ]]; then
      echo "同步失败: iOS 公开头文件缺失 ${PLUGIN_DIR}/ios/Classes/xlog_bridge.h"
      exit 1
    fi

    if [[ ! -d "${ios_framework_target}" ]]; then
      echo "同步失败: iOS xcframework 缺失 ${ios_framework_target}"
      exit 1
    fi

    if [[ ! -f "${ios_framework_target}/Info.plist" ]]; then
      echo "同步失败: iOS xcframework 元数据缺失 ${ios_framework_target}/Info.plist"
      exit 1
    fi

    if [[ ! -d "${ios_framework_target}/ios-arm64/${IOS_DYNAMIC_FRAMEWORK_NAME}" ]]; then
      echo "同步失败: iOS 真机 framework 缺失 ${ios_framework_target}/ios-arm64/${IOS_DYNAMIC_FRAMEWORK_NAME}"
      exit 1
    fi

    if [[ ! -f "${ios_framework_target}/ios-arm64/${IOS_DYNAMIC_FRAMEWORK_NAME}/flutter_xlog" ]]; then
      echo "同步失败: iOS 真机二进制缺失 ${ios_framework_target}/ios-arm64/${IOS_DYNAMIC_FRAMEWORK_NAME}/flutter_xlog"
      exit 1
    fi

    if [[ ! -d "${ios_framework_target}/ios-arm64_x86_64-simulator/${IOS_DYNAMIC_FRAMEWORK_NAME}" ]]; then
      echo "同步失败: iOS 模拟器 framework 缺失 ${ios_framework_target}/ios-arm64_x86_64-simulator/${IOS_DYNAMIC_FRAMEWORK_NAME}"
      exit 1
    fi

    if [[ ! -f "${ios_framework_target}/ios-arm64_x86_64-simulator/${IOS_DYNAMIC_FRAMEWORK_NAME}/flutter_xlog" ]]; then
      echo "同步失败: iOS 模拟器二进制缺失 ${ios_framework_target}/ios-arm64_x86_64-simulator/${IOS_DYNAMIC_FRAMEWORK_NAME}/flutter_xlog"
      exit 1
    fi

    if [[ ! -f "${ios_framework_target}/ios-arm64/${IOS_DYNAMIC_FRAMEWORK_NAME}/Headers/xlog_bridge.h" ]]; then
      echo "同步失败: iOS 真机头文件缺失 ${ios_framework_target}/ios-arm64/${IOS_DYNAMIC_FRAMEWORK_NAME}/Headers/xlog_bridge.h"
      exit 1
    fi

    if [[ ! -f "${ios_framework_target}/ios-arm64_x86_64-simulator/${IOS_DYNAMIC_FRAMEWORK_NAME}/Headers/xlog_bridge.h" ]]; then
      echo "同步失败: iOS 模拟器头文件缺失 ${ios_framework_target}/ios-arm64_x86_64-simulator/${IOS_DYNAMIC_FRAMEWORK_NAME}/Headers/xlog_bridge.h"
      exit 1
    fi
  fi
}

clean_build_outputs() {
  log "清理构建目录..."
  rm -rf "${MARS_ROOT}/cmake_build"
  rm -rf "${MARS_ROOT}/libraries/mars_xlog_sdk"
}

build_android_xlog() {
  if ! resolve_ndk_root; then
    echo "未能自动找到 Android NDK。"
    echo "请设置 NDK_ROOT 或 ANDROID_NDK_HOME 后重试。"
    exit 1
  fi

  log "使用 NDK: ${NDK_ROOT_PATH}"
  local ndk_major
  ndk_major="$(read_ndk_major_version "${NDK_ROOT_PATH}" || true)"
  if [[ -n "${ndk_major}" ]]; then
    log "NDK major: r${ndk_major}"
  fi
  NDK_SHIM_PATH="$(create_ndk_shim "${NDK_ROOT_PATH}")"
  log "使用 NDK shim: ${NDK_SHIM_PATH}"
  export NDK_ROOT="${NDK_SHIM_PATH}"
  if ! ensure_cmake_available; then
    echo "未找到可用 cmake，请安装 cmake 或通过 Android SDK Manager 安装 CMake。"
    exit 1
  fi
  prepare_mars_android_ndk_compat "${NDK_SHIM_PATH}" || {
    echo "准备 NDK 兼容路径失败，请检查 NDK 安装。"
    exit 1
  }
  configure_android_page_size_cmake_args "${NDK_ROOT_PATH}"
  if [[ "${#ANDROID_PAGE_SIZE_CMAKE_ARGS[@]}" -gt 0 ]]; then
    log "启用 Android 16KB page size 构建参数: ${ANDROID_PAGE_SIZE_CMAKE_ARGS[*]}"
  else
    log "当前 NDK 默认产出 16KB 对齐 so，无需额外 page size 参数"
  fi

  if [[ ! -f "${ANDROID_XLOG_CMAKE_DIR}/CMakeLists.txt" ]]; then
    echo "未找到 Android xlog 最小化 CMake 入口: ${ANDROID_XLOG_CMAKE_DIR}/CMakeLists.txt"
    exit 1
  fi
  if [[ ! -f "${ANDROID_BRIDGE_CMAKE_DIR}/CMakeLists.txt" ]]; then
    echo "未找到 Android bridge CMake 入口: ${ANDROID_BRIDGE_CMAKE_DIR}/CMakeLists.txt"
    exit 1
  fi

  log "开始构建 Android xlog..."
  local output_dir="${MARS_ROOT}/libraries/mars_xlog_sdk/libs"
  local symbol_dir="${MARS_ROOT}/libraries/mars_xlog_sdk/obj/local"
  local bridge_state_root
  local sync_token
  local strip_cmd
  local abi

  strip_cmd="$(resolve_android_strip_cmd "${NDK_SHIM_PATH}")" || {
    echo "Android 构建失败: 未找到 llvm-strip"
    exit 1
  }
  sync_token="$(date -u +%Y%m%dT%H%M%SZ)_$$"
  bridge_state_root="$(prepare_bridge_build_state_root "android" "${sync_token}")"

  rm -rf "${output_dir}" "${symbol_dir}"

  for abi in "${ANDROID_ARCHS[@]}"; do
    build_android_xlog_for_abi "${abi}"
    copy_android_xlog_binary "${MARS_ROOT}/cmake_build/AndroidXlog/${abi}" "${abi}" "${output_dir}" "${symbol_dir}" "${strip_cmd}"
  done

  if [[ ! -d "${output_dir}" ]]; then
    echo "Android 构建失败: 未找到输出目录 ${output_dir}"
    exit 1
  fi

  copy_android_shared_stl "${NDK_SHIM_PATH}" "${output_dir}" || {
    echo "Android 构建失败: 补充 libc++_shared.so 失败"
    exit 1
  }
  copy_android_shared_stl "${NDK_SHIM_PATH}" "${symbol_dir}" || {
    echo "Android 构建失败: 补充 symbols 目录的 libc++_shared.so 失败"
    exit 1
  }
  ensure_android_runtime_outputs "${output_dir}"

  for abi in "${ANDROID_ARCHS[@]}"; do
    build_android_bridge_for_abi "${abi}" "${sync_token}" "${bridge_state_root}"
    copy_android_bridge_binary "${MARS_ROOT}/cmake_build/AndroidBridge/${abi}" "${abi}" "${output_dir}" "${symbol_dir}" "${strip_cmd}"
  done
  ensure_android_bridge_outputs "${output_dir}"
  ensure_android_runtime_16k_alignment "${NDK_SHIM_PATH}" "${output_dir}"

  log "Android 构建完成: ${output_dir}"
}

build_ios_xlog() {
  log "开始构建 iOS xlog..."
  (
    cd "${MARS_ROOT}"
    python3 - <<'PY'
import os
import shutil
import build_ios as builder
from mars_utils import XLOG_COPY_HEADER_FILES
from mars_utils import clean
from mars_utils import copy_file_mapping
from mars_utils import gen_mars_revision_file
from mars_utils import libtool_libs
from mars_utils import lipo_libs

SCRIPT_PATH = builder.SCRIPT_PATH
BUILD_OUT_PATH = builder.BUILD_OUT_PATH
INSTALL_PATH = builder.INSTALL_PATH
ARTIFACT_ROOT = "cmake_build/iOSArtifacts"
COMMON_BUILD_ARGS = "-DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=../../ios.toolchain.cmake -DENABLE_ARC=0 -DENABLE_BITCODE=0 -DENABLE_VISIBILITY=1"
LIBTOOL_SOURCE_LIBS = [
    os.path.join(INSTALL_PATH, "libcomm.a"),
    os.path.join(INSTALL_PATH, "libmars-boost.a"),
    os.path.join(INSTALL_PATH, "libxlog.a"),
    os.path.join(BUILD_OUT_PATH, "zstd/libzstd.a"),
]


def abs_path(relative_path: str) -> str:
    return os.path.join(SCRIPT_PATH, relative_path)


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def clean_artifact_root() -> None:
    artifact_root = abs_path(ARTIFACT_ROOT)
    if os.path.isdir(artifact_root):
        shutil.rmtree(artifact_root)
    os.makedirs(artifact_root, exist_ok=True)


def build_platform(platform: str, output_relative_path: str, headers_relative_path: str) -> str:
    clean(BUILD_OUT_PATH)
    os.chdir(abs_path(BUILD_OUT_PATH))
    build_cmd = f"cmake ../.. {COMMON_BUILD_ARGS} -DPLATFORM={platform} && make -j8 && make install"
    ret = os.system(build_cmd)
    os.chdir(SCRIPT_PATH)
    if ret != 0:
        raise SystemExit(f"!!!!!!!!!!!build {platform} fail!!!!!!!!!!!!!!!")

    output_path = abs_path(output_relative_path)
    headers_path = abs_path(headers_relative_path)
    ensure_dir(os.path.dirname(output_path))
    ensure_dir(headers_path)

    if not libtool_libs([abs_path(path) for path in LIBTOOL_SOURCE_LIBS], output_path):
        raise SystemExit(1)

    copy_file_mapping(XLOG_COPY_HEADER_FILES, "../", headers_path)
    return output_path


gen_mars_revision_file("comm", "")
clean_artifact_root()

os_lib = build_platform("OS64", "cmake_build/iOSArtifacts/ios-arm64/libmars.a", "cmake_build/iOSArtifacts/ios-arm64/Headers")
sim_x86_lib = build_platform(
    "SIMULATOR64",
    "cmake_build/iOSArtifacts/simulator-x86_64/libmars.a",
    "cmake_build/iOSArtifacts/ios-arm64_x86_64-simulator/Headers",
)
sim_arm64_lib = build_platform(
    "SIMULATORARM64",
    "cmake_build/iOSArtifacts/simulator-arm64/libmars.a",
    "cmake_build/iOSArtifacts/ios-arm64_x86_64-simulator/Headers",
)
sim_lib = abs_path("cmake_build/iOSArtifacts/ios-arm64_x86_64-simulator/libmars.a")

if not lipo_libs([sim_x86_lib, sim_arm64_lib], sim_lib):
    raise SystemExit(1)
PY
  )

  local output_root="${MARS_ROOT}/cmake_build/iOSArtifacts"
  local os_lib="${output_root}/ios-arm64/libmars.a"
  local sim_lib="${output_root}/ios-arm64_x86_64-simulator/libmars.a"

  if [[ ! -f "${os_lib}" || ! -f "${sim_lib}" ]]; then
    echo "iOS 构建失败: 缺少动态 framework 链接所需的 Mars 静态库中间产物"
    exit 1
  fi
  log "iOS Mars 静态库中间产物构建完成: ${output_root}"
}

build_ios_bridge_object() {
  local sdk="$1"
  local arch="$2"
  local min_version_flag="$3"
  local output_obj="$4"
  local bridge_state_root="$5"
  local sync_token="$6"
  local sysroot

  sysroot="$(xcrun --sdk "${sdk}" --show-sdk-path)"
  write_build_state_header "${bridge_state_root}/include" "ios" "${sync_token}_${sdk}_${arch}"

  xcrun --sdk "${sdk}" clang++ \
    -arch "${arch}" \
    -isysroot "${sysroot}" \
    "${min_version_flag}=12.0" \
    -std=c++17 \
    -stdlib=libc++ \
    -DFLUTTER_XLOG_HAS_MARS=1 \
    -I"${PLUGIN_DIR}/ios/Classes" \
    -I"${bridge_state_root}" \
    -I"${MARS_ROOT}" \
    -I"${MARS_ROOT}/.." \
    -c "${PLUGIN_DIR}/ios/Classes/xlog_bridge.mm" \
    -o "${output_obj}"
}

create_ios_dynamic_framework_bundle() {
  local framework_dir="$1"
  local binary_path="$2"
  local bundle_identifier="$3"
  local platform_name="$4"

  rm -rf "${framework_dir}"
  mkdir -p "${framework_dir}/Headers" "${framework_dir}/Modules"
  cp -f "${binary_path}" "${framework_dir}/flutter_xlog"
  cp -f "${PLUGIN_DIR}/ios/Classes/xlog_bridge.h" "${framework_dir}/Headers/xlog_bridge.h"

  cat > "${framework_dir}/Modules/module.modulemap" <<'EOF'
framework module flutter_xlog {
  umbrella header "xlog_bridge.h"
  export *
  module * { export * }
}
EOF

  cat > "${framework_dir}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>flutter_xlog</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_identifier}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>flutter_xlog</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>${platform_name}</string>
  </array>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>MinimumOSVersion</key>
  <string>12.0</string>
</dict>
</plist>
EOF
}

link_ios_dynamic_framework_binary() {
  local sdk="$1"
  local arch="$2"
  local min_version_flag="$3"
  local output_binary="$4"
  local bridge_obj="$5"
  local mars_lib="$6"
  local sysroot

  sysroot="$(xcrun --sdk "${sdk}" --show-sdk-path)"
  xcrun --sdk "${sdk}" clang++ \
    -dynamiclib \
    -arch "${arch}" \
    -isysroot "${sysroot}" \
    "${min_version_flag}=12.0" \
    -stdlib=libc++ \
    -install_name "@rpath/${IOS_DYNAMIC_FRAMEWORK_NAME}/flutter_xlog" \
    -framework Foundation \
    -framework SystemConfiguration \
    -framework Security \
    -ObjC \
    "${bridge_obj}" \
    "${mars_lib}" \
    -lz \
    -lc++ \
    -o "${output_binary}"
}

build_ios_bridge() {
  local framework_output_dir="${MARS_ROOT}/cmake_build/iOS/iOS.out"
  local bridge_build_dir="${MARS_ROOT}/cmake_build/iOSDynamicFramework"
  local bridge_state_root
  local sync_token
  local mars_artifact_root="${MARS_ROOT}/cmake_build/iOSArtifacts"
  local os_mars_lib="${mars_artifact_root}/ios-arm64/libmars.a"
  local sim_mars_lib="${mars_artifact_root}/ios-arm64_x86_64-simulator/libmars.a"
  local os_obj="${bridge_build_dir}/iphoneos/arm64/xlog_bridge.o"
  local sim_x86_obj="${bridge_build_dir}/iphonesimulator/x86_64/xlog_bridge.o"
  local sim_arm64_obj="${bridge_build_dir}/iphonesimulator/arm64/xlog_bridge.o"
  local os_binary="${bridge_build_dir}/iphoneos/arm64/flutter_xlog"
  local sim_x86_binary="${bridge_build_dir}/iphonesimulator/x86_64/flutter_xlog"
  local sim_arm64_binary="${bridge_build_dir}/iphonesimulator/arm64/flutter_xlog"
  local sim_binary="${bridge_build_dir}/iphonesimulator/flutter_xlog"
  local os_framework="${bridge_build_dir}/iphoneos/${IOS_DYNAMIC_FRAMEWORK_NAME}"
  local sim_framework="${bridge_build_dir}/iphonesimulator/${IOS_DYNAMIC_FRAMEWORK_NAME}"
  local xcframework_output="${framework_output_dir}/${IOS_DYNAMIC_XCFRAMEWORK_NAME}"

  require_cmd xcrun
  require_cmd lipo
  require_cmd xcodebuild

  sync_token="$(date -u +%Y%m%dT%H%M%SZ)_$$"
  bridge_state_root="$(prepare_bridge_build_state_root "ios" "${sync_token}")"

  rm -rf "${bridge_build_dir}"
  mkdir -p "$(dirname "${os_obj}")" "$(dirname "${sim_x86_obj}")" "$(dirname "${sim_arm64_obj}")"

  if [[ ! -f "${os_mars_lib}" || ! -f "${sim_mars_lib}" ]]; then
    echo "iOS 动态 framework 构建失败: 缺少 Mars 静态库中间产物"
    exit 1
  fi

  build_ios_bridge_object "iphoneos" "arm64" "-miphoneos-version-min" "${os_obj}" "${bridge_state_root}" "${sync_token}"
  link_ios_dynamic_framework_binary "iphoneos" "arm64" "-miphoneos-version-min" "${os_binary}" "${os_obj}" "${os_mars_lib}"

  build_ios_bridge_object "iphonesimulator" "x86_64" "-mios-simulator-version-min" "${sim_x86_obj}" "${bridge_state_root}" "${sync_token}"
  link_ios_dynamic_framework_binary "iphonesimulator" "x86_64" "-mios-simulator-version-min" "${sim_x86_binary}" "${sim_x86_obj}" "${sim_mars_lib}"

  build_ios_bridge_object "iphonesimulator" "arm64" "-mios-simulator-version-min" "${sim_arm64_obj}" "${bridge_state_root}" "${sync_token}"
  link_ios_dynamic_framework_binary "iphonesimulator" "arm64" "-mios-simulator-version-min" "${sim_arm64_binary}" "${sim_arm64_obj}" "${sim_mars_lib}"

  lipo -create "${sim_x86_binary}" "${sim_arm64_binary}" -output "${sim_binary}"

  create_ios_dynamic_framework_bundle "${os_framework}" "${os_binary}" "com.gosh.flutter_xlog.iphoneos" "iPhoneOS"
  create_ios_dynamic_framework_bundle "${sim_framework}" "${sim_binary}" "com.gosh.flutter_xlog.iphonesimulator" "iPhoneSimulator"

  mkdir -p "${framework_output_dir}"
  rm -rf "${xcframework_output}"
  xcodebuild -create-xcframework \
    -framework "${os_framework}" \
    -framework "${sim_framework}" \
    -output "${xcframework_output}" >/dev/null

  if [[ ! -d "${xcframework_output}" ]]; then
    echo "iOS 动态 framework 构建失败: 未生成 ${xcframework_output}"
    exit 1
  fi

  log "iOS 动态 framework 构建完成: ${xcframework_output}"
}

sync_local_artifacts() {
  local android_source="${MARS_ROOT}/libraries/mars_xlog_sdk/libs"
  local android_target="${PLUGIN_DIR}/android/src/main/jniLibs"
  local ios_source="${MARS_ROOT}/cmake_build/iOS/iOS.out/${IOS_DYNAMIC_XCFRAMEWORK_NAME}"
  local ios_target="${PLUGIN_DIR}/ios/Frameworks/${IOS_DYNAMIC_XCFRAMEWORK_NAME}"

  if [[ "${BUILD_ANDROID}" -eq 1 && -d "${android_source}" ]]; then
    log "同步 Android 产物到插件目录..."
    for abi in "${ANDROID_ARCHS[@]}"; do
      if [[ -f "${android_source}/${abi}/libmarsxlog.so" ]]; then
        if [[ ! -f "${android_source}/${abi}/libflutter_xlog.so" ]]; then
          echo "同步失败: Android 源产物缺少 ${android_source}/${abi}/libflutter_xlog.so"
          exit 1
        fi
        if [[ ! -f "${android_source}/${abi}/libc++_shared.so" ]]; then
          echo "同步失败: Android 源产物缺少 ${android_source}/${abi}/libc++_shared.so"
          exit 1
        fi
        mkdir -p "${android_target}/${abi}"
        cp -f "${android_source}/${abi}/libmarsxlog.so" "${android_target}/${abi}/libmarsxlog.so"
        cp -f "${android_source}/${abi}/libflutter_xlog.so" "${android_target}/${abi}/libflutter_xlog.so"
        cp -f "${android_source}/${abi}/libc++_shared.so" "${android_target}/${abi}/libc++_shared.so"
      fi
    done
  fi

  if [[ "${BUILD_IOS}" -eq 1 && -d "${ios_source}" ]]; then
    log "同步 iOS xcframework 到插件目录..."
    rm -rf "${PLUGIN_DIR}/ios/Frameworks/mars.framework" \
      "${PLUGIN_DIR}/ios/Frameworks/libmars.a" \
      "${PLUGIN_DIR}/ios/Frameworks/mars.xcframework" \
      "${PLUGIN_DIR}/ios/Frameworks/libflutter_xlog_bridge.xcframework" \
      "${ios_target}"
    rm -f "${PLUGIN_DIR}/ios/Frameworks/${IOS_BRIDGE_LIB_NAME}"
    cp -R "${ios_source}" "${ios_target}"
  fi

  validate_synced_artifacts
}

main() {
  parse_args "$@"
  prepare

  if [[ "${CLEAN_BEFORE_BUILD}" -eq 1 ]]; then
    clean_build_outputs
  fi

  if [[ "${BUILD_ANDROID}" -eq 1 ]]; then
    build_android_xlog
  fi

  if [[ "${BUILD_IOS}" -eq 1 ]]; then
    build_ios_xlog
    build_ios_bridge
  fi

  if [[ "${SYNC_LOCAL_MODE}" != "never" ]]; then
    sync_local_artifacts
  fi

  log "全部完成。"
}

main "$@"
