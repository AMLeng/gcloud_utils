#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT:?PROJECT must be set (source env.sh first)}"
: "${SERVICE_ACCOUNT:?SERVICE_ACCOUNT must be set (source env.sh first)}"
: "${CPU_ZONE:?CPU_ZONE must be set (source env.sh first)}"
: "${CPU_REGION:?CPU_REGION must be set (source env.sh first)}"
: "${CPU_NAME:?CPU_NAME must be set in env.sh}"

MACHINE_TYPE="c4-standard-8"
SNAPSHOT_SCHEDULE="default-schedule-1"
OPS_AGENT_POLICY="goog-ops-agent-v2-template-1-5-0-${CPU_ZONE}"

echo "Creating instance: ${CPU_NAME}"

# Create the compute instance
gcloud compute instances create "${CPU_NAME}" \
  --project="${PROJECT}" \
  --zone="${CPU_ZONE}" \
  --machine-type="${MACHINE_TYPE}" \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=enable-osconfig=TRUE \
  --maintenance-policy=MIGRATE \
  --provisioning-model=STANDARD \
  --service-account="${SERVICE_ACCOUNT}" \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
  --tags=https-server \
  --create-disk=auto-delete=yes,boot=yes,device-name="${CPU_NAME}",image=projects/debian-cloud/global/images/debian-12-bookworm-v20260210,mode=rw,provisioned-iops=3060,provisioned-throughput=155,size=10,type=hyperdisk-balanced \
  --no-shielded-secure-boot \
  --shielded-vtpm \
  --shielded-integrity-monitoring \
  --labels=goog-ops-agent-policy=v2-template-1-5-0,goog-ec-src=vm_add-gcloud \
  --reservation-affinity=any \
  --threads-per-core=1

# Create and apply ops agent policy
CONFIG_FILE=$(mktemp)
cat > "${CONFIG_FILE}" <<'EOF'
agentsRule:
  packageState: installed
  version: latest
instanceFilter:
  inclusionLabels:
  - labels:
      goog-ops-agent-policy: v2-template-1-5-0
EOF

gcloud compute instances ops-agents policies create "${OPS_AGENT_POLICY}" \
  --project="${PROJECT}" \
  --zone="${CPU_ZONE}" \
  --file="${CONFIG_FILE}" 2>/dev/null || echo "Ops agent policy '${OPS_AGENT_POLICY}' already exists, skipping creation."

rm -f "${CONFIG_FILE}"

# Create snapshot schedule (may already exist, so allow failure)
gcloud compute resource-policies create snapshot-schedule "${SNAPSHOT_SCHEDULE}" \
  --project="${PROJECT}" \
  --region="${CPU_REGION}" \
  --max-retention-days=14 \
  --on-source-disk-delete=keep-auto-snapshots \
  --daily-schedule \
  --start-time=20:00 2>/dev/null || echo "Snapshot schedule '${SNAPSHOT_SCHEDULE}' already exists, skipping creation."

# Attach snapshot schedule to the instance disk
gcloud compute disks add-resource-policies "${CPU_NAME}" \
  --project="${PROJECT}" \
  --zone="${CPU_ZONE}" \
  --resource-policies="projects/${PROJECT}/regions/${CPU_REGION}/resourcePolicies/${SNAPSHOT_SCHEDULE}"

echo "Instance ${CPU_NAME} created and configured successfully."
echo "Run 'use-cpu' to activate it and enable commands like gssh, gpush, and gcpu."
