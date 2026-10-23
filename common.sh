#!/usr/bin/env bash
# 公共配置与函数，仅供 start/stop/status/restart 通过 source 加载
# 不要直接执行本文件

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR" || exit 1

BIND="http://localhost:2356"
WORKDIR="$ROOT_DIR/recordings"

RUN_DIR="$ROOT_DIR/run"
LOG_DIR="$ROOT_DIR/logs"
PIDFILE="$RUN_DIR/recorder.pid"
LOCKFILE="$RUN_DIR/start.lock"
LOG="$LOG_DIR/recorder.log"

COOKIE_FILE="$ROOT_DIR/cookie/bilibili.txt"
CONFIG_JSON="$WORKDIR/config.json"

LOG_MAX_MB=100        # 日志超过此大小，启动时自动轮转
STOP_TIMEOUT=15       # 优雅停止最长等待秒数（录制收尾需要时间）

mkdir -p "$RUN_DIR" "$LOG_DIR"

# ---------- 平台探测 ----------

OS=""
ARCH=""
detect_platform() {
  case "$(uname -s 2>/dev/null)" in
    Linux)  OS=linux ;;
    Darwin) OS=osx ;;
    *)      OS=unknown ;;
  esac
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64)  ARCH=x64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    armv7l|armv6l) ARCH=arm ;;
    *)             ARCH="$(uname -m 2>/dev/null || echo unknown)" ;;
  esac
}

# ---------- 程序本体自动探测 ----------
# 规则：扫描 BililiveRecorder-CLI-* 目录，「平台+架构精确匹配」优先，
#       其次同平台任意架构包，最后 any 版（需要 dotnet）。
# 可用 BREC_BIN 显式指定可执行文件或 dll。

BIN=""                 # 展示用路径（原生二进制或 dll）
BIN_CMD=()             # 实际启动器数组
BIN_KIND=""            # native | dotnet
BIN_ERROR=""           # 探测失败原因

_bin_score() {
  # $1 目录名；不匹配当前平台/架构时返回 0
  local name="$1" score=0
  case "$name" in
    *-x64|*-x64-*|*-musl-x64) [ "$ARCH" = "x64" ]   || { echo 0; return 0; } ;;
    *-arm64|*-arm64-*)        [ "$ARCH" = "arm64" ] || { echo 0; return 0; } ;;
    *-arm|*-arm-*)            [ "$ARCH" = "arm" ]   || { echo 0; return 0; } ;;
  esac
  case "$OS" in
    linux)
      case "$name" in
        *linux-musl-*)      score=80 ;;
        *linux-"$ARCH")     score=100 ;;
        *linux*)            score=50 ;;
        *any*)              score=10 ;;
        *)                  score=0 ;;
      esac
      ;;
    osx)
      case "$name" in
        *osx-"$ARCH")       score=100 ;;
        *osx*)              score=50 ;;
        *any*)              score=10 ;;
        *)                  score=0 ;;
      esac
      ;;
    *)
      case "$name" in
        *any*)              score=10 ;;
        *)                  score=0 ;;
      esac
      ;;
  esac
  echo "$score"
}

