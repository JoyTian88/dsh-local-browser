#!/bin/bash
# dsh-local-browser 安装器（幂等，可重复执行）。
#
# 作用：让 DSH 能读需要登录 / 被风控 / 强 JS 渲染的网页（微信、知乎、小红书、内网等），
# 走本机 Chrome 的真实登录态 + 本机 IP。
#
# 它做 7 件事：
#   1. 把 chrome-devtools-mcp 装到 $DSH_HOME/mcp
#   2. 在 profile 的 cordis.patch.yml 里维护一段受管块（插入 mcp-chrome-devtools）
#   3. 把 start.sh / sync.sh 放到 $DSH_HOME/chrome-debug/
#   4. 首次安装时从主 Chrome 复制登录态到调试 profile
#   5. 在 $DSH_HOME/AGENTS.md 里维护一段受管块（取网页链接的固定流程）
#   6. 把 local-browser skill 链接到 $DSH_HOME/skills/
#   7. 拉起调试 Chrome 并自检
#
# 用法：
#   bash install.sh                 # 默认 desktop profile
#   bash install.sh --profile web   # 换 profile
set -euo pipefail

MCP_PKG="chrome-devtools-mcp@1.10.1"
PORT="${DSH_CB_PORT:-9333}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="desktop"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CB_DIR="$DSH_HOME/chrome-debug"
MCP_ROOT="$DSH_HOME/mcp"

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?--profile 需要值}"; shift 2 ;;
    --port)    PORT="${2:?--port 需要值}"; shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "本安装器只支持 macOS（其他系统请照着 README 手动做）"
[ -d "/Applications/Google Chrome.app" ] || die "没找到 Google Chrome"
[ -d "$DSH_HOME/profiles/$PROFILE" ] || die "找不到 profile：$DSH_HOME/profiles/$PROFILE"

# ---- 1. 选一个绝对路径可用的 node（DSH GUI 进程的 PATH 只有 /usr/bin:/bin，必须写死绝对路径）----
NODE=""
for c in /opt/homebrew/bin/node /usr/local/bin/node; do
  [ -x "$c" ] && { NODE="$c"; break; }
done
if [ -z "$NODE" ]; then
  c="$(command -v node || true)"
  [ -n "$c" ] && NODE="$c"
fi
[ -n "$NODE" ] || die "找不到 node，请先装 Node.js（brew install node）"
NODE_DIR="$(cd "$(dirname "$NODE")" && pwd)"
say "node: $NODE ($("$NODE" -v))"

NPM=""
for c in "$NODE_DIR/npm" /opt/homebrew/bin/npm /usr/local/bin/npm; do
  [ -f "$c" ] && { NPM="$c"; break; }
done
[ -n "$NPM" ] || die "找不到 npm（应与 node 同目录）"

# ---- 2. 安装 MCP server 包 ----
MCP_ENTRY="$MCP_ROOT/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js"
if [ -f "$MCP_ENTRY" ]; then
  say "MCP server 已存在，跳过安装：$MCP_ENTRY"
else
  say "安装 $MCP_PKG 到 $MCP_ROOT ..."
  mkdir -p "$MCP_ROOT"
  "$NODE" "$NPM" install --prefix "$MCP_ROOT" --no-audit --no-fund "$MCP_PKG" >/dev/null
  [ -f "$MCP_ENTRY" ] || die "安装后找不到入口：$MCP_ENTRY"
fi

# ---- 3. 维护 profile 的受管块 ----
PATCH="$DSH_HOME/profiles/$PROFILE/cordis.patch.yml"
[ -f "$PATCH" ] || die "找不到 $PATCH"

DSH_LB_NODE="$NODE" DSH_LB_ENTRY="$MCP_ENTRY" DSH_LB_PORT="$PORT" DSH_LB_PATCH="$PATCH" \
python3 - <<'PY'
import os, shutil, sys, time

patch = os.environ['DSH_LB_PATCH']
node = os.environ['DSH_LB_NODE']
entry = os.environ['DSH_LB_ENTRY']
port = os.environ['DSH_LB_PORT']

BEGIN = '# >>> dsh-local-browser >>>'
END = '# <<< dsh-local-browser <<<'

with open(patch, encoding='utf-8') as f:
    original = f.read()
lines = original.split('\n')

# 去掉旧的受管块
out, skipping = [], False
for ln in lines:
    if ln.strip() == BEGIN:
        skipping = True
        continue
    if skipping:
        if ln.strip() == END:
            skipping = False
        continue
    out.append(ln)

# 去掉手工加过的同 id 条目（不是受管块时），避免重复注册同一个 MCP server
cleaned, i = [], 0
while i < len(out):
    if out[i].startswith('- insert:'):
        j = i + 1
        while j < len(out) and not out[j].startswith('- ') and out[j].strip() != '':
            j += 1
        block = out[i:j]
        if any('mcp-chrome-devtools' in b for b in block):
            sys.stderr.write('已移除手工添加的 mcp-chrome-devtools 条目\n')
            i = j
            continue
    cleaned.append(out[i])
    i += 1

while cleaned and cleaned[-1].strip() == '':
    cleaned.pop()

block = f'''{BEGIN}
- insert:
    - id: mcp-chrome-devtools
      name: "@deepseek-ai/dsh-mcp-client"
      config:
        serverName: chrome-devtools
        transport: stdio
        command: {node}
        args:
          - {entry}
          - --browserUrl=http://127.0.0.1:{port}
          - --slim
          - --no-usage-statistics
        env:
          PATH: {os.path.dirname(node)}:/usr/bin:/bin
        toolCallTimeoutMs: 150000
{END}'''

