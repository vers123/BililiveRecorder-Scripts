#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# 专门存放发布包的目录
DIST_DIR="$PWD/dist"
mkdir -p "$DIST_DIR"

with_cookie=1
suffix="selfuse"
case "${1:-}" in
  --public) with_cookie=0; suffix="public" ;;
  -h|--help|help)
    echo "用法：$0 [--public]"
    echo "  默认     打包为自用版（含 cookie）"
    echo "  --public 打包为公开分发版（不含 cookie）"
    exit 0 ;;
  "") ;;
  *) echo "未知参数：$1"; exit 1 ;;
esac

# 文件名带后缀，彻底防止覆盖
NAME="bilirec-kit-$(date +%Y-%m-%d)-$suffix.tar.gz"
OUT="$DIST_DIR/$NAME"

excludes=(
  --exclude='BililiveRecorder-CLI-*'
  --exclude='recordings/*.flv'
  --exclude='recordings/*.jpg'
  --exclude='run'
  --exclude='logs'
  --exclude='pack.sh'
  --exclude='pack.ps1'
  --exclude='.trae'
  --exclude='.git'
  --exclude='dist'             # 排除 dist 自身，防止套娃
)
[ "$with_cookie" -eq 0 ] && excludes+=(--exclude='cookie')

tar -czf "$OUT" "${excludes[@]}" -C "$(dirname "$PWD")" "$(basename "$PWD")"

# ---- 校验 ----
fail=0
list=$(tar -tzf "$OUT")

echo "$list" | grep -qE '\.(flv|jpg)$'                     && { echo "❌ 混入视频"; fail=1; }
echo "$list" | grep -qE '/(run|logs|dist)/'                 && { echo "❌ 混入 run/logs/dist"; fail=1; }
echo "$list" | grep -qE 'BililiveRecorder-CLI-[^/]+/'       && { echo "❌ 混入程序本体"; fail=1; }
echo "$list" | grep -qE '/pack\.(sh|ps1)$'                  && { echo "❌ 混入打包脚本"; fail=1; }
[ "$with_cookie" -eq 0 ] && echo "$list" | grep -q 'cookie/' && { echo "❌ --public 混入 cookie"; fail=1; }

for f in README.md LICENSE \
         common.sh start.sh stop.sh status.sh restart.sh \
         common.ps1 start.ps1 stop.ps1 status.ps1 restart.ps1; do
  echo "$list" | grep -qE "/$f$" || { echo "❌ 缺少 $f"; fail=1; }
done

echo "--------------------------------------------------------------"
ls -lh "$OUT"
echo "文件数：$(echo "$list" | wc -l)"
[ "$fail" -eq 0 ] && echo "✅ 校验通过：$OUT" || { echo "❌ 校验失败"; exit 1; }
