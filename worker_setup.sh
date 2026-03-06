#!/usr/bin/env bash

# To be run with
# gtpu -a scp worker_setup.sh "$TPU_NAME":~/
# gtpu -a ssh "$TPU_NAME" --command="sudo -E bash ~/worker_setup.sh"

set -e

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
