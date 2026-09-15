## 0.0.4

- Fixed invalid iOS `flutter_xlog.framework` bundle identifiers in the
  prebuilt xcframework.

## 0.0.3

- Added `XLogNative` for Android Java/Kotlin code and `FLXNativeLog` for iOS
  Objective-C/Swift code, so native and Dart logs share the same xlog output.
- Buffered up to 200 native startup logs or 64 KB before Dart initializes xlog,
  then replay them after the appender opens.
- Added `xlog_is_open()` and native `flush` helpers for lifecycle-aware callers.
- Documented Gradle and CocoaPods integration for local Flutter plugins that
  need to write through xlog.

## 0.0.2

- Fixed the iOS podspec name so Flutter and CocoaPods can resolve the
  `flutter_xlog_ffi` plugin correctly.

## 0.0.1

- Initial Flutter FFI xlog plugin release.
- Added Android prebuilt shared libraries for `armeabi-v7a` and `arm64-v8a`.
- Added iOS prebuilt `flutter_xlog.xcframework` for device and simulator builds.
- Added Dart APIs for init, write, flush, close, console logging, and public-key setup.
- Added a minimal Flutter example app.
