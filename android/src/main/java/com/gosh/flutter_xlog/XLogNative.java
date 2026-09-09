package com.gosh.flutter_xlog;

/**
 * Native-platform facade for the xlog runtime initialized by FlutterXLog.
 *
 * <p>This class deliberately exposes write and flush operations only. FlutterXLog owns
 * configuration, opening, and closing of the shared mars xlog appender.</p>
 */
public final class XLogNative {
  public static final int VERBOSE = 0;
  public static final int DEBUG = 1;
  public static final int INFO = 2;
  public static final int WARN = 3;
  public static final int ERROR = 4;

  static {
    System.loadLibrary("flutter_xlog");
  }

  private XLogNative() {}

  public static void v(String tag, String message) {
    write(VERBOSE, tag, "", "", 0, message);
  }

  public static void d(String tag, String message) {
    write(DEBUG, tag, "", "", 0, message);
  }

  public static void i(String tag, String message) {
    write(INFO, tag, "", "", 0, message);
  }

  public static void w(String tag, String message) {
    write(WARN, tag, "", "", 0, message);
  }

  public static void e(String tag, String message) {
    write(ERROR, tag, "", "", 0, message);
  }

  public static void write(
      int level, String tag, String file, String function, int line, String message) {
    nativeWrite(level, tag, file, function, line, message);
  }

  public static void flush(boolean sync) {
    nativeFlush(sync);
  }

  public static boolean isOpen() {
    return nativeIsOpen();
  }

  private static native void nativeWrite(
      int level, String tag, String file, String function, int line, String message);

  private static native void nativeFlush(boolean sync);

  private static native boolean nativeIsOpen();
}
