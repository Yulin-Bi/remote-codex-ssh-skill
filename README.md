# Remote Codex SSH Skill

[简体中文](#简体中文) · [English](#english)

## 简体中文

通过 SSH 和反向隧道，在远程 Linux/WebIDE 环境中安装、配置和维护 Codex CLI。

### 适用场景

- 远程服务器或 WebIDE 没有直接提供 SSH，但可以通过 VS Code Remote 或 WebIDE 终端访问
- 服务器无法直接访问 Codex 服务，需要借助本机代理
- 需要在官方 ChatGPT 登录和本地 API 中转之间切换
- 服务器上同时运行 CannBot、OpenCode 等内网工具，不能污染全局代理环境

### 工作模式

```text
官方 Codex profile:
Codex -> 服务器 127.0.0.1:<official-remote-port>
      -> SSH reverse tunnel
      -> 本机 HTTP proxy

本地 relay profile:
Codex -> 服务器 127.0.0.1:<relay-remote-port>
      -> SSH reverse tunnel
      -> 本机 OpenAI-compatible relay
```

两种 profile 使用独立的 `CODEX_HOME`，认证、配置和会话不会互相覆盖。

### 安装与配置

先在远程服务器确认环境：

```bash
uname -srm
whoami
printf 'HOME=%s\nCODEX_HOME=%s\n' "$HOME" "${CODEX_HOME:-<unset>}"
command -v curl || true
command -v codex || true
```

使用官方 Codex 安装方式安装与服务器架构匹配的 CLI，并将状态目录放到私有持久化目录：

```bash
install -d -m 700 /absolute/persistent/path/.codex-home
export CODEX_HOME=/absolute/persistent/path/.codex-home
```

不要把 `CODEX_HOME` 放进 Git 仓库，也不要提交 `auth.json`、SQLite 数据库或日志。

### 反向隧道

在 Windows PowerShell 中运行：

```powershell
& .\scripts\start-reverse-tunnel.ps1 `
  -SshHost 'your-ssh-host-alias' `
  -LocalProxyPort <local-proxy-port> `
  -RemoteProxyPort <official-remote-port>
```

如果还要转发本机 API relay，使用另一条端口转发：

```powershell
& .\scripts\start-reverse-tunnel.ps1 `
  -SshHost 'your-ssh-host-alias' `
  -LocalProxyPort <local-relay-port> `
  -RemoteProxyPort <relay-remote-port>
```

两个远端端口必须不同，并且都绑定到服务器回环地址。不要把端口监听到公网。

### 不污染全局代理

不要在服务器 `~/.bashrc` 中全局设置 `HTTP_PROXY`、`HTTPS_PROXY` 或 `ALL_PROXY`。否则 CannBot、OpenCode 等内网工具也会继承代理，导致内网连接失败。

推荐使用命名 launcher：

```bash
codex-official() {
  env HTTP_PROXY=http://127.0.0.1:<official-remote-port> \
      HTTPS_PROXY=http://127.0.0.1:<official-remote-port> \
      ALL_PROXY=http://127.0.0.1:<official-remote-port> \
      CODEX_HOME=/absolute/path/.codex-home \
      /home/<remote-user>/.local/bin/codex "$@"
}

codex-localrelay() {
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
      -u http_proxy -u https_proxy -u all_proxy \
      CODEX_HOME=/absolute/path/.codex-relay \
      /home/<remote-user>/.local/bin/codex "$@"
}
```

### 监控反向隧道

需要时手动启动后台监控：

```powershell
& .\scripts\start-reverse-tunnel-monitor.ps1 `
  -SshHost 'your-ssh-host-alias'
```

启动前会先检查服务器是否可达。服务器未启动时，脚本会直接提示并退出，不会留下后台进程。运行中连续多次探测失败后，监控也会自动退出。

日志位置：

```text
%LOCALAPPDATA%\Codex\reverse-tunnels\monitor.log
```

### 兼容性检查

中转服务必须支持 Codex 使用的 Responses API。仅能访问 `/v1/models` 或 `/v1/chat/completions`，不能证明兼容 Codex。

```bash
curl -sS -o /dev/null \
  -w 'code=%{http_code} total=%{time_total}s\n' \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST http://127.0.0.1:<relay-remote-port>/v1/responses \
  --data '{"model":"your-model","input":"ping","max_output_tokens":1}'
```

### 安全注意事项

- 不要提交 API Key、ChatGPT token、`auth.json`、日志或 SQLite 文件
- 不要公开完整的 Dev Space 注册 URL 或注册码
- 使用 `chmod 700` 保护 `CODEX_HOME`，使用 `chmod 600` 保护凭据文件
- 同一个 Linux 用户下，移动 `CODEX_HOME` 不能隔离不同人的账号
- 本地反向隧道依赖本机、代理程序、SSH 连接和远程开发环境持续在线

### 选择监控线路

监控器支持三种显式模式：

```powershell
& .\scripts\start-reverse-tunnel-monitor.ps1 `
  -SshHost 'your-ssh-host-alias' `
  -Mode Official

& .\scripts\start-reverse-tunnel-monitor.ps1 `
  -SshHost 'your-ssh-host-alias' `
  -Mode Relay
```

`Official` 只维护官方代理隧道并且是默认模式，`Relay` 只维护本地 API 中转隧道，`Both` 保留原来的双隧道行为。通常应选择正在使用的单线路模式，这样另一条线路断开后不会被反复重建。同一时间只允许一个监控进程；切换模式前先停止旧监控。

## English

Configure and maintain Codex CLI on a remote Linux/WebIDE environment through SSH and reverse tunnels.

### Use cases

- A remote server or WebIDE exposes a shell but no direct SSH workflow
- The server cannot reach Codex directly and needs a proxy on the local computer
- You need to switch between official ChatGPT authentication and a local API relay
- Internal tools such as CannBot or OpenCode must not inherit the Codex proxy

### Architecture

```text
Official Codex profile:
Codex -> server 127.0.0.1:<official-remote-port>
      -> SSH reverse tunnel
      -> local HTTP proxy

Local relay profile:
Codex -> server 127.0.0.1:<relay-remote-port>
      -> SSH reverse tunnel
      -> local OpenAI-compatible relay
```

Keep the two profiles in separate `CODEX_HOME` directories so their credentials, configuration, and sessions never overwrite each other.

### Setup

Inspect the remote host first, install the Codex CLI for the remote architecture, and keep its state in a private persistent directory outside the Git repository:

```bash
install -d -m 700 /absolute/persistent/path/.codex-home
export CODEX_HOME=/absolute/persistent/path/.codex-home
```

Never commit `auth.json`, SQLite state, logs, or any other credential-bearing file.

### Reverse tunnels and proxy isolation

Use `scripts/start-reverse-tunnel.ps1` with your own SSH alias and port values. Keep reverse forwards bound to loopback. Do not export `HTTP_PROXY`, `HTTPS_PROXY`, or `ALL_PROXY` globally in `.bashrc`; use named launchers so internal IDE tools do not inherit the proxy.

Use one explicit route when you need a manually controlled watchdog:

```powershell
& .\scripts\start-reverse-tunnel-monitor.ps1 `
  -SshHost 'your-ssh-host-alias' `
  -Mode Official

& .\scripts\start-reverse-tunnel-monitor.ps1 `
  -SshHost 'your-ssh-host-alias' `
  -Mode Relay
```

`Official` maintains only the official proxy tunnel and is the default, `Relay` maintains only the local API relay tunnel, and `Both` retains the previous dual-tunnel behavior. The monitor checks server availability before starting and exits after repeated server failures. Only one monitor process runs at a time; stop the existing monitor before switching modes.

### Compatibility and security

The relay must support the Responses API used by Codex. A successful `/v1/models` or Chat Completions request is not sufficient; test `POST /v1/responses` with a minimal request first.

Treat API keys, ChatGPT tokens, Dev Space registration URLs, and SSH credentials as secrets. Keep them out of Git history and rotate any credential that has been exposed.
