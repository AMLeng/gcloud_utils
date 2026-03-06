#!/usr/bin/env bash

# To be run with use-tpu --init, or manually:
# gpush tpu_setup.sh
# gssh "sudo REMOTE_USER=$REMOTE_USER bash ~/tpu_setup.sh"

set -e

if ! curl -sf -m 1 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ > /dev/null 2>&1; then
    echo "ERROR: This script must be run on a GCP instance, not the host machine." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y python3.11 python3.11-venv python3.11-dev

# Run the rest as the actual user
su - "${REMOTE_USER:?REMOTE_USER must be set}" <<'EOF'
python3.11 -m venv ~/jax-env
source ~/jax-env/bin/activate
pip install --upgrade pip
pip install -U "jax[tpu]" -f https://storage.googleapis.com/jax-releases/libtpu_releases.html
EOF
