#!/bin/bash
# 启动带 CDP 调试端口的 Chrome（独立 profile）。
# 登录态来自主 Chrome 的快照：用 sync.sh 刷新。
#
# 注意 1：不要用 9222。主 Chrome 打开 chrome://inspect#remote-debugging 后会占用
#         9222，但那是它自己的授权握手端口（/json/version 返回 404），不是标准 CDP 端点。
# 注意 2：用 `open -na` 让 launchd 托管这个实例，DSH 重启/退出不会把它带走。
set -euo pipefail

PORT="${DSH_CB_PORT:-9333}"
DIR="${DSH_CB_DIR:-$HOME/.dsh/chrome-debug}"

if curl -sS --noproxy '*' --max-time 2 "http://127.0.0.1:$PORT/json/version" 2>/dev/null | grep -q webSocketDebuggerUrl; then
  echo "already running on $PORT"
  exit 0
fi

open -na "Google Chrome" --args \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$DIR" \
  --no-first-run \
  --no-default-browser-check \
  --disable-features=Translate

for _ in $(seq 1 30); do
  if curl -sS --noproxy '*' --max-time 2 "http://127.0.0.1:$PORT/json/version" 2>/dev/null | grep -q webSocketDebuggerUrl; then
    echo "started on $PORT"
    exit 0
  fi
  sleep 1
done

echo "启动超时：$PORT 上没有 CDP 端点" >&2
exit 1
