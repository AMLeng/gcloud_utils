#!/usr/bin/env bash

# Set up a TPU VM with uv, deploy key, and the target repo (same as cpu_setup.sh).
#
# Requires: source env.sh before running.
# Usage: use-tpu --init                     # default: repo setup
#        use-tpu --init --venv-only          # just install JAX venv for gpython
#
# Or manually:
#   gpush tpu_setup.sh
#   gssh "sudo REMOTE_USER=$REMOTE_USER TARGET_REPO=$TARGET_REPO bash ~/tpu_setup.sh"
#   gssh "sudo REMOTE_USER=$REMOTE_USER bash ~/tpu_setup.sh --venv-only"
#
# With --venv-only, skips the repo clone and instead creates a ~/jax-env venv
# with JAX/TPU installed, for running scripts pushed ad-hoc via gpython.

set -e

if ! curl -sf -m 1 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ > /dev/null 2>&1; then
    echo "ERROR: This script must be run on a GCP instance, not the host machine." >&2
    exit 1
fi

: "${REMOTE_USER:?REMOTE_USER must be set}"

VENV_ONLY=false
for arg in "$@"; do
    case "${arg}" in
        --venv-only)
            VENV_ONLY=true
            ;;
        *)
            echo "Unknown option: ${arg}" >&2
            echo "Usage: $0 [--venv-only]" >&2
            exit 1
            ;;
    esac
done

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

if [ "${VENV_ONLY}" = true ]; then
    apt-get install -y python3.11 python3.11-venv python3.11-dev

    su - "${REMOTE_USER}" <<'EOF'
python3.11 -m venv ~/jax-env
source ~/jax-env/bin/activate
pip install --upgrade pip
pip install -U "jax[tpu]" -f https://storage.googleapis.com/jax-releases/libtpu_releases.html
EOF
else
    : "${TARGET_REPO:?TARGET_REPO must be set}"
    apt-get install -y git

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
    echo "Then re-run 'use-tpu --init' to clone the repo."
    echo ""
    exit 0
fi

# Use the deploy key for git operations
export GIT_SSH_COMMAND="ssh -i ~/.ssh/deploy_key -o IdentitiesOnly=yes"
REPO_DIR="\$(basename "${TARGET_REPO}" .git)"
if [[ -d "\$REPO_DIR" ]]; then
    cd "\$REPO_DIR"
    git pull
elif ! git clone "${TARGET_REPO}"; then
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
fi

if [ -f /var/run/reboot-required ]; then
    echo ""
    echo "*** System restart required ***"
    echo "Run 'gssh \"sudo reboot\"' then reconnect after ~30 seconds."
fi
