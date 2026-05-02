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
    apt-get install -y python3.11 python3.11-venv python3.11-dev htop

    # Heredoc is unquoted (<<EOF, not <<'EOF') so ${ADDITIONAL_CLAUDE_PLUGINS:-}
    # expands in the parent shell before being piped to `su -`. Use \$ to
    # defer any other variable expansion to the user's shell.
    su - "${REMOTE_USER}" <<EOF
python3.11 -m venv ~/jax-env
source ~/jax-env/bin/activate
pip install --upgrade pip
pip install -U "jax[tpu]" -f https://storage.googleapis.com/jax-releases/libtpu_releases.html
curl -fsSL https://claude.ai/install.sh | bash
grep -qxF "alias claude='claude --dangerously-skip-permissions'" ~/.bashrc \
    || echo "alias claude='claude --dangerously-skip-permissions'" >> ~/.bashrc
grep -qxF '"\e[5~": history-search-backward' ~/.inputrc 2>/dev/null \
    || echo '"\e[5~": history-search-backward' >> ~/.inputrc
grep -qxF '"\e[6~": history-search-forward' ~/.inputrc 2>/dev/null \
    || echo '"\e[6~": history-search-forward' >> ~/.inputrc
export PATH="\$HOME/.local/bin:\$PATH"

ADDITIONAL_CLAUDE_PLUGINS="${ADDITIONAL_CLAUDE_PLUGINS:-}" bash ~/install_claude_plugins.sh
EOF
else
    : "${TARGET_REPO:?TARGET_REPO must be set}"
    apt-get install -y git htop

    su - "${REMOTE_USER}" <<EOF
mkdir -p ~/.ssh
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null
curl -LsSf https://astral.sh/uv/install.sh | sh
curl -fsSL https://claude.ai/install.sh | bash
grep -qxF "alias claude='claude --dangerously-skip-permissions'" ~/.bashrc \
    || echo "alias claude='claude --dangerously-skip-permissions'" >> ~/.bashrc
grep -qxF '"\e[5~": history-search-backward' ~/.inputrc 2>/dev/null \
    || echo '"\e[5~": history-search-backward' >> ~/.inputrc
grep -qxF '"\e[6~": history-search-forward' ~/.inputrc 2>/dev/null \
    || echo '"\e[6~": history-search-forward' >> ~/.inputrc
export PATH="\$HOME/.local/bin:\$PATH"

ADDITIONAL_CLAUDE_PLUGINS="${ADDITIONAL_CLAUDE_PLUGINS:-}" bash ~/install_claude_plugins.sh

REPO_DIR="\$(basename "${TARGET_REPO}" .git)"
REPO_PATH="\$(echo "${TARGET_REPO}" | sed -E 's|.*github\.com[:/]||; s|\.git\$||')"

if [[ -d "\$REPO_DIR" ]]; then
    echo "Repo already cloned; pulling latest."
    cd "\$REPO_DIR"
    git pull
else
    # If a deploy key already exists, make sure SSH is configured to use it
    # before attempting the clone.
    if [[ -f ~/.ssh/deploy_key ]] && ! grep -q "Host github.com" ~/.ssh/config 2>/dev/null; then
        cat >> ~/.ssh/config <<'SSHEOF'
Host github.com
    IdentityFile ~/.ssh/deploy_key
    IdentitiesOnly yes
SSHEOF
        chmod 600 ~/.ssh/config
    fi

    echo "Cloning \$REPO_PATH..."
    if git clone "${TARGET_REPO}"; then
        cd "\$REPO_DIR"
    elif [[ ! -f ~/.ssh/deploy_key ]]; then
        # Clone failed and we have no deploy key — likely a private repo.
        # Generate one so the user can authorize this node.
        echo ""
        echo "Clone failed. If \$REPO_PATH is private, you'll need to add a deploy key."
        echo "Generating one now..."
        ssh-keygen -t ed25519 -f ~/.ssh/deploy_key -N "" -C "deploy-key-\$(hostname)"
        echo ""
        echo "=========================================="
        echo "Add this deploy key to your GitHub repo:"
        echo "  https://github.com/\$REPO_PATH/settings/keys"
        echo "=========================================="
        cat ~/.ssh/deploy_key.pub
        echo "=========================================="
        echo "Then re-run 'use-tpu --init' to retry the clone."
        echo ""
        exit 0
    else
        # We had a deploy key and the clone still failed — key is probably
        # not authorized on the repo (or TARGET_REPO is wrong).
        echo ""
        echo "ERROR: Clone failed even though a deploy key is configured."
        echo "Make sure this key is added to https://github.com/\$REPO_PATH/settings/keys :"
        echo ""
        cat ~/.ssh/deploy_key.pub
        exit 1
    fi
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
