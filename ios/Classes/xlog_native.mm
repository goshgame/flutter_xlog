#import "xlog_native.h"

#import "xlog_bridge.h"

@implementation FLXNativeLog

+ (void)logWithLevel:(FLXLogLevel)level
                  tag:(NSString *)tag
                 file:(NSString *)file
             function:(NSString *)function
                 line:(NSInteger)line
              message:(NSString *)message {
  xlog_write(
      (int)level,
      tag.UTF8String,
      file.UTF8String,
      function.UTF8String,
      (int)line,
      message.UTF8String);
}

+ (void)verboseWithTag:(NSString *)tag message:(NSString *)message {
  [self logWithLevel:FLXLogLevelVerbose tag:tag file:@"" function:@"" line:0 message:message];
}

+ (void)debugWithTag:(NSString *)tag message:(NSString *)message {
  [self logWithLevel:FLXLogLevelDebug tag:tag file:@"" function:@"" line:0 message:message];
}

+ (void)infoWithTag:(NSString *)tag message:(NSString *)message {
  [self logWithLevel:FLXLogLevelInfo tag:tag file:@"" function:@"" line:0 message:message];
}

+ (void)warnWithTag:(NSString *)tag message:(NSString *)message {
  [self logWithLevel:FLXLogLevelWarn tag:tag file:@"" function:@"" line:0 message:message];
}

+ (void)errorWithTag:(NSString *)tag message:(NSString *)message {
  [self logWithLevel:FLXLogLevelError tag:tag file:@"" function:@"" line:0 message:message];
}

+ (void)flushSynchronously:(BOOL)synchronously {
  xlog_flush(synchronously ? 1 : 0);
}

+ (BOOL)isOpen {
  return xlog_is_open() == 1;
}

@end
