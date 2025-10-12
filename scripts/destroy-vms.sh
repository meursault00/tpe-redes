#!/bin/bash
# Script to destroy all Multipass VMs for the k3s cluster

set -e

echo "Destroying all k3s cluster VMs..."

# List all VMs with k3s prefix
VMS=$(multipass list --format csv | grep "k3s-" | cut -d',' -f1)

if [ -z "$VMS" ]; then
  echo "No k3s VMs found"
  exit 0
fi

# Stop and delete each VM
for vm in $VMS; do
  echo "Stopping and deleting: $vm"
  multipass stop $vm || true
  multipass delete $vm
done

# Purge deleted VMs
echo "Purging deleted VMs..."
multipass purge

echo "All k3s VMs destroyed successfully!"