detect_bin() {
  local quiet="${1:-0}"
  local d name score best_dir="" best_score=-1 best_kind=""
  local exe dll found=""

  BIN=""
  BIN_CMD=()
  BIN_KIND=""
  BIN_ERROR=""

  # 1. 显式指定优先
  if [ -n "${BREC_BIN:-}" ]; then
    if [ ! -f "$BREC_BIN" ]; then
      BIN_ERROR="错误：BREC_BIN 指向的文件不存在：$BREC_BIN"
      [ "$quiet" = "1" ] || echo "$BIN_ERROR" >&2
      return 1
    fi
    case "$BREC_BIN" in
      *.dll)
        if ! command -v dotnet >/dev/null 2>&1; then
          BIN_ERROR="错误：BREC_BIN 指向 any 版 dll，但 PATH 中没有 dotnet"
          [ "$quiet" = "1" ] || echo "$BIN_ERROR" >&2
          return 1
        fi
        BIN_KIND=dotnet
        BIN="$BREC_BIN"
        BIN_CMD=(dotnet "$BREC_BIN")
        ;;
      *)
        if [ ! -x "$BREC_BIN" ]; then
          BIN_ERROR="错误：BREC_BIN 没有执行权限：$BREC_BIN"
          [ "$quiet" = "1" ] || echo "$BIN_ERROR" >&2
          return 1
        fi
        BIN_KIND=native
        BIN="$BREC_BIN"
        BIN_CMD=("$BREC_BIN")
        ;;
    esac
    return 0
  fi

  # 2. 扫描项目根目录下的程序目录
  for d in "$ROOT_DIR"/BililiveRecorder-CLI-*; do
    [ -d "$d" ] || continue
    name="${d##*/}"
    score=$(_bin_score "$name")
    [ "$score" -gt 0 ] || continue

    exe="$d/BililiveRecorder.Cli"
    dll="$d/BililiveRecorder.Cli.dll"
    found="${found}  $name"$'\n'

    if [ "$OS" != "unknown" ] && [ -f "$exe" ] && [ -x "$exe" ]; then
      if [ "$score" -gt "$best_score" ]; then
        best_dir="$d"; best_score=$score; best_kind=native
      fi
    elif [ -f "$dll" ] && command -v dotnet >/dev/null 2>&1; then
      if [ "$score" -gt "$best_score" ]; then
        best_dir="$d"; best_score=$score; best_kind=dotnet
      fi
    fi
  done

  if [ -z "$best_dir" ]; then
    BIN_ERROR="错误：未找到可用的 BililiveRecorder 程序本体（当前平台：${OS}/${ARCH}）"
    [ -n "$found" ] && BIN_ERROR="${BIN_ERROR}"$'\n'"已找到的目录："$'\n'"${found}"
    BIN_ERROR="${BIN_ERROR}"$'\n'"请从 https://github.com/BililiveRecorder/BililiveRecorder/releases 下载对应平台的压缩包，解压到本目录，"
    BIN_ERROR="${BIN_ERROR}"$'\n'"目录名保持 BililiveRecorder-CLI-<平台>-<架构>（如 BililiveRecorder-CLI-linux-x64、BililiveRecorder-CLI-osx-arm64）。"
    [ "$quiet" = "1" ] || printf '%s\n' "$BIN_ERROR" >&2
    return 1
  fi

  if [ "$best_kind" = "native" ]; then
    BIN="$best_dir/BililiveRecorder.Cli"
    BIN_CMD=("$BIN")
  else
    BIN="$best_dir/BililiveRecorder.Cli.dll"
    BIN_CMD=(dotnet "$BIN")
  fi
  BIN_KIND="$best_kind"
  return 0
}

# pgrep 匹配模式：兼容原生二进制与 dotnet any 版，以及绝对/相对路径启动
BIN_PATTERN='BililiveRecorder\.Cli(\.dll)? run'

# 统一获取 PID：PID 文件优先，pgrep / ps 兜底
get_pid() {
  local p
  if [ -f "$PIDFILE" ]; then
    p=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
      echo "$p"
      return 0
    fi
  fi
  if command -v pgrep >/dev/null 2>&1; then
    p=$(pgrep -f "$BIN_PATTERN" 2>/dev/null | head -n1)
  else
    p=$(ps -eo pid=,args= 2>/dev/null | awk -v pat="$BIN_PATTERN" '$0 ~ pat { print $1; exit }')
  fi
  if [ -n "$p" ]; then
    echo "$p"
    return 0
  fi
  return 1
}

is_running() { get_pid >/dev/null 2>&1; }

# 监听地址可能是通配形式（http://*:2356、http://0.0.0.0:2356、http://[::]:2356），
# 本机探测时要换成 localhost
http_check_url() {
  printf '%s' "$BIND" | sed -E 's#(://)(\*|0\.0\.0\.0|\[::\])(:)#\1localhost\3#'
}

# 返回 HTTP 状态码；未安装 curl 时返回 nocurl
http_code() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "nocurl"
    return
  fi
  local code url
  url=$(http_check_url)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null)
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

# ---------- Cookie 导入 ----------
# 只接受 Cookie Editor 的 Header String（即 Cookie 请求头原文）：
#   SESSDATA=xxx; bili_jct=yyy; buvid3=zzz

COOKIE_ERROR=""
COOKIE_VALUE=""

cookie_item_count() {
  printf '%s' "$1" | awk -F';' '{ n = 0; for (i = 1; i <= NF; i++) if ($i ~ /=/) n++; print n }'
}

