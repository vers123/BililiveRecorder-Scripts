#!/usr/bin/env bash
# 公共配置与函数，仅供 start/stop/status/restart 通过 source 加载
# 不要直接执行本文件

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR" || exit 1

BIN="$ROOT_DIR/BililiveRecorder-CLI-linux/BililiveRecorder.Cli"
BIND="http://localhost:2356"
WORKDIR="$ROOT_DIR/recordings"

RUN_DIR="$ROOT_DIR/run"
LOG_DIR="$ROOT_DIR/logs"
PIDFILE="$RUN_DIR/recorder.pid"
LOCKFILE="$RUN_DIR/start.lock"
LOG="$LOG_DIR/recorder.log"

LOG_MAX_MB=100        # 日志超过此大小，启动时自动轮转
STOP_TIMEOUT=15       # 优雅停止最长等待秒数（录制收尾需要时间）

mkdir -p "$RUN_DIR" "$LOG_DIR"

# pgrep 匹配模式：兼容绝对路径和相对路径启动
BIN_PATTERN='BililiveRecorder\.Cli run'

# 统一获取 PID：PID 文件优先，pgrep 兜底
get_pid() {
  local p
  if [ -f "$PIDFILE" ]; then
    p=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
      echo "$p"
      return 0
    fi
  fi
  p=$(pgrep -f "$BIN_PATTERN" 2>/dev/null | head -n1)
  if [ -n "$p" ]; then
    echo "$p"
    return 0
  fi
  return 1
}

is_running() { get_pid >/dev/null 2>&1; }

# 返回 HTTP 状态码；未安装 curl 时返回 nocurl
http_code() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "nocurl"
    return
  fi
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$BIND" 2>/dev/null)
  echo "${code:-000}"
}

log_tail() { [ -f "$LOG" ] && tail -n "${1:-10}" "$LOG"; }

_fsize() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}

# 日志超过阈值时按时间戳轮转
rotate_log() {
  [ -f "$LOG" ] || return 0
  local size_mb
  size_mb=$(( $(_fsize "$LOG") / 1024 / 1024 ))
  if [ "$size_mb" -ge "$LOG_MAX_MB" ]; then
    mv -f "$LOG" "$LOG.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  fi
}
