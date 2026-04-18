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

# --- Prompt tagging ---

# Save the original PS1 once so re-sourcing doesn't stack tags.
if [[ -z "${_GCLOUD_ORIG_PS1:-}" ]]; then
    export _GCLOUD_ORIG_PS1="$PS1"
fi

# _gcloud_set_prompt TAG COLOR — prepend a colored [TAG] to the saved PS1.
_gcloud_set_prompt() {
    local tag="$1"
    local color="$2"
    PS1="\[\e[1;${color}m\][${tag}]\[\e[0m\] ${_GCLOUD_ORIG_PS1}"
}

_gcloud_set_prompt "gcloud" "36"

# --- Mode switching ---

use-tpu() {
    local init=false
    local init_args=()
    if [[ "${1:-}" == "--init" ]]; then
        init=true
        shift
        init_args=("$@")
    fi
    export GCLOUD_MODE="tpu"
    export ZONE="$TPU_ZONE"
    export REGION="$TPU_REGION"
    export NODE_NAME="$TPU_NAME"
    _gcloud_set_prompt "tpu:$NODE_NAME" "33"
    echo "Active: TPU  node=$NODE_NAME  zone=$ZONE"
    if [[ "$init" == true ]]; then
        gpush "$SCRIPT_DIR/tpu_setup.sh"
        gssh "sudo REMOTE_USER=$REMOTE_USER TARGET_REPO=$TARGET_REPO UV_EXTRAS='$UV_EXTRAS' bash ~/tpu_setup.sh ${init_args[*]:-}"
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
    _gcloud_set_prompt "cpu:$NODE_NAME" "32"
    echo "Active: CPU  node=$NODE_NAME  zone=$ZONE"
    if [[ "$init" == true ]]; then
        gpush "$SCRIPT_DIR/cpu_setup.sh"
        gssh "sudo REMOTE_USER=$REMOTE_USER TARGET_REPO=$TARGET_REPO UV_EXTRAS='$UV_EXTRAS' bash ~/cpu_setup.sh"
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

gpull() {
    _require_mode || return 1
    local scp_flags=()
    local tpu_flags=()
    if [[ "${1:-}" == "-r" ]]; then
        scp_flags+=("--recurse")
        shift
    fi
    if [[ "${1:-}" == "-a" ]] || [[ "${1:-}" =~ ^-[0-9]+$ ]]; then
        tpu_flags+=("$1")
        shift
    fi

    local remote_path="$1"
    local local_path="${2:-.}"

    if [[ "$GCLOUD_MODE" == "tpu" ]]; then
        gtpu "${tpu_flags[@]}" scp "${scp_flags[@]}" "$NODE_NAME":"$remote_path" "$local_path"
    else
        gcloud compute scp "${scp_flags[@]}" "$NODE_NAME":"$remote_path" "$local_path" --zone="$ZONE" --project="$PROJECT"
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
        # Use jax-env venv if it exists (--venv-only setup), otherwise run directly
        gtpu -a ssh "$NODE_NAME" --command="if [ -d ~/jax-env ]; then source ~/jax-env/bin/activate; fi && python3 ~/$basename $*"
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
