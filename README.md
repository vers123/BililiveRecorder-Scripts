# BililiveRecorder 运维脚本包

BililiveRecorder CLI 的启动 / 停止 / 状态 / 重启脚本，开箱即用，支持 **Windows / Linux / macOS** 三平台后台常驻录制。

> 本仓库**只包含运维脚本**，不含 BililiveRecorder 程序本体。程序需自行下载后放入指定目录（见下文）。

## 平台与脚本对照

| 平台 | 使用脚本 | 程序包 |
|---|---|---|
| Linux | `start.sh` / `stop.sh` / `status.sh` / `restart.sh` | `BililiveRecorder-CLI-linux-*` |
| macOS | 同上（bash） | `BililiveRecorder-CLI-osx-*` |
| Windows | `start.ps1` / `stop.ps1` / `status.ps1` / `restart.ps1` | `BililiveRecorder-CLI-win-x64` |

两套脚本的参数、退出码与文件布局完全一致，只是解释器不同。

## 目录要求

程序目录**不再要求固定名字**，脚本会自动扫描项目根目录下的 `BililiveRecorder-CLI-*` 目录，按「平台+架构精确匹配 > 同平台任意包 > `any` 版」的优先级选择。

```
BililiveRecorder-Scripts/
├── BililiveRecorder-CLI-linux-x64/     ← 解压后的程序目录（名字随平台变化）
│   └── BililiveRecorder.Cli
├── common.sh / start.sh / stop.sh / status.sh / restart.sh
├── common.ps1 / start.ps1 / stop.ps1 / status.ps1 / restart.ps1
├── cookie/
│   └── bilibili.txt
└── recordings/
    └── config.json
```

支持的目录名（举例）：

- Windows：`BililiveRecorder-CLI-win-x64`（可执行文件 `BililiveRecorder.Cli.exe`）
- Linux：`BililiveRecorder-CLI-linux-x64`、`-linux-arm64`、`-linux-arm`、`-linux-musl-x64`、`-linux-musl-arm64`，旧版的 `BililiveRecorder-CLI-linux` 依然可用
- macOS：`BililiveRecorder-CLI-osx-x64`、`-osx-arm64`
- 兜底：`BililiveRecorder-CLI-any`（需要系统已安装 .NET 8 运行时，通过 `dotnet BililiveRecorder.Cli.dll` 启动）

如果目录名被改过，可以用环境变量显式指定可执行文件：

```bash
# Linux / macOS
export BREC_BIN=/path/to/BililiveRecorder.Cli
```

```powershell
# Windows
$env:BREC_BIN = 'D:\somewhere\BililiveRecorder.Cli.exe'
```

## 下载程序

