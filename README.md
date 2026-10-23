# BililiveRecorder 运维脚本包

BililiveRecorder CLI 的启动 / 停止 / 状态 / 重启脚本，开箱即用，适合 Linux 后台常驻录制。

> 本仓库**只包含运维脚本**，不含 BililiveRecorder 程序本体。程序需自行下载后放入指定目录（见下文）。

## 目录要求（重要）

`common.sh` 中的程序路径是写死的，**目录名和可执行文件名必须完全一致**：

```
BililiveRecorder/
├── BililiveRecorder-CLI-linux/        ← 必须是这个目录名
│   └── BililiveRecorder.Cli           ← 必须是这个可执行文件名
├── common.sh
├── start.sh
├── stop.sh
├── status.sh
├── restart.sh
├── cookie/
│   └── bilibili.txt
└── recordings/
    └── config.json
```

从 [BililiveRecorder Releases](https://github.com/BililiveRecorder/BililiveRecorder/releases) 下载 `linux-x64` 版本，解压后重命名为 `BililiveRecorder-CLI-linux` 放到项目根目录即可。

## 快速开始

```bash
# 1. 补执行权限（某些解压工具会丢权限）
chmod +x common.sh start.sh stop.sh status.sh restart.sh

# 2. 建录制目录（run/、logs/ 脚本会自动创建）
mkdir -p recordings

# 3. 放入自己的 cookie（可选，登录态可录高画质）
#    cookie/bilibili.txt

# 4. 后台启动
./start.sh -b

# 5. 查看状态
./status.sh
```

浏览器访问 `http://localhost:2356` 进入 Web 管理界面。

## 脚本说明

| 脚本 | 作用 |
|---|---|
| `start.sh` | 启动。`-f` 前台（Ctrl+C 停止），`-b` 后台，无参数交互选择 |
| `stop.sh` | 停止。默认 SIGTERM 优雅退出（最多等 15s 收尾录制），`-f` 强制 SIGKILL |
| `status.sh` | 状态。PID、CPU/内存、HTTP 健康检查、录制占用、磁盘剩余、最近日志 |
| `restart.sh` | 重启（等价于 `stop.sh` + `start.sh -b`） |
| `common.sh` | 公共配置与函数，被其余脚本 `source`，**不要直接执行** |

## 配置

修改 `common.sh` 顶部：

```bash
BIND="http://localhost:2356"      # 监听地址
WORKDIR="$ROOT_DIR/recordings"    # 录制输出目录
LOG_MAX_MB=100                    # 控制台日志超过此大小自动轮转
STOP_TIMEOUT=15                   # 优雅停止最长等待秒数
```

录制相关配置（房间、画质、文件命名等）在 `recordings/config.json`，由程序自己维护。

## 运行产物

| 路径 | 说明 | 是否可删 |
|---|---|---|
| `run/recorder.pid` | 进程 PID | 可，脚本会自动重建 |
| `run/start.lock` | 启动锁 | 可 |
| `logs/recorder.log` | 控制台输出日志 | 可，超过 `LOG_MAX_MB` 自动轮转 |
| `BililiveRecorder-CLI-linux/logs/` | 程序自身 Serilog 日志 | 排查问题用，**不要删** |

## 常见问题

**启动报“找不到可执行文件”**
检查 `BililiveRecorder-CLI-linux/BililiveRecorder.Cli` 是否存在且可执行：`ls -l` 后必要时 `chmod +x`。

**启动报“已经在运行”但实际没有进程**
`run/recorder.pid` 残留了被复用的 PID，`rm run/recorder.pid` 后重试。

**启动后 HTTP 检测失败**
看 `logs/recorder.log`，常见原因：端口 2356 被占、`config.json` 格式损坏、cookie 过期。

**换了程序版本后录不了**
确认新版本目录结构没变，且 `config.json` 兼容。升级前备份 `recordings/config.json`。

## 许可证

本仓库脚本采用 [MIT License](LICENSE)，Copyright (c) 2026 vers123。

BililiveRecorder 程序本体为其原作者所有，遵循其自身许可证（GPL-3.0），与本脚本包相互独立，本包仅通过命令行调用程序，不包含、不修改程序代码。