# 规范化 cookie 文件内容；成功时写入 COOKIE_VALUE，失败时设置 COOKIE_ERROR
normalize_cookie() {
  local file="$1" content line out="" net

  COOKIE_ERROR=""
  COOKIE_VALUE=""

  if [ ! -f "$file" ]; then
    COOKIE_ERROR="cookie 文件不存在：$file"
    return 1
  fi

  # 去掉 UTF-8 BOM 与 CR
  if [ "$(head -c 3 "$file" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "efbbbf" ]; then
    content=$(tail -c +4 "$file")
  else
    content=$(cat "$file")
  fi
  content=$(printf '%s' "$content" | tr -d '\r')
  content=$(printf '%s' "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  if [ -z "$content" ]; then
    COOKIE_ERROR="cookie 文件为空：$file"
    return 1
  fi

  case "$content" in
    \[*|\{*)
      COOKIE_ERROR="检测到 JSON 格式；请在 Cookie Editor 中改选 Header String 导出后覆盖 $file"
      return 1
      ;;
  esac

  if printf '%s' "$content" | grep -q 'Netscape HTTP Cookie File'; then
    COOKIE_ERROR="检测到 Netscape 格式；请在 Cookie Editor 中改选 Header String 导出后覆盖 $file"
    return 1
  fi

  net=$(printf '%s\n' "$content" | awk -F'\t' 'NF >= 7 { print "yes"; exit }')
  if [ -n "$net" ]; then
    COOKIE_ERROR="检测到 Netscape 格式（制表符分隔）；请在 Cookie Editor 中改选 Header String 导出后覆盖 $file"
    return 1
  fi

  # 去掉可选的 "Cookie:" 前缀
  content=$(printf '%s' "$content" | sed -E 's/^[Cc][Oo][Oo][Kk][Ii][Ee]:[[:space:]]*//')

  # 多行合并为一行
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$line" ] || continue
    if [ -z "$out" ]; then
      out="$line"
    else
      out="$out; $line"
    fi
  done <<EOF
$content
EOF

  # 按分号拆分，逐项去空白、丢弃空项，再用 "; " 重新拼接
  out=$(printf '%s' "$out" | awk -F';' '{
    buf = "";
    for (i = 1; i <= NF; i++) {
      item = $i;
      gsub(/^[ \t]+|[ \t]+$/, "", item);
      if (item == "") continue;
      buf = (buf == "" ? item : buf "; " item);
    }
    print buf;
  }')

  if printf '%s' "$out" | LC_ALL=C grep -q '["\\]'; then
    COOKIE_ERROR="cookie 中不允许出现双引号或反斜杠"
    return 1
  fi

  if printf '%s' "$out" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    COOKIE_ERROR="cookie 中包含控制字符（制表符或换行）"
    return 1
  fi

  if ! printf '%s' "$out" | grep -qE '(^|;[[:space:]]*)[^=;[:space:]]+='; then
    COOKIE_ERROR="cookie 格式不正确：未找到 name=value"
    return 1
  fi

  COOKIE_VALUE="$out"
  return 0
}

# 把 cookie 写入 recordings/config.json 的 global.Cookie
# 返回：0 成功；1 写入/校验失败；2 没有可用的 JSON 处理工具
config_set_cookie() {
  local cookie="$1"
  local backup="${CONFIG_JSON}.bak"
  local tmp backend="" rc=0

  if command -v jq >/dev/null 2>&1; then
    backend=jq
  elif command -v python3 >/dev/null 2>&1; then
    backend=python3
  elif command -v python >/dev/null 2>&1; then
    backend=python
  elif command -v perl >/dev/null 2>&1; then
    backend=perl
  else
    COOKIE_ERROR="未安装 jq / python3 / perl，无法自动写入 config.json"
    return 2
  fi

  mkdir -p "$(dirname "$CONFIG_JSON")"
  [ -f "$CONFIG_JSON" ] && cp -f "$CONFIG_JSON" "$backup" 2>/dev/null

  tmp=$(mktemp "${CONFIG_JSON}.XXXXXX" 2>/dev/null) || tmp="${CONFIG_JSON}.tmp"

  case "$backend" in
    jq)
      if [ -f "$CONFIG_JSON" ]; then
        jq -c --arg c "$cookie" '.global = (.global // {}) | .global.Cookie = {HasValue: true, Value: $c}' \
          "$CONFIG_JSON" > "$tmp" 2>/dev/null
      else
        printf '%s' '{"version":3,"global":{},"rooms":[]}' \
          | jq -c --arg c "$cookie" '.global.Cookie = {HasValue: true, Value: $c}' > "$tmp" 2>/dev/null
      fi
      rc=$?
      if [ "$rc" -eq 0 ]; then
        jq -e --arg c "$cookie" '.global.Cookie.Value == $c' "$tmp" >/dev/null 2>&1
        rc=$?
      fi
      ;;
    python3|python)
      "$backend" - "$CONFIG_JSON" "$cookie" "$tmp" 2>/dev/null <<'PY'
import json
import sys

path, cookie, out = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
except FileNotFoundError:
    data = {'version': 3, 'global': {}, 'rooms': []}
if not isinstance(data.get('global'), dict):
    data['global'] = {}
data['global']['Cookie'] = {'HasValue': True, 'Value': cookie}
with open(out, 'w', encoding='utf-8', newline='') as f:
    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
PY
      rc=$?
      if [ "$rc" -eq 0 ]; then
        "$backend" - "$tmp" "$cookie" 2>/dev/null <<'PY'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)
value = data.get('global', {}).get('Cookie', {}).get('Value')
sys.exit(0 if value == sys.argv[2] else 1)
PY
        rc=$?
      fi
      ;;
    perl)
      perl -MJSON::PP - "$CONFIG_JSON" "$cookie" "$tmp" 2>/dev/null <<'PL'
