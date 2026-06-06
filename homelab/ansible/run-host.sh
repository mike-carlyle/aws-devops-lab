#!/usr/bin/env bash
# Wrapper for the Phase 2 host-provisioning playbook.
#
# Unlike run.sh (Phase 1, containerised), this one runs ansible-playbook
# directly on the host because it needs apt, systemctl, and ufw — none of
# which work cleanly from inside a container without privileged mounts and
# musl/glibc gymnastics.
#
# One-off setup:
#   sudo apt install -y ansible-core
#   ansible-galaxy collection install -r requirements.yml
#   ansible-vault create group_vars/vault.yml    # see vault.yml.example
#   echo 'your-vault-password' > ~/.ansible-vault-pass && chmod 600 ~/.ansible-vault-pass
#
# Usage:
#   bash run-host.sh                       # full provision (sudo will prompt)
#   bash run-host.sh --check --diff        # dry-run, recommended first
#   bash run-host.sh --tags ssh,ufw        # subset
#   bash run-host.sh --skip-tags risky     # everything except SSH+UFW

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

# Resolve vault password file — env wins, otherwise default location.
VAULT_PASS_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-$HOME/.ansible-vault-pass}"
VAULT_FLAGS=()
if [ -f "$VAULT_PASS_FILE" ]; then
  VAULT_FLAGS=(--vault-password-file "$VAULT_PASS_FILE")
fi

# If vault.yml doesn't exist yet, skip loading it so --check still runs for
# everything except the msmtp role.
if [ ! -f group_vars/vault.yml ]; then
  echo ":: group_vars/vault.yml not found — running with empty vault" >&2
  echo ":: (msmtp role will be skipped; create vault.yml to enable it)" >&2
  EXTRA_VARS=(-e "vault_file=group_vars/vault.yml.example")
else
  EXTRA_VARS=()
fi

exec ansible-playbook \
  -i inventory/hosts.yml \
  --ask-become-pass \
  "${VAULT_FLAGS[@]}" \
  "${EXTRA_VARS[@]}" \
  provision-host.yml \
  "$@"
