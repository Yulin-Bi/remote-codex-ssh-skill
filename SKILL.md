---
name: remote-codex-ssh-setup
description: Configure, migrate, validate, and troubleshoot Codex CLI on a remote Linux server reached through SSH or a browser WebIDE. Use for remote Codex installation, CODEX_HOME migration, shared-server credential safety, Windows Clash or HTTP proxy reverse tunnels, persistent proxy variables, WebSocket or HTTPS timeouts, MCP startup failures, and deciding whether Codex can run from WebIDE without local VS Code.
---

# Remote Codex SSH Setup

Set up Codex CLI on a remote Linux host with a reversible, evidence-first workflow. Keep installation, account state, networking, and the terminal surface separate: VS Code and WebIDE are only ways to open a shell; Codex runs on the server.

## Workflow

### 1. Inspect before changing anything

Run a short read-only check on the remote host:

```bash
uname -srm
whoami
printf 'HOME=%s\nCODEX_HOME=%s\n' "$HOME" "${CODEX_HOME:-<unset>}"
command -v curl || true
command -v codex || true
command -v bwrap || true
cat /etc/os-release | sed -n '1,8p'
```

Then establish CPU architecture, distribution, ownership of persistent storage, existing tools, direct HTTPS access, and whether people use distinct Linux accounts. Do not install packages merely because a command is absent; inspect `PATH`, existing installations, permissions, and network access first.

### 2. Select a network mode

Test direct access:

```bash
curl -I --connect-timeout 5 --max-time 15 https://chatgpt.com
```

Choose one mode:

- Direct access: use the server connection without a local proxy.
- Local proxy through SSH: use when direct HTTPS times out but the user's computer has a working HTTP proxy such as Clash.
- WebIDE-only: require direct server access or a persistent proxy reachable independently of the local VS Code session.

Read [references/webide-network-modes.md](references/webide-network-modes.md) when WebIDE, tunnel lifetime, WebSocket fallback, or proxy ownership is relevant.

### 3. Create an SSH reverse proxy when needed

On Windows, prefer [scripts/start-reverse-tunnel.ps1](scripts/start-reverse-tunnel.ps1). Supply the actual SSH host alias and local proxy port:

```powershell
& .\scripts\start-reverse-tunnel.ps1 `
  -SshHost 'your-ssh-host-alias' `
  -LocalProxyPort 7897 `
  -RemoteProxyPort 17897
```

Never assume `7897`; inspect the user's proxy application first. Validate from the remote server:

```bash
curl -x http://127.0.0.1:17897 \
  -I --connect-timeout 10 --max-time 20 https://chatgpt.com
```

Treat any fast HTTP response as network reachability. A timeout means the reverse port, SSH process, local proxy, or proxy route is unhealthy.

For a user-controlled watchdog, start [scripts/start-reverse-tunnel-monitor.ps1](scripts/start-reverse-tunnel-monitor.ps1) manually with `-Mode Official`, `-Mode Relay`, or `-Mode Both`. The default is `Official`. Relay mode auto-detects the current `cockpit-cliproxy` listening port; pass `-LocalRelayPort <local-relay-port>` only when auto-detection is ambiguous or a different relay is used. Prefer a single-route mode when only one Codex profile is in use so the inactive tunnel is not rebuilt. It first probes the SSH host and prints an error without starting a background process when the server is unavailable. If the server later becomes unavailable, [scripts/monitor-reverse-tunnels.ps1](scripts/monitor-reverse-tunnels.ps1) exits after three failed probes instead of retrying forever. It does not set global proxy variables and does not require a scheduled task. The monitor writes status to `%LOCALAPPDATA%\Codex\reverse-tunnels\monitor.log` on Windows.

```powershell
& .\scripts\start-reverse-tunnel-monitor.ps1 -SshHost 'your-ssh-host-alias' -Mode Official
& .\scripts\start-reverse-tunnel-monitor.ps1 -SshHost 'your-ssh-host-alias' -Mode Relay
```

Keep separate reverse forwards for separate purposes. In the Huawei Dev Space setup used by this skill:

- remote `127.0.0.1:<official-proxy-port>` -> local Clash `127.0.0.1:<local-proxy-port>`; use only for official ChatGPT/Codex network access;
- remote `127.0.0.1:<relay-tunnel-port>` -> local `127.0.0.1:<local-relay-port>`; use only for a local API relay.

Do not use `155446`: TCP ports are limited to `1..65535`. Keep both listeners bound to loopback. Do not export either HTTP proxy globally in `.bashrc`; global proxy variables can break internal services such as CannBot and OpenCode.

### 4. Install Codex for the remote architecture

Prefer the current official Codex installation instructions. Verify the installed binary matches the remote architecture and place user-owned executables under a user-writable location such as `~/.local/bin`.

```bash
command -v codex
codex --version
```

Do not copy a Windows or x86-64 executable onto an AArch64 Linux server.

### 5. Configure state and environment

Use a private `CODEX_HOME` outside a Git repository when persistent workspace storage is desired. Never place it inside a repository that may be committed.

```bash
bash scripts/configure-remote-env.sh \
  /absolute/persistent/path/.codex-home \
  http://127.0.0.1:17897 \
  codex-official
