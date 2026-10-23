#!/usr/bin/env bash
set -u
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

force=0
case "${1:-}" in
  -f|--force) force=1 ;;
  -h|--help|help)
    echo "用法：$0 [-f|--force]"
    echo "  -f, --force  直接 SIGKILL（可能损坏未收尾的录制文件）"
    exit 0
    ;;
  "") ;;
  *) echo "未知参数：$1"; exit 1 ;;
esac

pid=$(get_pid || true)
if [ -z "$pid" ]; then
  echo "没有在运行的 BililiveRecorder"
  rm -f "$PIDFILE"
  exit 0
fi

echo "正在停止 PID=$pid ..."

if [ "$force" -eq 1 ]; then
  kill -9 "$pid" 2>/dev/null || true
else
  if ! kill -TERM "$pid" 2>/dev/null; then
    echo "发送 SIGTERM 失败（权限不足？）"
    exit 1
  fi
fi

# 优雅等待
for ((i = 1; i <= STOP_TIMEOUT; i++)); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
  if [ $((i % 5)) -eq 0 ]; then
    echo "  仍在退出中（${i}s）..."
  fi
done

# 超时兜底
if kill -0 "$pid" 2>/dev/null; then
  echo "进程 ${STOP_TIMEOUT}s 内未退出，强制结束（可能影响未收尾的录制）"
  kill -9 "$pid" 2>/dev/null || true
  sleep 1
fi

rm -f "$PIDFILE"

if kill -0 "$pid" 2>/dev/null; then
  echo "停止失败，请手动检查 PID=$pid"
  exit 1
fi

echo "已停止"
