# dsh-local-browser

让 DSH 能读**任何**链接：微信公众文章、知乎/小红书/飞书/内网等需要登录或被风控的页面。

原理：起一个**专用调试 Chrome**（独立 profile，CDP 端口 9333），登录态从你主 Chrome 复制一份快照。
DSH 通过 `@deepseek-ai/dsh-mcp-client`（stdio）挂载 Google 官方的 `chrome-devtools-mcp`（slim 模式 3 个工具），
用 `--browserUrl=http://127.0.0.1:9333` 连它。因此走的是**本机 IP + 真实登录态**，不是海外机房 IP。

## 换台电脑怎么装

```bash
git clone https://github.com/JoyTian88/dsh-local-browser.git
bash dsh-local-browser/install.sh          # 幂等，可反复执行
# 然后重启 DeepSeek Harness
```

前提：macOS、装了 Google Chrome、本机有 node（`brew install node`）、
主 Chrome 里已经登录过你要读的那些站点。

装完运行体检：

```bash
bash dsh-local-browser/doctor.sh
```

## install.sh 做了什么

1. `npm install --prefix ~/.dsh/mcp chrome-devtools-mcp@1.10.1`
2. 在 `~/.dsh/profiles/desktop/cordis.patch.yml` 里维护一段**受管块**（`# >>> dsh-local-browser >>>`），
   内容是插入 `mcp-chrome-devtools`；同时清掉手工加过的同 id 条目，避免重复注册
3. 把 `start.sh` / `sync.sh` 装到 `~/.dsh/chrome-debug/`
4. 首次安装时从主 Chrome 复制 cookie + Local Storage 到调试 profile
5. 在 `~/.dsh/AGENTS.md` 里维护一段受管块（取网页链接的固定流程，DSH 每次会话自动加载）
6. 把 `local-browser` skill 装到 `~/.dsh/skills/local-browser/SKILL.md`
7. 拉起调试 Chrome，跑 `doctor.sh`

改文件前都会留带时间戳的 `.bak-localbrowser-*`。

## 日常

- 直接把链接丢给 DSH 就行；它按 `web_fetch`/TinyFish → 本机浏览器 → TinyFish 自动化 的顺序降级。
- 调试 Chrome 没开：DSH 会自己跑 `~/.dsh/chrome-debug/start.sh`，它用 `open -na` 启动，
  由 launchd 托管，DSH 重启不会带走它。
- 主 Chrome 里**新登录**的站点不会自动同步。需要时先退出调试 Chrome，再跑：

  ```bash
  ~/.dsh/chrome-debug/sync.sh
  ```

  或者干脆在那个调试窗口里登录一次。

## 体检 / 卸载

```bash
bash doctor.sh                      # 逐项检查，失败项直接给下一步动作
bash uninstall.sh                   # 移除受管块/skill/脚本，保留登录态与 mcp 目录
bash uninstall.sh --purge           # 连 ~/.dsh/mcp 与 ~/.dsh/chrome-debug 一起删
```

## 踩过的坑（改配置前先读）

| 坑 | 结论 |
|---|---|
| GUI 进程 PATH | DSH GUI 的 `PATH` 只有 `/usr/bin:/bin:/usr/sbin:/sbin`，stdio MCP 的 `command` 必须是 **node 绝对路径**，不能用 `npx`（`#!/usr/bin/env node` 会找不到 node） |
| 端口 9222 被占 | 主 Chrome 打开 `chrome://inspect#remote-debugging` 后占用 9222，但那是它自己的授权握手口（`/json/version` 返回 404），不是标准 CDP 端点，所以调试 Chrome 用 9333 |
| `--autoConnect` 弹窗 | 每次新建连接都会弹 Chrome 授权框，不点就挂住；改用 `--browserUrl` 后零弹窗 |
| `--autoConnect` 与 `--executablePath` | 互斥，同时给会直接报错退出 |
| 微信验证 | 部分老链接（`__biz=...&mid=...` 形式）会跳 `wappoc_appmsgcaptcha`，那是链接本身失效/被风控；`/s/<id>` 直链正常 |
| 调试实例被带走 | 用 `open -na` 启动，归 launchd（`PPID=1`），DSH 重启不再杀掉它 |
| MCP 会话僵死 | `dsh-mcp-client` 只在 transport `onclose` 时重连，服务端返回 `-32001 Session not found` 不触发，只能重启 Host |