use strict;
use warnings;
use JSON::PP;

my ($path, $cookie, $out) = @ARGV;
my $data;
if (-e $path) {
    open my $fh, '<:encoding(UTF-8)', $path or exit 1;
    local $/;
    my $json = <$fh>;
    close $fh;
    $data = JSON::PP->new->utf8(0)->decode($json);
} else {
    $data = { version => 3, global => {}, rooms => [] };
}
$data->{global} = {} unless ref($data->{global}) eq 'HASH';
$data->{global}{Cookie} = { HasValue => JSON::PP::true, Value => $cookie };
open my $o, '>:encoding(UTF-8)', $out or exit 1;
print $o JSON::PP->new->utf8(0)->encode($data);
close $o;
exit 0;
PL
      rc=$?
      if [ "$rc" -eq 0 ]; then
        perl -MJSON::PP - "$tmp" "$cookie" 2>/dev/null <<'PL'
use strict;
use warnings;
use JSON::PP;

open my $fh, '<:encoding(UTF-8)', $ARGV[0] or exit 1;
local $/;
my $json = <$fh>;
close $fh;
my $data = JSON::PP->new->utf8(0)->decode($json);
my $value = $data->{global}{Cookie}{Value} // '';
exit($value eq $ARGV[1] ? 0 : 1);
PL
        rc=$?
      fi
      ;;
  esac

  if [ "$rc" -ne 0 ] || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    COOKIE_ERROR="写入 config.json 失败（配置文件可能不是合法 JSON）"
    return 1
  fi

  if ! mv -f "$tmp" "$CONFIG_JSON" 2>/dev/null; then
    rm -f "$tmp"
    COOKIE_ERROR="无法写入 $CONFIG_JSON"
    return 1
  fi
  chmod 600 "$CONFIG_JSON" 2>/dev/null || true
  return 0
}

# 启动前处理 cookie：检测文件 -> 询问 -> 写入或提示手动填写
maybe_apply_cookie() {
  [ -f "$COOKIE_FILE" ] || return 0

  local cookie count sess answer

  if ! normalize_cookie "$COOKIE_FILE"; then
    echo "cookie 未导入：$COOKIE_ERROR"
    echo "可继续启动，稍后在 Web 界面手动填写：$(http_check_url)"
    return 0
  fi
  cookie="$COOKIE_VALUE"

  count=$(cookie_item_count "$cookie")
  case "$cookie" in
    *SESSDATA=*) sess="包含 SESSDATA" ;;
    *)           sess="未包含 SESSDATA" ;;
  esac

  echo "检测到 cookie：$COOKIE_FILE（${count} 项，${sess}）"

  if [ -t 0 ]; then
    echo "  1) 自动写入 recordings/config.json（推荐）"
    echo "  2) 我自己填写（启动后在 Web 界面设置）"
    read -r -p "选择 [1]: " answer
    answer="${answer:-1}"
  else
    answer=1
    echo "非交互模式：自动写入 recordings/config.json"
  fi

  case "$answer" in
    1)
      if config_set_cookie "$cookie"; then
        echo "Cookie 已写入 $CONFIG_JSON"
      else
        echo "Cookie 写入失败：$COOKIE_ERROR"
        echo "请在 Web 界面手动填写：$(http_check_url)"
      fi
      ;;
    2)
      echo "已跳过自动填写。启动后访问 $(http_check_url) → 设置 → 全局 → Cookie 粘贴并保存。"
      ;;
    *)
      echo "无效选择：$answer（将跳过自动填写）"
      ;;
  esac

  return 0
}

detect_platform
# status.sh 允许在没有程序本体时继续展示状态，因此这里不直接退出
detect_bin 1 || true
