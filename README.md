# gcloud_utils

Helper scripts for managing GCP compute instances (CPU and TPU).

## Setup

1. Copy `env.sh.example` to `env.sh` and fill in your project-specific values.
2. Source the setup script: `source setup.sh`

`env.sh` contains all identifying information (project ID, service account, zones, instance names) and is gitignored. Everything else is safe to commit.

## Usage model

Only one instance (CPU or TPU) is active at a time. After sourcing `setup.sh`, use one of the switching commands to select your target:

```bash
use-tpu            # activate the TPU node (uses TPU_NAME from env.sh)
use-cpu            # activate the CPU instance (uses CPU_NAME from env.sh)
use-cpu my-other   # activate a specific CPU instance by name
```

This sets the canonical `ZONE`, `REGION`, and `NODE_NAME` variables that all helper commands use.

## Helper commands

These work against whichever instance is currently active:

| Command | Description |
|---|---|
| `gssh [CMD...]` | SSH into the active node, optionally running a command |
| `gpush [-r] FILE...` | SCP files to the active node's home directory |
| `gpython [-r] SCRIPT [ARGS...]` | Copy and run a Python script on the active node (`-r` skips the copy) |

### Low-level wrappers

These always use their respective zones, regardless of active mode:

| Command | Description |
|---|---|
| `gtpu [-a\|-N] SUBCMD...` | Wrapper for `gcloud compute tpus tpu-vm` with worker flags |
| `gcpu SUBCMD...` | Wrapper for `gcloud compute instances` |

### TPU-only

| Command | Description |
|---|---|
| `gettraces [REMOTE_PATH] [LOCAL_PATH]` | Download JAX traces from all TPU workers |

## Creating instances

```bash
# CPU instance (uses CPU_NAME, CPU_ZONE, CPU_REGION from env.sh)
./create_cpu_instance.sh
```

After creation, run `use-cpu` to activate it.
