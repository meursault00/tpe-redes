#!/usr/bin/env bash
# ===============================================================
# Script: watch_cluster.sh
# Purpose: Monitors Kubernetes cluster and triggers recovery.
# Adds periodic health checks and multipass validation.
# ===============================================================

INVENTORY_PATH="inventory.yml"
MASTER_NODE="k3s-master"
CHECK_INTERVAL=10
MAX_RETRIES=3
HEALTH_INTERVAL=60        # run health.yml every 60s
STATE_FILE="/tmp/node_failures.txt"
touch "$STATE_FILE"

LAST_HEALTH_RUN=0

echo "🔍 Starting cluster watcher..."
echo "Monitoring every ${CHECK_INTERVAL}s. Press Ctrl+C to stop."

get_failure_count() {
  local node="$1"
  grep -E "^${node}:" "$STATE_FILE" | cut -d':' -f2 | head -n1
}

set_failure_count() {
  local node="$1"
  local count="$2"
  grep -vE "^${node}:" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  echo "${node}:${count}" >> "$STATE_FILE"
}

while true; do
  echo ""
  echo "=============================================="
  echo "🕒 $(date '+%H:%M:%S') - Checking cluster status..."
  echo "=============================================="

  NODE_STATUS=$(multipass exec "$MASTER_NODE" -- sudo kubectl get nodes --no-headers 2>/dev/null)

  if [ -z "$NODE_STATUS" ]; then
    echo "⚠️  Unable to fetch node status (master may be unavailable)."
    sleep "$CHECK_INTERVAL"
    continue
  fi

  echo "$NODE_STATUS" | awk '{print "• " $1 " -> " $2}'

  # also list current multipass VMs
  MULTIPASS_NODES=$(multipass list --format csv | grep k3s-worker | cut -d',' -f1)

  FAILED_NODES=()
  while IFS= read -r line; do
    NODE_NAME=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{print $2}')

    # Skip control plane node from multipass existence check
    if [[ "$NODE_NAME" == "k3s-master" ]]; then
        continue  # still printed above, just skip health logic
    fi

    # check if exists in multipass (for workers only)
    if ! echo "$MULTIPASS_NODES" | grep -q "$NODE_NAME"; then
        echo "💀 Node $NODE_NAME missing from Multipass (deleted or crashed)."
        STATUS="Missing"
    fi

    if [[ "$STATUS" != "Ready" ]]; then
      COUNT=$(get_failure_count "$NODE_NAME")
      COUNT=$(( ${COUNT:-0} + 1 ))
      set_failure_count "$NODE_NAME" "$COUNT"

      echo "❌ Node $NODE_NAME is $STATUS (failure count: $COUNT)"

      if (( COUNT >= MAX_RETRIES )); then
        echo "🚨 Node $NODE_NAME marked as failed after $MAX_RETRIES checks."
        FAILED_NODES+=("$NODE_NAME")
      fi
    else
      set_failure_count "$NODE_NAME" 0
    fi
  done <<< "$NODE_STATUS"

  if [ ${#FAILED_NODES[@]} -gt 0 ]; then
    echo "🔥 Initiating auto-recovery for ${#FAILED_NODES[@]} failed node(s)..."
    echo "Nodes to replace: ${FAILED_NODES[*]}"

    for NODE in "${FAILED_NODES[@]}"; do
      echo "🧹 Removing $NODE from cluster..."
      multipass exec "$MASTER_NODE" -- sudo kubectl delete node "$NODE" --force --grace-period=0 || true
      multipass delete "$NODE" --purge || true
    done

    echo "⚙️  Launching Ansible scale playbook to restore capacity..."
    ansible-playbook -i "$INVENTORY_PATH" playbooks/scale.yml -e "action=add node_count=${#FAILED_NODES[@]}"

    for NODE in "${FAILED_NODES[@]}"; do
      set_failure_count "$NODE" 0
    done
  fi

  # Periodic health check
  NOW=$(date +%s)
  if (( NOW - LAST_HEALTH_RUN >= HEALTH_INTERVAL )); then
    echo "🩺 Running periodic health check..."
    ansible-playbook -i "$INVENTORY_PATH" playbooks/health.yml > /tmp/cluster_health_report.txt
    echo "✅ Health report saved to /tmp/cluster_health_report.txt"
    LAST_HEALTH_RUN=$NOW
  fi

  echo "✅ Cluster check completed. Next check in ${CHECK_INTERVAL}s..."
  sleep "$CHECK_INTERVAL"
done