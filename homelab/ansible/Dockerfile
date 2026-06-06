# Lightweight image that wraps Ansible + Docker tooling so the homelab
# playbook can be run from any machine with Docker available, no Ansible
# install required on the host.
#
# Based on cytopia/ansible:latest-tools (Alpine + Ansible + git + utilities)
# with docker-cli, the compose plugin, and rsync added so the playbook's
# community.docker tasks and rsync sync step work out of the box.

FROM cytopia/ansible:latest-tools

USER root
RUN apk add --no-cache docker-cli docker-cli-compose rsync

# Cytopia's entrypoint already drops back to whatever UID is passed via --user.
