#!/bin/bash
# dsh-local-browser 卸载：移除受管块、skill 和脚本，并关掉调试 Chrome。
# 默认保留 $DSH_HOME/mcp 与 $DSH_HOME/chrome-debug（里面是你的登录态快照）；
# 加 --purge 一并删除。
set -euo pipefail

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE="${DSH_PROFILE:-desktop}"
CB_DIR="$DSH_HOME/chrome-debug"
PATCH="$DSH_HOME/profiles/$PROFILE/cordis.patch.yml"
AGENTS="$DSH_HOME/AGENTS.md"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

strip_block() {
  local file="$1" begin="$2" end="$3"
  [ -f "$file" ] || return 0
  cp -p "$file" "$file.bak-uninstall-$(date +%Y%m%d-%H%M%S)"
  DSH_UB_FILE="$file" DSH_UB_BEGIN="$begin" DSH_UB_END="$end" python3 - <<'PY'
import os
p, b, e = os.environ['DSH_UB_FILE'], os.environ['DSH_UB_BEGIN'], os.environ['DSH_UB_END']
with open(p, encoding='utf-8') as f:
    lines = f.read().split('\n')
out, skip = [], False
for ln in lines:
    if ln.strip() == b:
        skip = True
        continue
    if skip:
        if ln.strip() == e:
            skip = False
        continue
    out.append(ln)
while out and out[-1].strip() == '':
    out.pop()
with open(p, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out) + ('\n' if out else ''))
print(f'已清理受管块：{p}')
PY
}

strip_block "$PATCH" '# >>> dsh-local-browser >>>' '# <<< dsh-local-browser <<<'
strip_block "$AGENTS" '<!-- >>> dsh-local-browser >>> -->' '<!-- <<< dsh-local-browser <<< -->'

rm -rf "$DSH_HOME/skills/local-browser"
echo "已移除 skill"

pkill -f "user-data-dir=$CB_DIR" 2>/dev/null && echo "已关闭调试 Chrome" || echo "调试 Chrome 未在运行"

if [ "$PURGE" -eq 1 ]; then
  rm -rf "$DSH_HOME/mcp" "$CB_DIR"
  echo "已删除 $DSH_HOME/mcp 与 $CB_DIR"
else
  echo "保留了 $DSH_HOME/mcp 与 $CB_DIR（要删干净用 --purge）"
fi

echo "完成。重启 DeepSeek Harness 生效。"
