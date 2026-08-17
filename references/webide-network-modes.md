# WebIDE and remote Codex network modes

## Core rule

Codex CLI runs where its process runs. If `codex` is entered in a WebIDE terminal, the CLI, configuration, credentials, filesystem access, and network requests belong to the remote server. Local VS Code is not required as a user interface.

## Mode comparison

| Mode | Can WebIDE run Codex? | Dependency |
|---|---|---|
| Server has direct outbound HTTPS | Yes | WebIDE terminal and server remain available |
| Server uses a company or persistent remote proxy | Yes | That proxy remains reachable |
| Server uses a reverse tunnel to local Clash | Yes, conditionally | Local computer, Clash, and the SSH tunnel process must stay running |
| No direct network and local computer/tunnel are off | No | The server has no path to OpenAI |

Closing VS Code does not necessarily stop a tunnel launched as an independent background SSH process. Shutting down the local computer, closing Clash, ending that SSH process, changing networks, or letting the managed workspace endpoint expire will break the route.

## Minimum WebIDE validation

Run inside the WebIDE terminal:

```bash
command -v codex
printf 'CODEX_HOME=%s\nHTTPS_PROXY=%s\n' "${CODEX_HOME:-<unset>}" "${HTTPS_PROXY:-<unset>}"
codex login status
curl -I --connect-timeout 10 --max-time 20 https://chatgpt.com
```

If using a reverse proxy, test it explicitly:

```bash
curl -x http://127.0.0.1:17897 \
  -I --connect-timeout 10 --max-time 20 https://chatgpt.com
```

A fast HTTP status demonstrates routing. It does not prove that long-lived WebSocket traffic is stable, so also perform a short real Codex request when account usage is authorized.

## Split official access from a local API relay

Do not use one global proxy environment for both Codex and internal IDE services. Use named launchers:

- `codex-official`: injects the official-network proxy only for that process;
- `codex-localrelay`: unsets proxy variables and points a separate `CODEX_HOME` at the local relay tunnel.

The local relay tunnel uses a user-selected remote and local port. The public/local relay must be tested with `POST /v1/responses`; `/v1/models` and Chat Completions success are insufficient for Codex.

## Choosing independence from the local computer

To use WebIDE after the local computer is off, provide direct server outbound access, a proxy hosted on a persistent reachable machine, or an organization-approved gateway or VPN. Do not expose a personal unauthenticated proxy publicly. Keep proxy listeners bound to loopback when using SSH reverse forwarding.
