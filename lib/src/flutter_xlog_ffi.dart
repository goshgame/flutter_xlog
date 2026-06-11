import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

enum XLogLevel {
  verbose(0),
  debug(1),
  info(2),
  warn(3),
  error(4);

  const XLogLevel(this.value);
  final int value;
}

enum XLogMode {
  sync(0),
  async(1);

  const XLogMode(this.value);
  final int value;
}

typedef _XlogOpenNative = Void Function(
  Int32 level,
  Int32 mode,
  Pointer<Utf8> cacheDir,
  Pointer<Utf8> logDir,
  Pointer<Utf8> prefixName,
  Int32 cacheDays,
  Int64 maxFileSizeBytes,
  Int64 maxAliveDurationSeconds,
);
typedef _XlogOpenDart = void Function(
  int level,
  int mode,
  Pointer<Utf8> cacheDir,
  Pointer<Utf8> logDir,
  Pointer<Utf8> prefixName,
  int cacheDays,
  int maxFileSizeBytes,
  int maxAliveDurationSeconds,
);

typedef _XlogWriteNative = Void Function(
  Int32 level,
  Pointer<Utf8> tag,
  Pointer<Utf8> fileName,
  Pointer<Utf8> funcName,
  Int32 line,
  Pointer<Utf8> message,
);
typedef _XlogWriteDart = void Function(
  int level,
  Pointer<Utf8> tag,
  Pointer<Utf8> fileName,
  Pointer<Utf8> funcName,
  int line,
  Pointer<Utf8> message,
);

typedef _XlogFlushNative = Void Function(Int32 isSync);
typedef _XlogFlushDart = void Function(int isSync);

typedef _XlogCloseNative = Void Function();
typedef _XlogCloseDart = void Function();

typedef _XlogSetPubKeyNative = Void Function(Pointer<Utf8> pubkey);
typedef _XlogSetPubKeyDart = void Function(Pointer<Utf8> pubkey);
typedef _XlogSetConsoleLogOpenNative = Void Function(Int32 isOpen);
typedef _XlogSetConsoleLogOpenDart = void Function(int isOpen);
typedef _XlogIsAvailableNative = Int32 Function();
typedef _XlogIsAvailableDart = int Function();

class FlutterXLog {
  FlutterXLog._();

  static final FlutterXLog instance = FlutterXLog._();

  bool _initialized = false;

  late final _XlogOpenDart _open;
  late final _XlogWriteDart _write;
  late final _XlogFlushDart _flush;
  late final _XlogCloseDart _close;
  late final _XlogSetPubKeyDart _setPubKey;
  late final _XlogSetConsoleLogOpenDart _setConsoleLogOpen;
  late final _XlogIsAvailableDart _isAvailable;

  String? _pendingPublicKey;
  bool _pendingConsoleLogOpen = false;

  void init({
    required String logDir,
    required String cacheDir,
    String prefixName = 'app',
    XLogLevel level = XLogLevel.info,
    XLogMode mode = XLogMode.async,
    int cacheDays = 3,
    int maxFileSizeBytes = 0,
    int maxAliveDurationSeconds = 0,
    String? publicKey,
    bool? consoleLogOpen,
  }) {
    if (_initialized) {
      return;
    }

    final DynamicLibrary lib = _loadLibrary();
    _open = lib.lookupFunction<_XlogOpenNative, _XlogOpenDart>('xlog_open');
    _write = lib.lookupFunction<_XlogWriteNative, _XlogWriteDart>('xlog_write');
    _flush = lib.lookupFunction<_XlogFlushNative, _XlogFlushDart>('xlog_flush');
    _close = lib.lookupFunction<_XlogCloseNative, _XlogCloseDart>('xlog_close');
    _setPubKey =
        lib.lookupFunction<_XlogSetPubKeyNative, _XlogSetPubKeyDart>('xlog_set_pubkey');
    _setConsoleLogOpen = lib.lookupFunction<
        _XlogSetConsoleLogOpenNative,
        _XlogSetConsoleLogOpenDart>('xlog_set_console_log_open');
    _isAvailable =
        lib.lookupFunction<_XlogIsAvailableNative, _XlogIsAvailableDart>('xlog_is_available');

    if (_isAvailable() != 1) {
      throw StateError(
        'xlog native library is unavailable. Please ensure mars artifacts are packaged.',
      );
    }

    final String? keyToUse = publicKey ?? _pendingPublicKey;
    final bool consoleLogOpenToUse =
        consoleLogOpen ?? _pendingConsoleLogOpen;

    using((Arena arena) {
      if (keyToUse != null && keyToUse.isNotEmpty) {
        final Pointer<Utf8> cPubKey = keyToUse.toNativeUtf8(allocator: arena);
        _setPubKey(cPubKey);
      }
      final Pointer<Utf8> cCacheDir = cacheDir.toNativeUtf8(allocator: arena);
      final Pointer<Utf8> cLogDir = logDir.toNativeUtf8(allocator: arena);
      final Pointer<Utf8> cPrefix = prefixName.toNativeUtf8(allocator: arena);
      _open(
        level.value,
        mode.value,
        cCacheDir,
        cLogDir,
        cPrefix,
        cacheDays,
        maxFileSizeBytes,
        maxAliveDurationSeconds,
      );
      _setConsoleLogOpen(consoleLogOpenToUse ? 1 : 0);
    });

    _pendingPublicKey = keyToUse;
    _pendingConsoleLogOpen = consoleLogOpenToUse;
    _initialized = true;
  }

  void setPublicKey(String pubkey) {
    if (_initialized) {
      throw StateError('setPublicKey() must be called before init().');
    }
    _pendingPublicKey = pubkey;
  }

  void setConsoleLogOpen(bool isOpen) {
    _pendingConsoleLogOpen = isOpen;
    if (!_initialized) {
      return;
    }
    _setConsoleLogOpen(isOpen ? 1 : 0);
  }

  void log(
    XLogLevel level,
    String tag,
    String message, {
    String fileName = '',
    String funcName = '',
    int line = 0,
  }) {
    _ensureInitialized();

    using((Arena arena) {
      final Pointer<Utf8> cTag = tag.toNativeUtf8(allocator: arena);
      final Pointer<Utf8> cFile = fileName.toNativeUtf8(allocator: arena);
      final Pointer<Utf8> cFunc = funcName.toNativeUtf8(allocator: arena);
      final Pointer<Utf8> cMessage = message.toNativeUtf8(allocator: arena);
      _write(level.value, cTag, cFile, cFunc, line, cMessage);
    });
  }

  void v(String tag, String message) {
    log(XLogLevel.verbose, tag, message);
  }

  void d(String tag, String message) {
    log(XLogLevel.debug, tag, message);
  }

  void i(String tag, String message) {
    log(XLogLevel.info, tag, message);
  }

  void w(String tag, String message) {
    log(XLogLevel.warn, tag, message);
  }

  void e(String tag, String message) {
    log(XLogLevel.error, tag, message);
  }

  void flush({bool sync = false}) {
    _ensureInitialized();
    _flush(sync ? 1 : 0);
  }

  void close() {
    if (!_initialized) {
      return;
    }
    _close();
    _initialized = false;
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libflutter_xlog.so');
    }
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('flutter_xlog only supports Android and iOS.');
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('FlutterXLog is not initialized. Call init() first.');
    }
  }
}
