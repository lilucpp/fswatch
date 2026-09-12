#include <iostream>
#include <string>
#include <vector>
#include <chrono>
#include <iomanip>
#include <csignal>
#include <atomic>
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif
#include <libfswatch/c/libfswatch.h>

static std::atomic<FSW_HANDLE> g_fsw_handle{nullptr};

// Helper function to return human-readable monitor type description
static const char* get_monitor_type_name(enum fsw_monitor_type type)
{
    switch (type)
    {
    case system_default_monitor_type:
        return "system_default_monitor_type (Default -> Windows Native Monitor)";
    case windows_monitor_type:
        return "windows_monitor_type (Windows Native: ReadDirectoryChangesW)";
    case poll_monitor_type:
        return "poll_monitor_type (Stat-based Polling Monitor)";
    case inotify_monitor_type:
        return "inotify_monitor_type (Linux inotify)";
    case fanotify_monitor_type:
        return "fanotify_monitor_type (Linux fanotify)";
    case kqueue_monitor_type:
        return "kqueue_monitor_type (BSD kqueue)";
    case fsevents_monitor_type:
        return "fsevents_monitor_type (macOS FSEvents)";
    case fen_monitor_type:
        return "fen_monitor_type (Solaris/Illumos FEN)";
    default:
        return "unknown_monitor_type";
    }
}

// Ctrl+C Signal handler
static void signal_handler(int signal)
{
    (void)signal;
    std::cout << "\n[INFO] 接收到退出信号，正在停止监听..." << std::endl;
    FSW_HANDLE handle = g_fsw_handle.load();
    if (handle != nullptr) {
        fsw_stop_monitor(handle);
    }
}

// C-compatible callback invoked by libfswatch
extern "C" void fsw_event_callback(fsw_cevent const *const events,
                                   const unsigned int event_num,
                                   void *data)
{
    (void)data;
    for (unsigned int i = 0; i < event_num; ++i) {
        const fsw_cevent& evt = events[i];

        // Format event timestamp
        char time_buf[64] = {0};
        struct tm tm_info;
#if defined(_WIN32)
        localtime_s(&tm_info, &evt.evt_time);
#else
        localtime_r(&evt.evt_time, &tm_info);
#endif
        std::strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", &tm_info);

        std::cout << "[" << time_buf << "] 变更路径: " << (evt.path ? evt.path : "(unknown)") << "\n";
        std::cout << "       事件类型: ";

        for (unsigned int j = 0; j < evt.flags_num; ++j) {
            char *flag_name = fsw_get_event_flag_name(evt.flags[j]);
            if (flag_name) {
                std::cout << flag_name << (j + 1 < evt.flags_num ? ", " : "");
                free(flag_name);
            } else {
                std::cout << "Unknown" << (j + 1 < evt.flags_num ? ", " : "");
            }
        }
        std::cout << "\n" << std::endl;
    }
}

int main(int argc, char *argv[])
{
#if defined(_WIN32)
    // Ensure Windows console interprets and displays UTF-8 strings correctly
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
#endif

    std::string watch_path = ".";
    enum fsw_monitor_type selected_monitor = system_default_monitor_type;

    // Simple argument parsing: supports path and --poll / --windows flags
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--poll" || arg == "-p") {
            selected_monitor = poll_monitor_type;
        } else if (arg == "--windows" || arg == "-w") {
            selected_monitor = windows_monitor_type;
        } else if (arg == "--default" || arg == "-d") {
            selected_monitor = system_default_monitor_type;
        } else if (arg.rfind("-", 0) != 0) {
            watch_path = arg;
        }
    }

    std::cout << "=========================================================\n";
    std::cout << "  libfswatch C API in C++ Demo (MSVC v142 编译)          \n";
    std::cout << "=========================================================\n";
    std::cout << "监听目标路径 : " << watch_path << "\n";
    std::cout << "配置监控模式 : " << get_monitor_type_name(selected_monitor) << " (enum: " << selected_monitor << ")\n";
    std::cout << "可用模式参数 : --windows (原生Win32监听), --poll (轮询监听)\n";
    std::cout << "按 Ctrl+C 退出监听。\n\n";

    // 1. 初始化 libfswatch 库
    if (fsw_init_library() != FSW_OK) {
        std::cerr << "[ERROR] 初始化 libfswatch 失败。\n";
        return 1;
    }

    // 2. 创建监听会话
    FSW_HANDLE handle = fsw_init_session(selected_monitor);
    if (!handle) {
        std::cerr << "[ERROR] 创建 fswatch 会话失败，错误码: " << fsw_last_error() << "\n";
        return 1;
    }
    g_fsw_handle.store(handle);

    // 3. 配置监听路径与参数
    if (fsw_add_path(handle, watch_path.c_str()) != FSW_OK) {
        std::cerr << "[ERROR] 添加监听路径失败: " << watch_path << "\n";
        fsw_destroy_session(handle);
        return 1;
    }

    fsw_set_recursive(handle, true);    // 递归监听子目录
    fsw_set_latency(handle, 0.5);       // 防抖延迟 0.5 秒

    // 注册回调函数
    if (fsw_set_callback(handle, fsw_event_callback, nullptr) != FSW_OK) {
        std::cerr << "[ERROR] 注册回调函数失败。\n";
        fsw_destroy_session(handle);
        return 1;
    }

    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    // 4. 打印当前使用的 Monitor Type 并启动监听
    std::cout << "---------------------------------------------------------\n";
    std::cout << "[INFO] Monitor 已就绪: " << get_monitor_type_name(selected_monitor) << "\n";
    std::cout << "[INFO] 开始进入监听循环，等待文件系统变更事件...\n";
    std::cout << "---------------------------------------------------------\n\n";

    FSW_STATUS status = fsw_start_monitor(handle);
    if (status != FSW_OK) {
        std::cerr << "[ERROR] 监听异常退出，状态码: " << status << "\n";
    }

    // 5. 销毁会话
    g_fsw_handle.store(nullptr);
    fsw_destroy_session(handle);

    std::cout << "[INFO] 会话已正常销毁并退出。\n";
    return 0;
}
