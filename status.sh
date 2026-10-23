#!/usr/bin/env bash
set -u
set -o pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

pid=$(get_pid || true)

echo "==================== BililiveRecorder 状态 ===================="
if [ -n "$pid" ]; then
  echo "运行状态 : 正在运行 ✅"
  echo "PID      : $pid"
  if ps -p "$pid" >/dev/null 2>&1; then
    ps -p "$pid" -o pid=,ppid=,etime=,%cpu=,%mem=,rss=,args= 2>/dev/null \
      | sed 's/^/  /'
  fi
else
  echo "运行状态 : 未运行 ❌"
fi

echo "--------------------------------------------------------------"
echo "监听地址 : $BIND"
echo "工作目录 : $WORKDIR"
echo "日志文件 : $LOG"
echo "PID 文件 : $PIDFILE"
echo "--------------------------------------------------------------"

code=$(http_code)
case "$code" in
  nocurl) echo "HTTP 检测: 未安装 curl，跳过" ;;
  000|"") echo "HTTP 检测: 无法访问 ❌" ;;
  *)      echo "HTTP 检测: 可访问（HTTP $code）✅" ;;
esac

echo "--------------------------------------------------------------"
if [ -d "$WORKDIR" ]; then
  size=$(du -sh "$WORKDIR" 2>/dev/null | cut -f1)
  echo "录制占用 : ${size:-未知}"
fi
df_line=$(df -h "$WORKDIR" 2>/dev/null | awk 'NR==2{print $4" 可用 / "$2"（已用 "$5"）"}')
[ -n "$df_line" ] && echo "磁盘剩余 : $df_line"

echo "--------------------------------------------------------------"
if [ -f "$LOG" ]; then
  echo "最近 10 行日志（$LOG）："
  log_tail 10
else
  echo "日志文件不存在：$LOG"
fi
echo "=============================================================="

[ -n "$pid" ] && exit 0 || exit 1
