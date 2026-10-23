#!/usr/bin/env bash
set -u
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<EOF
用法：$0 [-f|--foreground] [-b|--background] [-h]

  -f, --foreground  前台运行（Ctrl+C 停止）
  -b, --background  后台运行（日志：$LOG）
  -h, --help        显示帮助

不带参数时交互式选择。
EOF
}

mode=""
case "${1:-}" in
  -b|--background|bg) mode=bg ;;
  -f|--foreground|fg) mode=fg ;;
  -h|--help|help)     usage; exit 0 ;;
  "")                 ;;
  *) echo "未知参数：$1"; usage; exit 1 ;;
esac

if [ -z "$mode" ]; then
  echo "请选择运行方式："
  echo "  1) 前台运行（Ctrl+C 停止）"
  echo "  2) 后台运行（日志写入 $LOG）"
  read -rp "输入 1 或 2 [默认 1]: " choice
  case "${choice:-1}" in
    1) mode=fg ;;
    2) mode=bg ;;
    *) echo "无效选择：$choice"; exit 1 ;;
  esac
fi

# 程序本体检查（由 common.sh 自动探测）
if [ "${#BIN_CMD[@]}" -eq 0 ]; then
  printf '%s\n' "$BIN_ERROR"
  exit 1
fi

if [ "$BIN_KIND" = "native" ]; then
  if [ ! -x "$BIN" ]; then
    echo "错误：找不到可执行文件 $BIN"
    exit 1
  fi
else
  if ! command -v dotnet >/dev/null 2>&1; then
    echo "错误：any 版需要 dotnet，但 PATH 中没有 dotnet"
    exit 1
  fi
  if [ ! -f "$BIN" ]; then
    echo "错误：找不到程序文件 $BIN"
    exit 1
  fi
fi

# 已在运行则直接退出（PID 文件或进程扫描命中都算）
running_pid=$(get_pid || true)
if [ -n "${running_pid:-}" ]; then
  echo "已经在运行，PID=$running_pid"
  echo "$running_pid" > "$PIDFILE"   # 顺手修复丢失的 PID 文件
  exit 0
fi

# 启动前处理 cookie（自动写入 config.json 或提示手动填写）
maybe_apply_cookie

if [ "$mode" = "fg" ]; then
  echo ">>> 前台运行中，按 Ctrl+C 停止"
  exec "${BIN_CMD[@]}" run --bind "$BIND" "$WORKDIR"
fi

# 后台模式：加锁防止并发双开
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCKFILE"
  if ! flock -n 9; then
    echo "另一个 start.sh 正在执行，请稍后重试"
    exit 1
  fi
fi

# 拿到锁后再查一次，避免竞态
running_pid=$(get_pid || true)
if [ -n "${running_pid:-}" ]; then
  echo "已经在运行，PID=$running_pid"
  exit 0
fi

rotate_log
echo ">>> 后台运行中，日志：$LOG"
nohup "${BIN_CMD[@]}" run --bind "$BIND" "$WORKDIR" > "$LOG" 2>&1 < /dev/null &
pid=$!
echo "$pid" > "$PIDFILE"

# 最多等 10 秒：进程存活且 HTTP 就绪
ready=0
for ((i = 1; i <= 10; i++)); do
  if ! kill -0 "$pid" 2>/dev/null; then
    break
  fi
  code=$(http_code)
  if [ "$code" != "nocurl" ] && [ "$code" != "000" ] && [ -n "$code" ]; then
    ready=1
    break
  fi
  sleep 1
done

if ! kill -0 "$pid" 2>/dev/null; then
  echo "启动失败（进程已退出），最近日志："
  log_tail 20
  rm -f "$PIDFILE"
  exit 1
fi

if [ "$ready" -eq 1 ]; then
  echo "PID=$pid，HTTP 已就绪，停止：./stop.sh"
else
  echo "PID=$pid，进程在运行但 HTTP 尚未响应（可能仍在初始化），日志：$LOG"
fi
