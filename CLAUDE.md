# gcloud_utils

Bash helper scripts for managing GCP compute instances (CPU and TPU).

## Project structure

- `env.sh` — User-specific config (project ID, service account, zones, instance names). Gitignored. Contains all identifying information.
- `env.sh.example` — Template for `env.sh`. Safe to commit.
- `setup.sh` — Sourced (not executed) to load env vars and define shell helper functions.
- `create_cpu_instance.sh` — Executable script to provision a CPU instance using `CPU_NAME` from `env.sh`.
- `worker_setup.sh` — Runs on TPU workers to install Python 3.11 and JAX in a venv (`~/jax-env`).

## Design principles

- One instance (CPU or TPU) is active at a time, selected via `use-cpu` / `use-tpu`.
- Active mode sets canonical `ZONE`, `REGION`, `NODE_NAME`, and `GCLOUD_MODE` env vars.
- Generic helpers (`gssh`, `gpush`, `gpython`) dispatch based on `GCLOUD_MODE`.
- Low-level wrappers (`gtpu`, `gcpu`) always use their respective zones regardless of active mode.
- `env.sh` holds all secrets/identifying info; everything else is safe to commit.

## Key variables (from env.sh)

- `PROJECT`, `SERVICE_ACCOUNT`, `REMOTE_USER` — GCP project, service account, and remote username
- `CPU_ZONE`, `CPU_REGION`, `CPU_NAME` — CPU instance config
- `TPU_ZONE`, `TPU_REGION`, `TPU_NAME`, `NUM_WORKERS` — TPU config

## Important rules

- When modifying `env.sh`, always update `env.sh.example` to match (with placeholder values).

## Conventions

- Scripts that define shell functions (setup.sh) must be sourced, not executed.
- Executable scripts (create_cpu_instance.sh) use `set -euo pipefail` and guard required env vars with `: "${VAR:?message}"`.
- Shell scripts use bash. No Python or other languages in this repo.
