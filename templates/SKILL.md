---
name: local-browser
description: 用本机 Chrome 的真实登录态读网页（微信、知乎、小红书、飞书、内网等需要登录或被风控的页面），并负责这套能力的安装、自检与修复。只要用户提到读不了链接、访问失败、要验证、需要登录、微信公众号文章读不出、换电脑后 DSH 读不了网页、重装 local-browser、检查/修复本地浏览器通道，就用这个技能。
---

# local-browser — 本机浏览器取网页通道

后端是一个**专用调试 Chrome**（独立 profile，CDP 端口 9333），登录态是从主 Chrome 复制的快照。
DSH 通过 `@deepseek-ai/dsh-mcp-client` 以 stdio 方式启动 `chrome-devtools-mcp`（slim 模式，3 个工具），
用 `--browserUrl=http://127.0.0.1:9333` 连它。

## 工具

- `mcp__chrome-devtools__navigate` — 打开 URL
- `mcp__chrome-devtools__evaluate` — 在页面里跑 JS，取 `document.body.innerText`（正文）或 `document.documentElement.outerHTML`（结构）
- `mcp__chrome-devtools__screenshot`

## 常规用法

1. 先试 `web_fetch` / `mcp__tinyfish__fetch_content`（免费且快）。
2. 失败、需要登录、或被风控时，用 `navigate` + `evaluate`。这是本机 IP + 真实登录态，微信等站点走这里。
3. 仍失败，说明卡在哪一级、报什么错，再让用户手动给内容。

## 故障处理

- **报 `Could not connect to Chrome`**：调试 Chrome 没开。执行 `__CB_DIR__/start.sh` 再重试。
- **页面要求登录（登录态过期）**：让用户执行 `__CB_DIR__/sync.sh`（需先退出调试 Chrome），
  或让用户直接在调试 Chrome 窗口里登录一次。
- **`navigate` 跳到 `mp.weixin.qq.com/mp/wappoc_appmsgcaptcha?...`**：该链接本身失效或被风控，
  换一条新链接（`/s/<id>` 直链通常正常），或在调试 Chrome 窗口里让用户手动过一次验证。
- **换新电脑 / 需要重装**：`git clone https://github.com/JoyTian88/dsh-local-browser.git` 后
  `bash dsh-local-browser/install.sh`，然后重启 DSH。
- **只想体检**：`bash dsh-local-browser/doctor.sh`。
- **要卸载**：`bash dsh-local-browser/uninstall.sh`。

## 关键约束（改配置时别踩）

- DSH GUI 进程的 `PATH` 只有 `/usr/bin:/bin:/usr/sbin:/sbin`，所以 stdio MCP 的 `command`
  **必须是 node 的绝对路径**，不能用 `npx`（它是 `#!/usr/bin/env node`）。
- 调试端口不要用 **9222**：主 Chrome 打开 `chrome://inspect#remote-debugging` 时会占用 9222，
  但那是它自己的授权握手口（`/json/version` 返回 404），不是标准 CDP 端点。
- `chrome-devtools-mcp` 的 `--autoConnect` 与 `--executablePath` 互斥；`--autoConnect` 每次连接
  都会弹 Chrome 授权框，所以这里用 `--browserUrl`。
