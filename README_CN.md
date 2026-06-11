<p align="center">
  <strong>flutter_xlog</strong>
</p>

<p align="center">
  <i>面向 Android 和 iOS 的 Tencent mars xlog Flutter FFI 插件。</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Flutter-40c4ff.svg" alt="Flutter Platform Badge">
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-4caf50.svg" alt="Android and iOS Badge">
  <img src="https://img.shields.io/badge/FFI-native-ff69b4.svg" alt="FFI Native Badge">
  <img src="https://img.shields.io/badge/license-MIT-purple.svg" alt="MIT License Badge">
</p>

---

# flutter_xlog

[English](README_EN.md)

`flutter_xlog` 用一个轻量的 Flutter FFI API 封装 Tencent mars xlog。包内
携带 Android 和 iOS native 产物，宿主 Flutter App 不需要在自身工程里编译
mars，就可以通过 xlog 写入 native 日志。

## 使用

添加依赖：

```yaml
dependencies:
  flutter_xlog_ffi: ^0.0.2
```

引入包：

```dart
import 'package:flutter_xlog_ffi/flutter_xlog_ffi.dart';
```

写日志前先初始化 xlog：

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

写入并 flush 日志：

```dart
FlutterXLog.instance.i('Home', 'page opened');
FlutterXLog.instance.e('Network', 'request failed');
FlutterXLog.instance.flush(sync: true);
```

不再需要 logger 时关闭：

```dart
FlutterXLog.instance.close();
```

## 功能

- **Flutter FFI API**：通过简洁的 Dart 封装访问 mars xlog。
- **Android 和 iOS**：内置两个移动平台的 native 产物。
- **日志生命周期控制**：在 Dart 侧完成初始化、写入、flush 和关闭。
- **控制台日志开关**：调试时可以打开 native console log。
- **公钥支持**：初始化前可配置 xlog public key。
- **同步或异步模式**：按运行时需求选择 xlog mode。

## 公钥

如果你的 xlog 构建使用加密日志，可以在 `init()` 前设置公钥：

```dart
FlutterXLog.instance.setPublicKey('your public key');
FlutterXLog.instance.init(
  logDir: '/path/to/logs',
  cacheDir: '/path/to/cache',
);
```

也可以直接通过 `init(publicKey: ...)` 传入。

## 平台说明

### Android

包内包含以下 ABI 的 Android 动态库：

- `armeabi-v7a`
- `arm64-v8a`

宿主 App 仍需要正确打包 native libraries。对于 16 KB page size 设备，需要验证最终 APK 或 AAB。

### iOS

包内包含 `ios/Frameworks/flutter_xlog.xcframework`，覆盖 iOS 真机和模拟器构建。

### 本地编译

如需重新编译随包分发的 Android 和 iOS native 产物，请参考
[本地编译说明](build_tools/LOCAL_BUILD.md)。

## 示例

`example/` 提供了一个最小 Flutter App，用于演示初始化 xlog、写入示例日志、flush
日志并关闭 logger。

```bash
cd example
flutter pub get
flutter run
```
