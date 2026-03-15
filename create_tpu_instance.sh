#!/usr/bin/env bash
# Provision a GCP TPU VM instance.
#
# Requires: source env.sh before running.
# Usage: ./create_tpu_instance.sh            # direct TPU VM
#        ./create_tpu_instance.sh -q         # queued resource request
#        ./create_tpu_instance.sh --queued   # queued resource request
#
# By default, creates a TPU VM directly. With -q/--queued, submits a
# queued-resource request instead (useful when capacity is limited).

set -euo pipefail

: "${PROJECT:?PROJECT must be set (source env.sh first)}"
: "${TPU_ZONE:?TPU_ZONE must be set (source env.sh first)}"
: "${TPU_NAME:?TPU_NAME must be set in env.sh}"
: "${TPU_ACCELERATOR_TYPE:?TPU_ACCELERATOR_TYPE must be set in env.sh}"
: "${TPU_RUNTIME_VERSION:?TPU_RUNTIME_VERSION must be set in env.sh}"

QUEUED=false
for arg in "$@"; do
  case "${arg}" in
    -q|--queued)
      QUEUED=true
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      echo "Usage: $0 [-q|--queued]" >&2
      exit 1
      ;;
  esac
done

if [ "${QUEUED}" = true ]; then
  : "${TPU_QUEUE_NAME:?TPU_QUEUE_NAME must be set in env.sh}"
  echo "Creating TPU queued resource: ${TPU_QUEUE_NAME} (node: ${TPU_NAME})"

  gcloud alpha compute tpus queued-resources create "${TPU_QUEUE_NAME}" \
    --node-id="${TPU_NAME}" \
    --project="${PROJECT}" \
    --zone="${TPU_ZONE}" \
    --accelerator-type="${TPU_ACCELERATOR_TYPE}" \
    --runtime-version="${TPU_RUNTIME_VERSION}"

  echo "TPU queued resource '${TPU_QUEUE_NAME}' created successfully."
else
  echo "Creating TPU VM: ${TPU_NAME}"

  gcloud compute tpus tpu-vm create "${TPU_NAME}" \
    --project="${PROJECT}" \
    --zone="${TPU_ZONE}" \
    --accelerator-type="${TPU_ACCELERATOR_TYPE}" \
    --version="${TPU_RUNTIME_VERSION}"

  echo "TPU VM '${TPU_NAME}' created successfully."
fi

echo "Run 'use-tpu' to activate it and enable commands like gssh, gpush, and gtpu."
