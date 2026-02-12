#!/usr/bin/env bash
set -Eeuo pipefail

# =============================================================
# ULTIMATE MULTI-DOMAIN DYNAMIC SECURITY TOOL INSTALLER
# - 4 parallel threads
# - Fully unattended
# - Auto build detection (Python / Node / Go / Rust)
# =============================================================

export DEBIAN_FRONTEND=noninteractive

BASE="$HOME/oss-tool-lab"
LOG="$BASE/install.log"
STATUS="$BASE/status.json"
VENV_DIR="$BASE/venvs"
MAX_JOBS=4
PER_PAGE=100

mkdir -p "$BASE" "$VENV_DIR"
echo "{}" > "$STATUS"

exec > >(tee -a "$LOG") 2>&1

msg(){ echo "[*] $1"; }
ok(){ echo "[✓] $1"; }
warn(){ echo "[!] $1"; }

json_update(){
  tmp=$(mktemp)
  jq --arg k "$1" --arg v "$2" '. + {($k): $v}' "$STATUS" > "$tmp"
  mv "$tmp" "$STATUS"
}

search_topics=(
  "osint" "osint-tools" "osint-reconnaissance" "web-scraper"
  "smart-contract-security" "solidity-audit" "evm-analysis"
  "cryptography" "zero-knowledge" "post-quantum-crypto"
  "exploit-development" "binary-exploitation"
  "reverse-engineering" "symbolic-execution"
  "malware-analysis" "fuzzing"
  "cloud-security" "container-security"
  "digital-forensics" "ctf-tools"
)

repos=()

msg "Discovering repositories..."

for topic in "${search_topics[@]}"; do
  results=$(curl -s "https://api.github.com/search/repositories?q=topic:${topic}&per_page=${PER_PAGE}"     | jq -r '.items[].full_name')
  for r in $results; do
    repos+=("$r")
  done
done

repos=($(printf "%s
" "${repos[@]}" | sort -u))

msg "Total repos discovered: ${#repos[@]}"

install_repo(){
  full="$1"
  name="${full##*/}"
  url="https://github.com/${full}.git"

  msg "Cloning $name"

  if ! git clone --depth 1 "$url" "$BASE/$name" >/dev/null 2>&1; then
    warn "$name clone failed"
    json_update "$name" "clone_failed"
    return
  fi

  cd "$BASE/$name" || return

  if [[ -f "setup.py" || -f "pyproject.toml" ]]; then
    python3 -m venv "$VENV_DIR/$name"
    source "$VENV_DIR/$name/bin/activate"
    pip install -U pip setuptools wheel >/dev/null 2>&1 || true
    pip install . >/dev/null 2>&1 &&       json_update "$name" "installed_python" ||       json_update "$name" "python_failed"
    deactivate
    return
  fi

  if [[ -f "package.json" ]]; then
    npm install >/dev/null 2>&1 &&       json_update "$name" "installed_node" ||       json_update "$name" "node_failed"
    return
  fi

  if [[ -f "go.mod" ]]; then
    go build ./... >/dev/null 2>&1 &&       json_update "$name" "built_go" ||       json_update "$name" "go_failed"
    return
  fi

  if [[ -f "Cargo.toml" ]]; then
    cargo build --release >/dev/null 2>&1 &&       json_update "$name" "built_rust" ||       json_update "$name" "rust_failed"
    return
  fi

  json_update "$name" "cloned_only"
}

active=0
pids=()

run_job(){
  install_repo "$1" &
  pids+=($!)
  active=$((active+1))

  while (( active >= MAX_JOBS )); do
    sleep 0.5
    newpids=()
    active=0
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        newpids+=("$pid")
        active=$((active+1))
      fi
    done
    pids=("${newpids[@]}")
  done
}

msg "Starting 4-thread installation..."

for repo in "${repos[@]}"; do
  run_job "$repo"
done

wait

msg "Installation complete."
msg "Status: $STATUS"
msg "Log: $LOG"
