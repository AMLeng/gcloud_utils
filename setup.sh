#!/usr/bin/env bash

# this file is meant to be sourced on your workstation to enable helper commands/env vars for interacting with gcloud hosts

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed:"
    echo "  source ${BASH_SOURCE[0]}"
    exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/env.sh" ]]; then
    echo "Missing env.sh — copy env.sh.example to env.sh and fill in your values."
    return 1
fi
source "$SCRIPT_DIR/env.sh"

# --- Mode switching ---

use-tpu() {
    local init=false
    if [[ "${1:-}" == "--init" ]]; then
        init=true
        shift
    fi
    export GCLOUD_MODE="tpu"
    export ZONE="$TPU_ZONE"
    export REGION="$TPU_REGION"
    export NODE_NAME="$TPU_NAME"
    echo "Active: TPU  node=$NODE_NAME  zone=$ZONE"
    if [[ "$init" == true ]]; then
        gpush "$SCRIPT_DIR/tpu_setup.sh"
        gssh "sudo REMOTE_USER=$REMOTE_USER bash ~/tpu_setup.sh"
    fi
}

use-cpu() {
    local init=false
    if [[ "${1:-}" == "--init" ]]; then
        init=true
        shift
    fi
    local name="${1:-$CPU_NAME}"
    if [[ -z "$name" ]]; then
        echo "Usage: use-cpu [--init] INSTANCE_NAME (or set CPU_NAME in env.sh)" >&2
        return 1
    fi
    export GCLOUD_MODE="cpu"
    export ZONE="$CPU_ZONE"
    export REGION="$CPU_REGION"
    export NODE_NAME="$name"
    echo "Active: CPU  node=$NODE_NAME  zone=$ZONE"
    if [[ "$init" == true ]]; then
        gpush "$SCRIPT_DIR/cpu_setup.sh"
        gssh "sudo REMOTE_USER=$REMOTE_USER TARGET_REPO=$TARGET_REPO bash ~/cpu_setup.sh"
    fi
}

_require_mode() {
    if [[ -z "${GCLOUD_MODE:-}" ]]; then
        echo "No active instance. Run use-tpu or use-cpu first." >&2
        return 1
    fi
}

# --- Low-level wrappers ---

# TPU-specific gcloud wrapper (handles worker flags)
gtpu() {
    local worker_flag=""

    if [[ "$1" == "-a" ]]; then
        worker_flag="--worker=all"
        shift
    elif [[ "$1" =~ ^-([0-9]+)$ ]]; then
        worker_flag="--worker=${BASH_REMATCH[1]}"
        shift
    fi

    gcloud compute tpus tpu-vm "$@" --zone="$TPU_ZONE" --project="$PROJECT" $worker_flag
}

# CPU gcloud wrapper
gcpu() {
    gcloud compute instances "$@" --zone="$CPU_ZONE" --project="$PROJECT"
}

# --- Generic helpers (dispatch on active mode) ---

gssh() {
    _require_mode || return 1
    if [[ "$GCLOUD_MODE" == "tpu" ]]; then
        if [[ $# -gt 0 ]]; then
            gtpu -a ssh "$NODE_NAME" --command="$*"
        else
            gtpu ssh "$NODE_NAME"
        fi
    else
        if [[ $# -gt 0 ]]; then
            gcloud compute ssh "$NODE_NAME" --zone="$ZONE" --project="$PROJECT" --command="$*"
        else
            gcloud compute ssh "$NODE_NAME" --zone="$ZONE" --project="$PROJECT"
        fi
    fi
}

gpush() {
    _require_mode || return 1
    local scp_flags=()
    if [[ "$1" == "-r" ]]; then
        scp_flags+=("--recurse")
        shift
    fi

    if [[ "$GCLOUD_MODE" == "tpu" ]]; then
        gtpu -a scp "${scp_flags[@]}" "$@" "$NODE_NAME":~/
    else
        gcloud compute scp "${scp_flags[@]}" "$@" "$NODE_NAME":~/ --zone="$ZONE" --project="$PROJECT"
    fi
}

gpython() {
    _require_mode || return 1
    local skip_scp=false
    if [[ "$1" == "-r" ]]; then
        skip_scp=true
        shift
    fi

    local script="$1"
    shift
    local basename="${script##*/}"
    if [[ "$skip_scp" == false ]]; then
        gpush "$script"
    fi

    if [[ "$GCLOUD_MODE" == "tpu" ]]; then
        # The worker_setup.sh script sets up a venv for a more recent version of python in jax-env; we use this when running our scripts
        gtpu -a ssh "$NODE_NAME" --command="source ~/jax-env/bin/activate && python3 ~/$basename $*"
    else
        gssh "python3 ~/$basename $*"
    fi
}

# --- TPU-only helpers ---

gettraces() {
    if [[ "${GCLOUD_MODE:-}" != "tpu" ]]; then
        echo "gettraces is only available in TPU mode." >&2
        return 1
    fi
    local remote_path="${1:-/tmp/jax-trace}"
    local local_path="${2:-/tmp/jax-trace-worker}"
    mkdir -p "$local_path"
    for ((i = 0; i < NUM_WORKERS; i++)); do
        gtpu -$i scp --recurse "$NODE_NAME":"$remote_path" "$local_path"/
    done
    gtpu -a ssh "$NODE_NAME" --command="rm -rf '$remote_path'"
    echo "Copied traces to '$local_path'"
}
