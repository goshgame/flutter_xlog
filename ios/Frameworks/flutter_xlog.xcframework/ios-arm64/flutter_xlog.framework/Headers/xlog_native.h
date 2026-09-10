#ifndef FLUTTER_XLOG_NATIVE_H
#define FLUTTER_XLOG_NATIVE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FLXLogLevel) {
  FLXLogLevelVerbose = 0,
  FLXLogLevelDebug = 1,
  FLXLogLevelInfo = 2,
  FLXLogLevelWarn = 3,
  FLXLogLevelError = 4,
};

/// Native-platform facade for the xlog runtime initialized by FlutterXLog.
///
/// This facade only writes and flushes. FlutterXLog owns appender configuration,
/// opening, and closing so Flutter and native logs share one xlog output stream.
@interface FLXNativeLog : NSObject

+ (void)logWithLevel:(FLXLogLevel)level
                  tag:(NSString *)tag
                 file:(NSString *)file
             function:(NSString *)function
                 line:(NSInteger)line
              message:(NSString *)message NS_SWIFT_NAME(log(level:tag:file:function:line:message:));

+ (void)verboseWithTag:(NSString *)tag message:(NSString *)message NS_SWIFT_NAME(verbose(tag:message:));
+ (void)debugWithTag:(NSString *)tag message:(NSString *)message NS_SWIFT_NAME(debug(tag:message:));
+ (void)infoWithTag:(NSString *)tag message:(NSString *)message NS_SWIFT_NAME(info(tag:message:));
+ (void)warnWithTag:(NSString *)tag message:(NSString *)message NS_SWIFT_NAME(warn(tag:message:));
+ (void)errorWithTag:(NSString *)tag message:(NSString *)message NS_SWIFT_NAME(error(tag:message:));

+ (void)flushSynchronously:(BOOL)synchronously;
+ (BOOL)isOpen;

@end

NS_ASSUME_NONNULL_END

#endif
