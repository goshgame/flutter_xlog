# 本地编译说明

本文档说明如何在本地重新编译 `flutter_xlog_ffi` 随包分发的 native
产物。所有命令默认从仓库根目录执行。

## 前置环境

通用依赖：

- `git`
- `python3`
- `cmake`

Android 依赖：

- Android SDK
- Android NDK，推荐 r28 或更新版本
- `ANDROID_SDK_ROOT` 或 `ANDROID_HOME` 指向 Android SDK
- 可选：`NDK_ROOT`、`ANDROID_NDK_HOME` 或 `ANDROID_NDK_ROOT` 指向指定 NDK

iOS 依赖：

- macOS
- Xcode 和 Command Line Tools
- `xcodebuild`

Android 构建会优先使用 `NDK_ROOT`，其次是 `ANDROID_NDK_ROOT` /
`ANDROID_NDK_HOME`，再从 Android SDK 的 `ndk/` 目录里自动选择可用版本。

## 常用命令

构建 Android 和 iOS，并同步到插件目录：

```bash
bash build_tools/build_mars_xlog.sh --all --sync-local
```

只构建 Android：

```bash
bash build_tools/build_mars_xlog.sh --android --sync-local
```

只构建 iOS：

```bash
bash build_tools/build_mars_xlog.sh --ios --sync-local
```

构建前清理 Mars 构建产物：

```bash
bash build_tools/build_mars_xlog.sh --all --clean --sync-local
```

只构建到缓存目录，不覆盖当前插件内置产物：

```bash
bash build_tools/build_mars_xlog.sh --all --no-sync-local
```

`build_flutter_xlog.sh` 是兼容入口，会直接转发到 `build_mars_xlog.sh`：

```bash
bash build_tools/build_flutter_xlog.sh --android --sync-local
```

## Mars 源码来源

首次运行时，脚本会自动把 Tencent mars 克隆到：

```text
build_tools/.cache/mars
```

默认地址是：

```text
https://github.com/Tencent/mars.git
```

如需指定 fork 或 tag/branch，可以设置环境变量：

```bash
MARS_GIT_URL=https://github.com/Tencent/mars.git \
MARS_GIT_REF=master \
bash build_tools/build_mars_xlog.sh --all --sync-local
```

脚本会在本地 Mars 源码上自动应用：

- xlog formatter 时区补丁
- Android Clang 兼容编译参数补丁

## Android 产物

构建 ABI：

- `armeabi-v7a`
- `arm64-v8a`

缓存目录中的原始产物：

```text
build_tools/.cache/mars/mars/libraries/mars_xlog_sdk/libs/<abi>/libmarsxlog.so
build_tools/.cache/mars/mars/libraries/mars_xlog_sdk/libs/<abi>/libflutter_xlog.so
build_tools/.cache/mars/mars/libraries/mars_xlog_sdk/libs/<abi>/libc++_shared.so
```

同步到插件后的产物：

```text
android/src/main/jniLibs/<abi>/libmarsxlog.so
android/src/main/jniLibs/<abi>/libflutter_xlog.so
android/src/main/jniLibs/<abi>/libc++_shared.so
```

脚本会校验 `arm64-v8a` 的 Android native libraries 是否满足 16 KB page
size 对齐要求。若校验失败，优先使用 NDK r28 或更新版本重新构建，并确认宿主
APK/AAB 的最终打包也满足 16 KB page size 要求。

## iOS 产物

缓存目录中的原始产物：

```text
build_tools/.cache/mars/mars/cmake_build/iOS/iOS.out/flutter_xlog.xcframework
```

同步到插件后的产物：

```text
ios/Frameworks/flutter_xlog.xcframework
ios/Classes/xlog_bridge.h
```

`flutter_xlog.xcframework` 包含：

- `ios-arm64` 真机 framework
- `ios-arm64_x86_64-simulator` 模拟器 framework

## 参数说明

```text
--android        仅构建 Android xlog
--ios            仅构建 iOS xlog
--all            构建 Android + iOS，默认行为
--clean          构建前清理 Mars 构建产物目录
--sync-local     强制同步本次构建产物到插件目录
--no-sync-local  仅构建，不同步本地产物
-h, --help       显示脚本帮助
```

## 常见问题

### 未找到 Android NDK

设置 `NDK_ROOT` 指向 NDK 根目录，例如：

```bash
export NDK_ROOT="$ANDROID_SDK_ROOT/ndk/28.0.13004108"
bash build_tools/build_mars_xlog.sh --android --sync-local
```

也可以设置 `ANDROID_SDK_ROOT` 或 `ANDROID_HOME`，让脚本从 SDK 的 `ndk/`
目录自动选择版本。

### 未找到 cmake

安装系统 `cmake`，或通过 Android SDK Manager 安装 CMake。脚本会先查找
`PATH` 里的 `cmake`，找不到时再尝试使用 Android SDK 下的 CMake。

### Android 16 KB page size 校验失败

优先换用 NDK r28 或更新版本重新构建：

```bash
export NDK_ROOT="$ANDROID_SDK_ROOT/ndk/28.0.13004108"
bash build_tools/build_mars_xlog.sh --android --clean --sync-local
```

### iOS 构建找不到 xcodebuild

确认 Xcode 和 Command Line Tools 已安装，并选择正确的 Xcode：

```bash
xcode-select -p
xcodebuild -version
```

### Mars 源码缓存异常

如果 Mars 源码缓存被中断或污染，可以删除 `build_tools/.cache/mars` 后重新运行
构建脚本。该目录是本地缓存，不应提交到 git。

## 发布前检查

重新编译并同步 native 产物后，建议至少执行：

```bash
dart analyze
dart pub publish --dry-run
```

发布前还需要在真实 Android 设备或模拟器、iOS 模拟器或设备上验证 example app。
