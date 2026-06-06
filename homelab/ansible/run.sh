#!/usr/bin/env bash
# Wrapper to invoke the homelab Ansible playbook from a maintained
# ansible+docker container image, without installing Ansible on the host.
#
# Usage:
#   bash run.sh                       # full deploy
#   bash run.sh --check --diff        # dry-run, show what would change
#   bash run.sh --tags <tag>          # selective task subset
#
# Expectations:
#   * Docker is installed and the invoking user is in the 'docker' group
#   * The repo is checked out under $HOME/aws-devops-lab (or set REPO_ROOT)
#   * Service runtime directories live under $HOME (or set SERVICE_ROOT)

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/aws-devops-lab}"
SERVICE_ROOT="${SERVICE_ROOT:-$HOME}"
ANSIBLE_IMAGE="${ANSIBLE_IMAGE:-homelab-ansible:local}"

# Build the image on first run (or whenever the Dockerfile changes).
# Subsequent runs reuse the existing image.
if ! docker image inspect "$ANSIBLE_IMAGE" >/dev/null 2>&1; then
  echo ":: Building $ANSIBLE_IMAGE (one-time setup)..."
  docker build -t "$ANSIBLE_IMAGE" "$REPO_ROOT/homelab/ansible/"
fi

# Allocate a TTY only when stdin/stdout actually are TTYs (interactive shells).
# Skipping this lets the wrapper run from CI or non-interactive shells.
TTY_FLAGS=()
if [ -t 0 ] && [ -t 1 ]; then
  TTY_FLAGS=(-it)
fi

docker run --rm "${TTY_FLAGS[@]}" \
  --network host \
  -v "$REPO_ROOT:/repo:rw" \
  -v "$SERVICE_ROOT:$SERVICE_ROOT:rw" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc/passwd:/etc/passwd:ro \
  -v /etc/group:/etc/group:ro \
  -e HOME="$SERVICE_ROOT" \
  -w /repo/homelab/ansible \
  --user "$(id -u):$(getent group docker | cut -d: -f3)" \
  "$ANSIBLE_IMAGE" \
  ansible-playbook \
    -e "repo_root=/repo" \
    -e "service_root=$SERVICE_ROOT" \
    deploy-stack.yml \
    "$@"
