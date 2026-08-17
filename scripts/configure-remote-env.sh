#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 && $# -ne 3 ]]; then
  echo "Usage: $0 /absolute/path/.codex-home http://127.0.0.1:17897 [launcher-name]" >&2
  exit 2
fi

codex_home=$1
proxy_url=$2
launcher_name=${3:-codex-official}

if [[ $codex_home != /* ]]; then
  echo "CODEX_HOME must be an absolute path." >&2
  exit 2
fi

if [[ $proxy_url != http://* && $proxy_url != https://* ]]; then
  echo "Proxy URL must start with http:// or https://." >&2
  exit 2
fi

if [[ ! $launcher_name =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
  echo "Launcher name must be a shell identifier-like name." >&2
  exit 2
fi

install -d -m 700 "$codex_home"
bashrc="$HOME/.bashrc"
touch "$bashrc"

if grep -qF '# REMOTE_CODEX_PROFILE_BEGIN' "$bashrc"; then
  echo "Remote Codex profile block already exists in $bashrc."
  echo "Edit that block manually if the path or proxy port changed."
  exit 0
fi

cat >> "$bashrc" <<EOF

# REMOTE_CODEX_PROFILE_BEGIN
$launcher_name() {
  env \
    HTTP_PROXY='$proxy_url' \
    HTTPS_PROXY='$proxy_url' \
    ALL_PROXY='$proxy_url' \
    http_proxy='$proxy_url' \
    https_proxy='$proxy_url' \
    all_proxy='$proxy_url' \
    NO_PROXY='localhost,127.0.0.1' \
    no_proxy='localhost,127.0.0.1' \
    CODEX_HOME='$codex_home' \
    "${CODEX_BIN:-$HOME/.local/bin/codex}" "\$@"
}
# REMOTE_CODEX_PROFILE_END
EOF

echo "Configured $bashrc. Run: source ~/.bashrc"
