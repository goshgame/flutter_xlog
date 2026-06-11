import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Severity level used when writing an xlog entry.
enum XLogLevel {
  /// Verbose diagnostic output.
  verbose(0),

  /// Debug output for development-time diagnostics.
  debug(1),

  /// Informational output for normal runtime events.
  info(2),

  /// Warning output for recoverable problems.
  warn(3),

  /// Error output for failures that should be investigated.
  error(4);

  const XLogLevel(this.value);

  /// Native mars xlog integer value for this level.
  final int value;
}

/// Native xlog write mode.
enum XLogMode {
  /// Write logs synchronously.
  sync(0),

  /// Buffer and write logs asynchronously.
  async(1);

  const XLogMode(this.value);

  /// Native mars xlog integer value for this mode.
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

/// Singleton wrapper around the bundled native mars xlog library.
///
/// Call [init] once before writing logs, then use [v], [d], [i], [w], [e], or
/// [log] to emit entries. Call [flush] when pending logs must be persisted and
/// [close] when the logger is no longer needed.
class FlutterXLog {
  FlutterXLog._();

  /// Shared xlog instance used by applications.
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

  /// Initializes the native xlog runtime.
  ///
  /// [logDir] is the final log directory and [cacheDir] is the temporary cache
  /// directory used by xlog. Optional size, age, public-key, and console-log
  /// settings are passed through to the native library.
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

  /// Stores the xlog public key to use during [init].
  ///
  /// This must be called before [init]. Pass [publicKey] directly to [init] if
  /// you prefer to configure the key in a single call.
  void setPublicKey(String pubkey) {
    if (_initialized) {
      throw StateError('setPublicKey() must be called before init().');
    }
    _pendingPublicKey = pubkey;
  }

  /// Enables or disables native console logging.
  ///
  /// When called before [init], the setting is applied during initialization.
  void setConsoleLogOpen(bool isOpen) {
    _pendingConsoleLogOpen = isOpen;
    if (!_initialized) {
      return;
    }
    _setConsoleLogOpen(isOpen ? 1 : 0);
  }

  /// Writes a log entry with the given [level], [tag], and [message].
  ///
  /// Optional source metadata can be supplied with [fileName], [funcName], and
  /// [line].
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

  /// Writes a verbose log entry.
  void v(String tag, String message) {
    log(XLogLevel.verbose, tag, message);
  }

  /// Writes a debug log entry.
  void d(String tag, String message) {
    log(XLogLevel.debug, tag, message);
  }

  /// Writes an informational log entry.
  void i(String tag, String message) {
    log(XLogLevel.info, tag, message);
  }

  /// Writes a warning log entry.
  void w(String tag, String message) {
    log(XLogLevel.warn, tag, message);
  }

  /// Writes an error log entry.
  void e(String tag, String message) {
    log(XLogLevel.error, tag, message);
  }

  /// Flushes pending log data to storage.
  ///
  /// Set [sync] to `true` when the caller must wait for native flushing to
  /// complete.
  void flush({bool sync = false}) {
    _ensureInitialized();
    _flush(sync ? 1 : 0);
  }

  /// Closes the native xlog runtime.
  ///
  /// Calling this before [init] is a no-op.
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
