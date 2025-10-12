#!/bin/bash
# Script to create Multipass VMs for the k3s cluster

set -e

# Configuration
CONTROL_PLANE_NAME="k3s-master"
CONTROL_PLANE_IP="192.168.64.10"
WORKER_PREFIX="k3s-worker"
WORKER_BASE_IP="192.168.64"
WORKER_START=11
NUM_WORKERS=2

# VM specs
CPUS=2
MEMORY="2G"
DISK="10G"

echo "Creating k3s cluster VMs with Multipass..."

# Create control plane node
echo "Creating control plane node: $CONTROL_PLANE_NAME"
multipass launch --name $CONTROL_PLANE_NAME \
  --cpus $CPUS \
  --memory $MEMORY \
  --disk $DISK \
  jammy

# Create worker nodes
for i in $(seq 1 $NUM_WORKERS); do
  WORKER_NAME="${WORKER_PREFIX}-${i}"
  echo "Creating worker node: $WORKER_NAME"
  multipass launch --name $WORKER_NAME \
    --cpus $CPUS \
    --memory $MEMORY \
    --disk $DISK \
    jammy
done

echo "VMs created successfully!"
echo "Run 'multipass list' to see all VMs"
