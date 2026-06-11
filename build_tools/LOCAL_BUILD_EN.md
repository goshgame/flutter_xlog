# Local Build Guide

This guide explains how to rebuild the native artifacts shipped with
`flutter_xlog_ffi`. All commands are intended to run from the repository root.

## Prerequisites

Common tools:

- `git`
- `python3`
- `cmake`

Android tools:

- Android SDK
- Android NDK, r28 or newer recommended
- `ANDROID_SDK_ROOT` or `ANDROID_HOME` pointing to the Android SDK
- Optional: `NDK_ROOT`, `ANDROID_NDK_HOME`, or `ANDROID_NDK_ROOT` pointing to a
  specific NDK

iOS tools:

- macOS
- Xcode and Command Line Tools
- `xcodebuild`

The Android build first checks `NDK_ROOT`, then `ANDROID_NDK_ROOT` /
`ANDROID_NDK_HOME`, and finally auto-selects an installed NDK from the Android
SDK `ndk/` directory.

## Common Commands

Build Android and iOS, then sync artifacts back into the plugin:

```bash
bash build_tools/build_mars_xlog.sh --all --sync-local
```

Build Android only:

```bash
bash build_tools/build_mars_xlog.sh --android --sync-local
```

Build iOS only:

```bash
bash build_tools/build_mars_xlog.sh --ios --sync-local
```

Clean Mars build outputs before building:

```bash
bash build_tools/build_mars_xlog.sh --all --clean --sync-local
```

Build into the cache directory without overwriting the currently bundled plugin
artifacts:

```bash
bash build_tools/build_mars_xlog.sh --all --no-sync-local
```

`build_flutter_xlog.sh` is a compatibility entrypoint that forwards to
`build_mars_xlog.sh`:

```bash
bash build_tools/build_flutter_xlog.sh --android --sync-local
```

## Mars Source

On the first run, the script clones Tencent mars into:

```text
build_tools/.cache/mars
```

The default source URL is:

```text
https://github.com/Tencent/mars.git
```

To use a fork, tag, or branch, set environment variables:

```bash
MARS_GIT_URL=https://github.com/Tencent/mars.git \
MARS_GIT_REF=master \
bash build_tools/build_mars_xlog.sh --all --sync-local
```

The script applies local patches to the cached Mars checkout:

- xlog formatter timezone patch
- Android Clang compatibility flags

## Android Artifacts

Built ABIs:

- `armeabi-v7a`
- `arm64-v8a`

Raw cached outputs:

```text
build_tools/.cache/mars/mars/libraries/mars_xlog_sdk/libs/<abi>/libmarsxlog.so
build_tools/.cache/mars/mars/libraries/mars_xlog_sdk/libs/<abi>/libflutter_xlog.so
build_tools/.cache/mars/mars/libraries/mars_xlog_sdk/libs/<abi>/libc++_shared.so
```

Synced plugin outputs:

```text
android/src/main/jniLibs/<abi>/libmarsxlog.so
android/src/main/jniLibs/<abi>/libflutter_xlog.so
android/src/main/jniLibs/<abi>/libc++_shared.so
```

The script validates that the `arm64-v8a` Android native libraries satisfy the
16 KB page-size alignment requirement. If validation fails, rebuild with NDK r28
or newer and verify that the final host APK/AAB packaging also satisfies the
16 KB page-size requirement.

## iOS Artifacts

Raw cached output:

```text
build_tools/.cache/mars/mars/cmake_build/iOS/iOS.out/flutter_xlog.xcframework
```

Synced plugin outputs:

```text
ios/Frameworks/flutter_xlog.xcframework
ios/Classes/xlog_bridge.h
```

`flutter_xlog.xcframework` contains:

- `ios-arm64` device framework
- `ios-arm64_x86_64-simulator` simulator framework

## Options

```text
--android        Build Android xlog only
--ios            Build iOS xlog only
--all            Build Android + iOS, the default behavior
--clean          Clean Mars build outputs before building
--sync-local     Force syncing built artifacts into the plugin directory
--no-sync-local  Build only, without syncing local artifacts
-h, --help       Show script help
```

## Troubleshooting

### Android NDK Not Found

Set `NDK_ROOT` to the NDK root directory:

```bash
export NDK_ROOT="$ANDROID_SDK_ROOT/ndk/28.0.13004108"
bash build_tools/build_mars_xlog.sh --android --sync-local
```

You can also set `ANDROID_SDK_ROOT` or `ANDROID_HOME` and let the script choose
an installed NDK from the SDK `ndk/` directory.

### cmake Not Found

Install system `cmake`, or install CMake from Android SDK Manager. The script
checks `cmake` from `PATH` first, then tries the CMake installation under the
Android SDK.

### Android 16 KB Page-Size Validation Failed

Prefer rebuilding with NDK r28 or newer:

```bash
export NDK_ROOT="$ANDROID_SDK_ROOT/ndk/28.0.13004108"
bash build_tools/build_mars_xlog.sh --android --clean --sync-local
```

### iOS Build Cannot Find xcodebuild

Confirm Xcode and Command Line Tools are installed and selected:

```bash
xcode-select -p
xcodebuild -version
```

### Mars Cache Is Broken

If the Mars checkout was interrupted or polluted, remove `build_tools/.cache/mars`
and rerun the build script. The cache directory is local-only and should not be
committed.

## Pre-Publish Checks

After rebuilding and syncing native artifacts, run at least:

```bash
dart analyze
dart pub publish --dry-run
```

Before publishing, also verify the example app on a real Android device or
emulator and an iOS simulator or device.