updated = '\n'.join(cleaned) + '\n' + block + '\n'

if updated == original:
    print(f'受管块无变化：{patch}')
elif os.path.exists(patch):
    shutil.copy2(patch, f'{patch}.bak-localbrowser-{time.strftime("%Y%m%d-%H%M%S")}')
    with open(patch, 'w', encoding='utf-8') as f:
        f.write(updated)
    print(f'已更新受管块：{patch}')
else:
    with open(patch, 'w', encoding='utf-8') as f:
        f.write(updated)
    print(f'已写入受管块：{patch}')
PY

# ---- 4. 脚本落到 $DSH_HOME/chrome-debug ----
mkdir -p "$CB_DIR"
install -m 700 "$REPO_DIR/scripts/start.sh" "$CB_DIR/start.sh"
install -m 700 "$REPO_DIR/scripts/sync.sh"  "$CB_DIR/sync.sh"
say "已安装脚本：$CB_DIR/start.sh、$CB_DIR/sync.sh"

# ---- 5. 首次安装时复制登录态（已存在则不覆盖，避免抹掉用户在调试窗口里的新登录）----
if [ ! -f "$CB_DIR/Default/Cookies" ]; then
  say "首次安装：从主 Chrome 复制登录态 ..."
  "$CB_DIR/sync.sh" || die "复制登录态失败（请确认主 Chrome 已登录过目标站点）"
else
  say "调试 profile 已存在，保留现有登录态（要刷新请先退出调试 Chrome 再跑 $CB_DIR/sync.sh）"
fi

# ---- 6. 维护 AGENTS.md 的受管块 ----
AGENTS="$DSH_HOME/AGENTS.md"
[ -f "$AGENTS" ] || : > "$AGENTS"

DSH_LB_AGENTS="$AGENTS" DSH_LB_CB="$CB_DIR" python3 - <<'PY'
import os, shutil, time

path = os.environ['DSH_LB_AGENTS']
cb = os.environ['DSH_LB_CB']
BEGIN = '<!-- >>> dsh-local-browser >>> -->'
END = '<!-- <<< dsh-local-browser <<< -->'

with open(path, encoding='utf-8') as f:
    lines = f.read().split('\n')

out, skipping = [], False
for ln in lines:
    if ln.strip() == BEGIN:
        skipping = True
        continue
    if skipping:
        if ln.strip() == END:
            skipping = False
        continue
    out.append(ln)

# 去掉之前手工写的同名小节（到下一个二级标题为止）
cleaned, skipping_section = [], False
for ln in out:
    if ln.strip() == '## 取网页链接':
        skipping_section = True
        continue
    if skipping_section:
        if ln.startswith('## '):
            skipping_section = False
        else:
            continue
    cleaned.append(ln)

while cleaned and cleaned[-1].strip() == '':
    cleaned.pop()

block = f'''{BEGIN}
## 取网页链接

给到链接或要求读某页面时，按下列顺序取；某一级失败一次就换下一级，不要反复重试同一级。

1. 公开页面 → `web_fetch`；多 URL 并行 → `mcp__tinyfish__fetch_content`。
2. 需要登录 / 被风控（验证码、「环境异常」）/ 强 JS 渲染 / 上一级失败 →
   `mcp__chrome-devtools__navigate` 打开链接，再 `mcp__chrome-devtools__evaluate` 取
   `document.body.innerText`（正文）或 `document.documentElement.outerHTML`（结构）。
   这一级用的是本机 Chrome 的登录态快照与本机 IP，微信、知乎、小红书等走这里。
   - 后端是一个**专用调试 Chrome**（独立 profile）。工具报 `Could not connect to Chrome` 时，
     先执行 `{cb}/start.sh` 再重试。
   - 页面要求重新登录（登录态过期）：让用户执行 `{cb}/sync.sh`
     刷新（需先退出调试 Chrome），或让用户直接在调试 Chrome 窗口里登录一次。
   - 若 `navigate` 返回的 URL 变成 `mp.weixin.qq.com/mp/wappoc_appmsgcaptcha?...`，
     说明该链接本身已失效或被微信风控：换一条新链接（`/s/<id>` 形式直链通常正常），
     或在调试 Chrome 窗口里手动过一次验证。
3. 海外站点、需代理、需批量或定时 → `mcp__tinyfish__run_web_automation`。
4. 三级都失败才让用户手动提供内容，并说明卡在哪一级、报什么错。
{END}'''

with open(path, encoding='utf-8') as f:
    original = f.read()

updated = '\n'.join(cleaned) + '\n' + block + '\n'

if updated == original:
    print(f'受管块无变化：{path}')
else:
    if original:
        shutil.copy2(path, f'{path}.bak-localbrowser-{time.strftime("%Y%m%d-%H%M%S")}')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(updated)
    print(f'已更新受管块：{path}')
PY

# ---- 7. 安装 skill ----
SKILL_DIR="$DSH_HOME/skills/local-browser"
mkdir -p "$(dirname "$SKILL_DIR")"
rm -rf "$SKILL_DIR"
mkdir -p "$SKILL_DIR"
sed "s#__CB_DIR__#$CB_DIR#g" "$REPO_DIR/templates/SKILL.md" > "$SKILL_DIR/SKILL.md"
say "已安装 skill：$SKILL_DIR/SKILL.md"

# ---- 8. 拉起调试 Chrome 并自检 ----
"$CB_DIR/start.sh" >/dev/null || true
say ""
bash "$REPO_DIR/doctor.sh" || true
say ""
say "完成。请重启 DeepSeek Harness 让新的 MCP server 生效。"
