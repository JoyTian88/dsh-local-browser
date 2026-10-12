#!/bin/bash
# dsh-local-browser 自检：逐项检查这条通道的每个环节，并给出下一步动作。
set -uo pipefail

PORT="${DSH_CB_PORT:-9333}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="${DSH_PROFILE:-desktop}"
CB_DIR="$DSH_HOME/chrome-debug"
PATCH="$DSH_HOME/profiles/$PROFILE/cordis.patch.yml"
AGENTS="$DSH_HOME/AGENTS.md"
SKILL="$DSH_HOME/skills/local-browser/SKILL.md"

ok=0; bad=0
pass() { printf '  [ OK ] %s\n' "$1"; ok=$((ok+1)); }
fail() { printf '  [FAIL] %s\n         → %s\n' "$1" "$2"; bad=$((bad+1)); }

echo "dsh-local-browser 自检（profile=$PROFILE, port=$PORT）"

[ "$(uname -s)" = "Darwin" ] && pass "macOS" || fail "非 macOS" "本方案只支持 macOS"
[ -d "/Applications/Google Chrome.app" ] && pass "Google Chrome 已安装" || fail "没找到 Google Chrome" "安装 Chrome"

# 1. MCP server 包
ENTRY="$(grep -A3 'args:' "$PATCH" 2>/dev/null | grep -m1 'chrome-devtools-mcp.js' | sed 's/^[- ]*//')"
if [ -n "$ENTRY" ] && [ -f "$ENTRY" ]; then
  pass "MCP server 入口存在：$ENTRY"
else
  fail "MCP server 入口缺失（$ENTRY）" "重跑 install.sh"
fi

# 2. profile 受管块
if grep -q '# >>> dsh-local-browser >>>' "$PATCH" 2>/dev/null; then
  pass "profile 受管块已写入：$PATCH"
  if grep -q 'mcp-chrome-devtools' "$PATCH"; then
    pass "mcp-chrome-devtools 条目存在"
  else
    fail "受管块里没有 mcp-chrome-devtools" "重跑 install.sh"
  fi
  NODE_PATH="$(grep -A2 '^        command:' "$PATCH" | head -1 | sed 's/.*command: *//')"
  if [ -n "$NODE_PATH" ] && [ -x "$NODE_PATH" ]; then
    pass "MCP command 指向可执行 node：$NODE_PATH"
  else
    fail "MCP command 的 node 不可执行：$NODE_PATH" "重跑 install.sh 重新探测 node"
  fi
else
  fail "profile 里没有受管块" "重跑 install.sh"
fi

# 3. AGENTS.md / skill
grep -q '>>> dsh-local-browser >>>' "$AGENTS" 2>/dev/null \
  && pass "AGENTS.md 受管块已写入" || fail "AGENTS.md 缺少受管块" "重跑 install.sh"
[ -f "$SKILL" ] && pass "skill 已安装：$SKILL" || fail "skill 未安装" "重跑 install.sh"

# 4. 脚本
[ -x "$CB_DIR/start.sh" ] && pass "start.sh 可执行" || fail "start.sh 缺失" "重跑 install.sh"
[ -x "$CB_DIR/sync.sh" ]  && pass "sync.sh 可执行"  || fail "sync.sh 缺失"  "重跑 install.sh"

# 5. 登录态快照
if [ -f "$CB_DIR/Default/Cookies" ]; then
  n="$(sqlite3 "$CB_DIR/Default/Cookies" 'select count(distinct host_key) from cookies;' 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt 0 ] && pass "登录态快照：$n 个域" || fail "登录态快照为空" "退出调试 Chrome 后跑 $CB_DIR/sync.sh"
else
  fail "没有登录态快照" "跑 $CB_DIR/sync.sh（会从主 Chrome 复制）"
fi

# 6. 调试 Chrome 在跑吗
if curl -sS --noproxy '*' --max-time 3 "http://127.0.0.1:$PORT/json/version" 2>/dev/null | grep -q webSocketDebuggerUrl; then
  pass "CDP 端点在线：http://127.0.0.1:$PORT"
else
  fail "CDP 端点不可达" "执行 $CB_DIR/start.sh"
fi

echo ""
echo "通过 $ok 项，失败 $bad 项"
if [ "$bad" -eq 0 ]; then
  echo "通道正常。若 DSH 里仍看不到 mcp__chrome-devtools__* 工具，重启 DeepSeek Harness。"
else
  echo "先按上面 → 的提示处理，再把本文件贴给 DSH。"
fi
exit 0
