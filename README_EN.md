<p align="center">
  <strong>flutter_xlog</strong>
</p>

<p align="center">
  <i>A Flutter FFI plugin for Tencent mars xlog on Android and iOS.</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Flutter-40c4ff.svg" alt="Flutter Platform Badge">
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-4caf50.svg" alt="Android and iOS Badge">
  <img src="https://img.shields.io/badge/FFI-native-ff69b4.svg" alt="FFI Native Badge">
  <img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="MIT License Badge">
</p>

---

# flutter_xlog

[中文文档](README.md)

`flutter_xlog` packages Tencent mars xlog behind a small Flutter FFI API. It
ships with native artifacts for Android and iOS, so Flutter apps can write logs
through xlog without compiling mars inside the host app.

## Usage

Add the dependency:

```yaml
dependencies:
  flutter_xlog_ffi: ^0.0.4
```

Import it:

```dart
import 'package:flutter_xlog_ffi/flutter_xlog_ffi.dart';
```

Initialize xlog before writing logs:

```dart
FlutterXLog.instance.init(
  logDir: '/path/to/logs',
  cacheDir: '/path/to/cache',
  prefixName: 'myapp',
  level: XLogLevel.debug,
  mode: XLogMode.async,
  cacheDays: 3,
  consoleLogOpen: true,
);
```

Write and flush logs:

```dart
FlutterXLog.instance.i('Home', 'page opened');
FlutterXLog.instance.e('Network', 'request failed');
FlutterXLog.instance.flush(sync: true);
```

Close the logger when it is no longer needed:

```dart
FlutterXLog.instance.close();
```

## Features

- **Flutter FFI API**: Access mars xlog through a compact Dart wrapper.
- **Android and iOS**: Includes native artifacts for both mobile platforms.
- **Log lifecycle control**: Initialize, write, flush, and close logs from Dart.
- **Console log switch**: Enable native console logging when debugging.
- **Public key support**: Configure an xlog public key before initialization.
- **Async or sync mode**: Choose the xlog mode that matches your runtime needs.

## Public key

Set a public key before `init()` if your xlog build uses encrypted logs:

```dart
FlutterXLog.instance.setPublicKey('your public key');
FlutterXLog.instance.init(
  logDir: '/path/to/logs',
  cacheDir: '/path/to/cache',
);
```

You can also pass the key directly to `init(publicKey: ...)`.

## Platform notes

Dart's `FlutterXLog.instance.init()` configures and opens xlog for the process.
The native facades only write and flush, so Flutter and native code use the
same xlog output stream. Native code must not call `xlog_open` or `xlog_close`.

### Android

The package includes Android shared libraries for:

- `armeabi-v7a`
- `arm64-v8a`

The host app is still responsible for packaging native libraries correctly.
For Android devices with 16 KB page size, validate the final APK or AAB.

Java and Kotlin modules can use `XLogNative` from the AAR:

```kotlin
import com.gosh.flutter_xlog.XLogNative

XLogNative.i("Player", "decoder initialized")
XLogNative.e("Player", "decoder failed")
XLogNative.flush(false)
```

`write(...)` additionally accepts file, function, and line metadata. The
convenience methods do not collect Kotlin/Java stack traces for regular logs.

For another local Flutter plugin that writes from Android native code, declare
the dependency in that plugin's `android/build.gradle`:

```gradle
dependencies {
    implementation project(':flutter_xlog_ffi')
}
```

Also add `flutter_xlog_ffi: ^0.0.4` to that plugin's `pubspec.yaml`, so Flutter
includes both plugins in the host app. After `flutter pub get`, the plugin can
use `XLogNative` without copying an AAR or shared library manually.

### iOS

The package includes `ios/Frameworks/flutter_xlog.xcframework` for iOS device
and simulator builds.

Objective-C and Swift can import `flutter_xlog` and use `FLXNativeLog`:

```swift
import flutter_xlog

FLXNativeLog.info(tag: "Player", message: "decoder initialized")
FLXNativeLog.log(
  level: .error,
  tag: "Player",
  file: #fileID,
  function: #function,
  line: #line,
  message: "decoder failed"
)
```

Native logs written before Dart initialization are retained in a bounded,
process-local queue of up to 200 entries or 64 KB and replayed after the first
successful `init()`. Separate processes, including Android `android:process`
and iOS App Extensions, must initialize their own appender and use an
independent log directory or prefix.

For another local Flutter plugin that writes from iOS native code, declare the
pod dependency in its `.podspec`:

```ruby
s.dependency 'flutter_xlog_ffi'
```

Its Swift or Objective-C files can then import `flutter_xlog` and call
`FLXNativeLog`. After `flutter pub get`, Flutter and CocoaPods link the
XCFramework automatically.

### Native rebuilds

See [Local Build Guide](build_tools/LOCAL_BUILD_EN.md) to rebuild the bundled
Android and iOS native artifacts.

## Example

See `example/` for a minimal Flutter app that initializes xlog, writes sample
logs, flushes them, and closes the logger.

```bash
cd example
flutter pub get
flutter run
```