source ~/.bashrc

The configuration script must create a named launcher function, not global `HTTP_PROXY`, `HTTPS_PROXY`, or `ALL_PROXY` variables. Use a second `CODEX_HOME` for a local relay and a launcher that explicitly unsets proxy variables:

```bash
codex-official() {
  env HTTP_PROXY=http://127.0.0.1:17897 HTTPS_PROXY=http://127.0.0.1:17897 \
      ALL_PROXY=http://127.0.0.1:17897 CODEX_HOME=/absolute/.codex-home \
      /home/<remote-user>/.local/bin/codex "$@"
}

codex-localrelay() {
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
      -u http_proxy -u https_proxy -u all_proxy \
      CODEX_HOME=/absolute/.codex-relay \
      /home/<remote-user>/.local/bin/codex "$@"
}
```

Keep the official device-login state and relay API-key state in different homes. The relay profile should use `http://127.0.0.1:15446/v1` only after testing that its `/v1/responses` endpoint works. A successful `/v1/models` or `/v1/chat/completions` request alone does not prove Codex compatibility; current Codex uses the Responses wire API.
```

If migrating existing state:

```bash
install -d -m 700 /absolute/persistent/path/.codex-home
cp -a "$HOME/.codex/." /absolute/persistent/path/.codex-home/
chmod -R go-rwx /absolute/persistent/path/.codex-home
```

Never display `auth.json`. Check only its existence, owner, mode, size, or equality with `cmp`.

### 6. Authenticate and validate

Use device login when the remote host cannot open a browser. Validate the selected home explicitly:

```bash
CODEX_HOME=/absolute/persistent/path/.codex-home codex login status
CODEX_HOME=/absolute/persistent/path/.codex-home codex resume --all
```

Open a fresh terminal and check persistence:

```bash
printf 'CODEX_HOME=%s\nHTTPS_PROXY=%s\n' "$CODEX_HOME" "$HTTPS_PROXY"
codex login status
```

Keep the old state directory until a fresh terminal passes these checks. Delete it only after the user explicitly requests deletion and the exact absolute target is verified.

### 7. Diagnose recurring connection errors

Interpret these separately:

- `Falling back from WebSockets to HTTPS transport`: WebSocket failed; HTTPS fallback may still work.
- `request timed out` after fallback: no usable transport; test HTTPS through the configured proxy.
- `MCP startup incomplete`: an optional MCP server failed; ordinary Codex may still work.
- Missing system `bubblewrap`: Codex may use its bundled fallback, but install the OS package when allowed.

For reconnect loops, verify in order: proxy variables in the launching shell, remote reverse port, HTTPS through the proxy, local proxy egress, and SSH keepalive state. Separate confirmed evidence from inference; a successful login does not prove stable model connectivity.

For profile isolation, verify both explicitly:

```bash
codex-official login status
codex-localrelay login status
env | grep -iE '^(HTTP|HTTPS|ALL|http|https|all)_PROXY=' || true
```

The last command should be empty in a normal shell. Only the named launcher should inject the official proxy.

## Shared-server safety

- Set the Codex home directory to mode `700` and credential files to `600`.
- Distinct Linux users are protected by filesystem permissions when configured correctly.
- People sharing the same Linux account can normally access that account's Codex session; moving directories does not isolate them.
- Never commit credentials, print tokens, or store the Codex home in a shared Git tree.
- Recommend a dedicated Linux account or separate server when strong account isolation is required.
