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
  flutter_xlog_ffi: ^0.0.2
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

### Android

The package includes Android shared libraries for:

- `armeabi-v7a`
- `arm64-v8a`

The host app is still responsible for packaging native libraries correctly.
For Android devices with 16 KB page size, validate the final APK or AAB.

### iOS

The package includes `ios/Frameworks/flutter_xlog.xcframework` for iOS device
and simulator builds.

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