从 [BililiveRecorder Releases](https://github.com/BililiveRecorder/BililiveRecorder/releases) 下载，解压后保持压缩包内的目录名放到项目根目录：

| 系统 | 架构 | 压缩包 |
|---|---|---|
| Windows | x64 | [BililiveRecorder-CLI-win-x64.zip](https://github.com/BililiveRecorder/BililiveRecorder/releases/latest/download/BililiveRecorder-CLI-win-x64.zip) |
| Linux | x64 | [BililiveRecorder-CLI-linux-x64.zip](https://github.com/BililiveRecorder/BililiveRecorder/releases/latest/download/BililiveRecorder-CLI-linux-x64.zip) |
| Linux | arm64 | [BililiveRecorder-CLI-linux-arm64.zip](https://github.com/BililiveRecorder/BililiveRecorder/releases/latest/download/BililiveRecorder-CLI-linux-arm64.zip) |
| Linux | arm32 | [BililiveRecorder-CLI-linux-arm.zip](https://github.com/BililiveRecorder/BililiveRecorder/releases/latest/download/BililiveRecorder-CLI-linux-arm.zip) |
| macOS | arm64 | [BililiveRecorder-CLI-osx-arm64.zip](https://github.com/BililiveRecorder/BililiveRecorder/releases/latest/download/BililiveRecorder-CLI-osx-arm64.zip) |
| macOS | x64 | [BililiveRecorder-CLI-osx-x64.zip](https://github.com/BililiveRecorder/BililiveRecorder/releases/latest/download/BililiveRecorder-CLI-osx-x64.zip) |
| 任意 | — | [BililiveRecorder-CLI-any.zip](https://github.com/BililiveRecorder/BililiveRecorder/releases/latest/download/BililiveRecorder-CLI-any.zip)（需装 .NET 8 运行时） |

## Cookie 导入（推荐 Header String）

登录状态可以录到更高画质。脚本支持从 `cookie/bilibili.txt` 自动导入，也支持在 Web 界面手动填写。

### 导出格式

| 格式 | 示例 | 是否支持 |
|---|---|---|
| **Header String** | `SESSDATA=xxx; bili_jct=yyy; buvid3=zzz` | ✅ **推荐**，程序直接可用的 `Cookie` 请求头原文 |
| JSON | `[{"name":"SESSDATA","value":"...","domain":".bilibili.com"}]` | ❌ 不支持，需要转换 |
| Netscape | 制表符分隔的 curl/wget cookie 文件 | ❌ 不支持，需要转换 |

脚本只接受 Header String；检测到 JSON 或 Netscape 内容时会直接提示重新导出。

### 存放位置

- 路径：`cookie/bilibili.txt`
- 编码 UTF-8，单行最佳；多行粘贴也可以，脚本会自动合并
- 允许带 `Cookie:` 前缀，脚本会自动去掉
- 该目录已被 `.gitignore` 忽略，`pack.sh/pack.ps1 --public` 也不会打包它

导出步骤：

1. 浏览器登录 [bilibili.com](https://www.bilibili.com)
2. 打开 Cookie Editor 扩展
3. 点击 Export → 选择 **Header String** → 复制
4. 粘贴保存到 `cookie/bilibili.txt`

### 启动时的选择

`start.sh` / `start.ps1` 检测到该文件后会询问：

```
检测到 cookie：...（3 项，包含 SESSDATA）
  1) 自动写入 recordings/config.json（推荐）
  2) 我自己填写（启动后在 Web 界面设置）
选择 [1]:
```

- 非交互场景（计划任务、重定向、CI）自动选择 1，不阻塞启动
- 写入前会备份为 `recordings/config.json.bak`，只改 `global.Cookie`，其它设置不受影响
- 写入失败（例如 Linux/macOS 缺少 `jq` / `python3` / `perl`）不会阻止启动，会提示改用 Web 界面
- 脚本不会输出 cookie 明文，只显示项数与是否包含 `SESSDATA`

手动填写：启动后访问 `http://localhost:2356` → 设置 → 全局 → Cookie → 粘贴 Header String → 保存。

> Cookie 等同账号凭据，请勿提交到仓库或分享给他人。过期后重新导出并覆盖 `cookie/bilibili.txt` 即可；程序运行期间请通过 Web 界面修改，不要直接编辑 `config.json`。

## 快速开始

### Linux / macOS

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

macOS 从浏览器下载的压缩包会带隔离属性，若提示「无法打开，因为无法验证开发者」，先执行：

```bash
xattr -dr com.apple.quarantine BililiveRecorder-CLI-osx-arm64
```

### Windows

```powershell
# 1. 解除下载文件的锁定（否则执行策略会拦截）
Unblock-File .\*.ps1
Unblock-File .\BililiveRecorder-CLI-win-x64\BililiveRecorder.Cli.exe

# 2. 建录制目录（run\、logs\ 脚本会自动创建）
New-Item -ItemType Directory -Force -Path .\recordings | Out-Null

# 3. 后台启动（Windows PowerShell 5.1 或 PowerShell 7 均可）
powershell -NoProfile -ExecutionPolicy Bypass -File .\start.ps1 -Background
# 已经装了 PowerShell 7 的话也可以：
# pwsh -NoProfile -File .\start.ps1 -Background

# 4. 查看状态
powershell -NoProfile -ExecutionPolicy Bypass -File .\status.ps1
```

浏览器访问 `http://localhost:2356` 进入 Web 管理界面。

## 脚本说明

| bash | PowerShell | 作用 |
|---|---|---|
| `start.sh` | `start.ps1` | 启动。`-f` 前台（Ctrl+C 停止），`-b` 后台，无参数交互选择 |
| `stop.sh` | `stop.ps1` | 停止。默认优雅退出（最多等 15s 收尾录制），`-f` 强制结束 |
| `status.sh` | `status.ps1` | 状态。PID、CPU/内存、HTTP 健康检查、录制占用、磁盘剩余、最近日志 |
| `restart.sh` | `restart.ps1` | 重启（等价于 stop + start -b） |
| `common.sh` | `common.ps1` | 公共配置与函数，被其余脚本加载，**不要直接执行** |
| `pack.sh` | `pack.ps1` | 打包发布包（tar.gz / zip） |

## 停止行为（重要）

BililiveRecorder 只有收到 **Ctrl+C（SIGINT）** 才会先停止录制、保存配置再退出。

- **Linux / macOS**：`stop.sh` 发送 `SIGTERM`，程序收到后同样会优雅退出；15s 内未退出才 `SIGKILL`。
- **Windows**：`stop.ps1` 会用一个独立子进程向目标控制台发送 `CTRL_C_EVENT`，模拟 Ctrl+C。若控制台已不可用或 15s 内未退出，会降级为强制结束，并打印警告——此时配置文件可能未保存、弹幕文件可能不完整，请尽量避免。

因此 Windows 上**不要**直接点命令行窗口的关闭按钮或任务管理器结束进程；请始终用 `stop.ps1`。

## 配置

修改 `common.sh` / `common.ps1` 顶部：

```bash
BIND="http://localhost:2356"      # 监听地址
WORKDIR="$ROOT_DIR/recordings"    # 录制输出目录
LOG_MAX_MB=100                    # 控制台日志超过此大小自动轮转
STOP_TIMEOUT=15                   # 优雅停止最长等待秒数
```

录制相关配置（房间、画质、文件命名等）在 `recordings/config.json`，由程序自己维护。

如果要把管理页面暴露到局域网，请参考官方文档配置 `BREC_HTTP_BASIC_USER` / `BREC_HTTP_BASIC_PASS`，或在 `--bind` 中使用 `http://*:2356` 并配合 `BREC_HTTP_OPEN_ACCESS`。

## 运行产物

| 路径 | 说明 | 是否可删 |
|---|---|---|
| `run/recorder.pid` | 进程 PID | 可，脚本会自动重建 |
| `run/start.lock` | 启动锁 | 可 |
| `logs/recorder.log` | 控制台输出日志 | 可，超过 `LOG_MAX_MB` 自动轮转 |
| `logs/recorder.err.log` | 仅 Windows：标准错误输出 | 可，同样参与轮转 |
| `BililiveRecorder-CLI-*/logs/` | 程序自身 Serilog 日志 | 排查问题用，**不要删** |

## 打包

```bash
./pack.sh            # 自用版 tar.gz（含 cookie）
./pack.sh --public   # 公开版 tar.gz（不含 cookie）
```

```powershell
.\pack.ps1           # 自用版 zip（含 cookie）
.\pack.ps1 --public  # 公开版 zip（不含 cookie）
```

两个脚本都会自动排除程序本体、录制视频、`run/`、`logs/`、`dist/`、`.trae/` 和打包脚本自身，并在打包后逐项校验。

## 常见问题

**启动报「未找到可用的程序本体」**
把对应平台的压缩包解压到项目根目录，目录名保持 `BililiveRecorder-CLI-<平台>-<架构>`；或设置 `BREC_BIN` 指向可执行文件。脚本会把扫描到的目录列出来，便于排查。

**Windows 提示「无法加载文件，因为在此系统上禁止运行脚本」**
执行 `Unblock-File .\*.ps1`，或按文档用 `powershell -ExecutionPolicy Bypass -File .\start.ps1` 运行。

**macOS 提示无法验证开发者**
执行 `xattr -dr com.apple.quarantine BililiveRecorder-CLI-osx-*`。

**启动报「已经在运行」但实际没有进程**
PID 文件里是已被复用的 PID；脚本会校验进程身份，通常会自动忽略。仍异常时删除 `run/recorder.pid` 后重试。

**启动后 HTTP 检测失败**
看 `logs/recorder.log`（Windows 另外看 `logs/recorder.err.log`），常见原因：端口 2356 被占、`config.json` 格式损坏、cookie 过期。

**换了程序版本后录不了**
确认新版本目录结构没变，且 `config.json` 兼容。升级前备份 `recordings/config.json`。

**想开机自启**
本脚本包不提供服务化配置。Linux 可自行编写 systemd unit（`ExecStart=<项目目录>/start.sh -b` 不推荐，建议直接让 systemd 托管 `BililiveRecorder.Cli run ...`）；Windows 可用「任务计划程序」调用 `start.ps1 -Background`。

## 许可证

本仓库脚本采用 [MIT License](LICENSE)，Copyright (c) 2026 vers123。

BililiveRecorder 程序本体为其原作者所有，遵循其自身许可证（GPL-3.0），与本脚本包相互独立，本包仅通过命令行调用程序，不包含、不修改程序代码。
