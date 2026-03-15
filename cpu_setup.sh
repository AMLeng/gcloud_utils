#!/usr/bin/env bash

# To be run with use-cpu --init, or manually:
# gpush cpu_setup.sh
# gssh "sudo REMOTE_USER=$REMOTE_USER TARGET_REPO=$TARGET_REPO bash ~/cpu_setup.sh"

set -e

if ! curl -sf -m 1 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ > /dev/null 2>&1; then
    echo "ERROR: This script must be run on a GCP instance, not the host machine." >&2
    exit 1
fi

: "${REMOTE_USER:?REMOTE_USER must be set}"
: "${TARGET_REPO:?TARGET_REPO must be set}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y git

# Install uv, generate deploy key, and clone repo as the actual user
su - "${REMOTE_USER}" <<EOF
mkdir -p ~/.ssh
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="\$HOME/.local/bin:\$PATH"

# Generate a deploy key if one doesn't exist
if [[ ! -f ~/.ssh/deploy_key ]]; then
    ssh-keygen -t ed25519 -f ~/.ssh/deploy_key -N "" -C "deploy-key-\$(hostname)"
    echo ""
    echo "=========================================="
    echo "Add this deploy key to your GitHub repo:"
    echo "  Repo → Settings → Deploy keys → Add deploy key"
    echo "=========================================="
    cat ~/.ssh/deploy_key.pub
    echo "=========================================="
    echo "Then re-run 'use-cpu --init' to clone the repo."
    echo ""
    exit 0
fi

# Configure SSH to always use the deploy key for GitHub
if ! grep -q "Host github.com" ~/.ssh/config 2>/dev/null; then
    cat >> ~/.ssh/config <<'SSHEOF'
Host github.com
    IdentityFile ~/.ssh/deploy_key
    IdentitiesOnly yes
SSHEOF
    chmod 600 ~/.ssh/config
fi
REPO_DIR="\$(basename "${TARGET_REPO}" .git)"
if [[ -d "\$REPO_DIR" ]]; then
    cd "\$REPO_DIR"
    git pull
elif ! git clone "${TARGET_REPO}"; then
    # Extract owner/repo from git@github.com:owner/repo.git or https://github.com/owner/repo.git
    REPO_PATH="\$(echo "${TARGET_REPO}" | sed -E 's|.*github\.com[:/]||; s|\.git\$||')"
    echo ""
    echo "ERROR: Failed to clone. Make sure the deploy key is added to the repo:"
    echo "  https://github.com/\$REPO_PATH/settings/keys"
    echo ""
    echo "Public key to add:"
    cat ~/.ssh/deploy_key.pub
    exit 1
else
    cd "\$REPO_DIR"
fi
if [[ -f pyproject.toml ]]; then
    uv sync$(for extra in ${UV_EXTRAS:-}; do printf ' --extra %s' "$extra"; done)
fi
EOF

if [ -f /var/run/reboot-required ]; then
    echo ""
    echo "*** System restart required ***"
    echo "Run 'gssh \"sudo reboot\"' then reconnect after ~30 seconds."
fi
