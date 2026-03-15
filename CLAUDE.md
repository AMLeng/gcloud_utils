# gcloud_utils

Bash helper scripts for managing GCP compute instances (CPU and TPU).

## Project structure

- `env.sh` — User-specific config (project ID, service account, zones, instance names, machine/accelerator types). Gitignored. Contains all identifying information.
- `env.sh.example` — Template for `env.sh`. Safe to commit.
- `setup.sh` — Sourced (not executed) to load env vars and define shell helper functions.
- `create_cpu_instance.sh` — Provisions a CPU instance with monitoring and daily snapshots.
- `create_tpu_instance.sh` — Provisions a TPU VM directly, or via queued resources with `-q`/`--queued`.
- `cpu_setup.sh` — Runs on a CPU instance to install uv, set up a deploy key, and clone `TARGET_REPO`.
- `tpu_setup.sh` — Runs on TPU workers to install uv and clone `TARGET_REPO`. With `--venv-only`, skips the repo and installs a JAX venv (`~/jax-env`) instead.

## Design principles

- One instance (CPU or TPU) is active at a time, selected via `use-cpu` / `use-tpu`.
- Active mode sets canonical `ZONE`, `REGION`, `NODE_NAME`, and `GCLOUD_MODE` env vars.
- Generic helpers (`gssh`, `gpush`, `gpython`) dispatch based on `GCLOUD_MODE`.
- Low-level wrappers (`gtpu`, `gcpu`) always use their respective zones regardless of active mode.
- `env.sh` holds all secrets/identifying info and all tunables (machine types, accelerator types, runtime versions); scripts should never contain hardcoded config that a user might need to change.

## Key variables (from env.sh)

- `PROJECT`, `SERVICE_ACCOUNT`, `REMOTE_USER`, `TARGET_REPO` — GCP project, service account, remote username, and repo to clone
- `CPU_ZONE`, `CPU_REGION`, `CPU_NAME`, `CPU_MACHINE_TYPE` — CPU instance config
- `TPU_ZONE`, `TPU_REGION`, `TPU_NAME`, `TPU_QUEUE_NAME`, `TPU_ACCELERATOR_TYPE`, `TPU_RUNTIME_VERSION`, `NUM_WORKERS` — TPU config

## Important rules

- When modifying `env.sh`, always update `env.sh.example` to match (with placeholder values).
- All user-configurable values belong in `env.sh`, not hardcoded in scripts.

## Conventions

- Scripts that define shell functions (setup.sh) must be sourced, not executed.
- Executable scripts (create_cpu_instance.sh, create_tpu_instance.sh) use `set -euo pipefail` and guard required env vars with `: "${VAR:?message}"`.
- Remote setup scripts (cpu_setup.sh, tpu_setup.sh) check for `/var/run/reboot-required` and prompt the user to reboot if needed.
- Shell scripts use bash. No Python or other languages in this repo.
