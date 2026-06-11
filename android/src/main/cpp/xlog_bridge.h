#ifndef FLUTTER_XLOG_BRIDGE_H
#define FLUTTER_XLOG_BRIDGE_H

// flutter_xlog Android C 桥接层对外 ABI。
// 设计目标：
// 1) 仅暴露 C 符号，供 Dart FFI 直接调用；
// 2) 对上层保持稳定签名，屏蔽 mars C++ 接口细节；
// 3) 在无 mars 库场景下，可通过 xlog_is_available() 快速探测能力。

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void xlog_open(
    int level,
    int mode,
    const char* cache_dir,
    const char* log_dir,
    const char* prefix_name,
    int cache_days,
    int64_t max_file_size_bytes,
    int64_t max_alive_duration_seconds
);

// 写一条日志。file/func/line 为可选调试信息。
void xlog_write(
    int level,
    const char* tag,
    const char* file_name,
    const char* func_name,
    int line,
    const char* message
);

// 刷盘：is_sync=1 强制同步刷盘；is_sync=0 走异步刷盘。
void xlog_flush(int is_sync);

// 关闭 appender，释放日志资源。
void xlog_close(void);

// 设置加密公钥（应在 xlog_open 前设置，保证配置生效）。
void xlog_set_pubkey(const char* pubkey);

// 控制是否镜像输出到系统终端。
void xlog_set_console_log_open(int is_open);

// 探测当前进程内是否可用真实 mars xlog 实现：1=可用，0=不可用。
int xlog_is_available(void);

#ifdef __cplusplus
}
#endif

#endif
