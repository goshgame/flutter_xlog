#include "xlog_bridge.h"
#include "include/flutter_xlog_build_state.h"

#include <string>
#include <sys/time.h>

// Android 侧 xlog C 桥接实现：
// - 对 Dart FFI 暴露稳定 C ABI；
// - 内部再转发给 mars::xlog C++ 接口；
// - 若编译期无 mars 依赖，则降级为 no-op，并由 xlog_is_available() 告知上层。

#if FLUTTER_XLOG_HAS_MARS && __has_include("mars/xlog/appender.h") && __has_include("mars/xlog/xlogger.h")
#include "mars/xlog/appender.h"
#include "mars/xlog/xlogger.h"
#define FLUTTER_XLOG_MARS_AVAILABLE 1
#else
#define FLUTTER_XLOG_MARS_AVAILABLE 0
#endif

#if FLUTTER_XLOG_MARS_AVAILABLE
using namespace mars::xlog;

namespace {
std::string g_pub_key;

XLogConfig BuildXLogConfig(int mode,
                           const char* cache_dir,
                           const char* log_dir,
                           const char* prefix_name,
                           int cache_days) {
    XLogConfig config;
    // Dart: 0=sync, 1=async; Mars: 0=async, 1=sync.
    config.mode_ = mode == 0 ? kAppenderSync : kAppenderAsync;
    config.cachedir_ = cache_dir == nullptr ? "" : cache_dir;
    config.logdir_ = log_dir == nullptr ? "" : log_dir;
    config.nameprefix_ = prefix_name == nullptr ? "" : prefix_name;
    config.cache_days_ = cache_days;
    config.compress_mode_ = kZlib;
    config.compress_level_ = 0;
    config.pub_key_ = g_pub_key;
    return config;
}

void ApplyAppenderLimits(int64_t max_file_size_bytes, int64_t max_alive_duration_seconds) {
    if (max_file_size_bytes > 0) {
        appender_set_max_file_size(static_cast<uint64_t>(max_file_size_bytes));
    }
    if (max_alive_duration_seconds > 0) {
        appender_set_max_alive_duration(static_cast<long>(max_alive_duration_seconds));
    }
}
}
#endif

extern "C" void xlog_open(int level,
                           int mode,
                           const char* cache_dir,
                           const char* log_dir,
                           const char* prefix_name,
                           int cache_days,
                           int64_t max_file_size_bytes,
                           int64_t max_alive_duration_seconds) {
#if FLUTTER_XLOG_MARS_AVAILABLE
    // 初始化 xlog appender（日志级别、模式、目录、压缩、公钥等）。
    xlogger_SetLevel((TLogLevel)level);

    const XLogConfig config = BuildXLogConfig(mode, cache_dir, log_dir, prefix_name, cache_days);
    ApplyAppenderLimits(max_file_size_bytes, max_alive_duration_seconds);
    // 升级首启时，先尝试把旧 mmap 缓冲冲刷成正式日志，避免旧尾日志继续滞留在缓存文件里。
    appender_oneshot_flush(config, nullptr);
    appender_open(config);
#else
    (void)level;
    (void)mode;
    (void)cache_dir;
    (void)log_dir;
    (void)prefix_name;
    (void)cache_days;
    (void)max_file_size_bytes;
    (void)max_alive_duration_seconds;
#endif
}

extern "C" void xlog_write(int level,
                            const char* tag,
                            const char* file_name,
                            const char* func_name,
                            int line,
                            const char* message) {
#if FLUTTER_XLOG_MARS_AVAILABLE
    // 构造 xlog 元信息并写入单条日志。
    XLoggerInfo info = XLOGGER_INFO_INITIALIZER;
    info.level = (TLogLevel)level;
    info.tag = tag == nullptr ? "" : tag;
    info.filename = file_name == nullptr ? "" : file_name;
    info.func_name = func_name == nullptr ? "" : func_name;
    info.line = line;
    gettimeofday(&info.timeval, nullptr);
    info.pid = xlogger_pid();
    info.tid = xlogger_tid();
    info.maintid = xlogger_maintid();

    xlogger_Write(&info, message == nullptr ? "" : message);
#else
    (void)level;
    (void)tag;
    (void)file_name;
    (void)func_name;
    (void)line;
    (void)message;
#endif
}

extern "C" void xlog_flush(int is_sync) {
#if FLUTTER_XLOG_MARS_AVAILABLE
    // 统一暴露同步/异步刷盘能力，供上层在前后台切换与退出时调用。
    if (is_sync != 0) {
        appender_flush_sync();
    } else {
        appender_flush();
    }
#else
    (void)is_sync;
#endif
}

extern "C" void xlog_close(void) {
#if FLUTTER_XLOG_MARS_AVAILABLE
    // 显式关闭 appender，释放内部线程与文件句柄。
    appender_close();
#endif
}

extern "C" void xlog_set_pubkey(const char* pubkey) {
#if FLUTTER_XLOG_MARS_AVAILABLE
    // 缓存公钥，后续在 open 时写入 XLogConfig。
    g_pub_key = pubkey == nullptr ? "" : pubkey;
#else
    (void)pubkey;
#endif
}

extern "C" void xlog_set_console_log_open(int is_open) {
#if FLUTTER_XLOG_MARS_AVAILABLE
    appender_set_console_log(is_open != 0);
#else
    (void)is_open;
#endif
}

extern "C" int xlog_is_available(void) {
#if FLUTTER_XLOG_MARS_AVAILABLE
    // 真实 mars xlog 可用。
    return 1;
#else
    // 降级 stub（无真实 mars 依赖）。
    return 0;
#endif
}
