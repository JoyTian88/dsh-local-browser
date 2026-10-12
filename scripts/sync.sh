#!/bin/bash
# 从主 Chrome 刷新登录态到调试 profile。
# 用法：先完全退出调试 Chrome（不是主 Chrome），再执行本脚本，然后 start.sh。
set -euo pipefail

PORT="${DSH_CB_PORT:-9333}"
DIR="${DSH_CB_DIR:-$HOME/.dsh/chrome-debug}"

case "$(uname -s)" in
  Darwin) SRC="$HOME/Library/Application Support/Google/Chrome" ;;
  Linux)  SRC="$HOME/.config/google-chrome" ;;
  *) echo "不支持的系统：$(uname -s)" >&2; exit 1 ;;
esac

[ -d "$SRC/Default" ] || { echo "找不到主 Chrome profile：$SRC/Default" >&2; exit 1; }

if curl -sS --noproxy '*' --max-time 2 "http://127.0.0.1:$PORT/json/version" 2>/dev/null | grep -q webSocketDebuggerUrl; then
  echo "调试 Chrome 还在运行，请先退出它再执行本脚本" >&2
  exit 1
fi

mkdir -p "$DIR/Default"
sqlite3 "$SRC/Default/Cookies" ".backup '$DIR/Default/Cookies'"
if [ -d "$SRC/Default/Local Storage" ]; then
  rm -rf "$DIR/Default/Local Storage"
  cp -R "$SRC/Default/Local Storage" "$DIR/Default/Local Storage"
fi
echo "已同步：$(sqlite3 "$DIR/Default/Cookies" 'select count(distinct host_key) from cookies;') 个域"
