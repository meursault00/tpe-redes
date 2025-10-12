#!/bin/bash
# Cleanup script - removes all cluster resources and resets environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warn "This will:"
echo "  1. Uninstall k3s from all nodes (if installed)"
echo "  2. Destroy all k3s VMs"
echo "  3. Clean up local cache and logs"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    print_info "Aborted"
    exit 0
fi

# 1. Uninstall k3s if ansible is available
if command -v ansible-playbook &> /dev/null; then
    print_info "Attempting to uninstall k3s from nodes..."
    cd "$PROJECT_ROOT/ansible"
    ansible-playbook playbooks/uninstall.yml --extra-vars "confirm_uninstall=yes" 2>/dev/null || print_warn "Could not run uninstall playbook (might be expected if VMs are down)"
else
    print_warn "Ansible not found, skipping k3s uninstall"
fi

# 2. Destroy VMs
if command -v multipass &> /dev/null; then
    print_info "Destroying Multipass VMs..."

    VMS=$(multipass list --format csv | grep "k3s-" | cut -d',' -f1 || true)

    if [ -z "$VMS" ]; then
        print_info "No k3s VMs found"
    else
        for vm in $VMS; do
            print_info "Stopping and deleting: $vm"
            multipass stop $vm 2>/dev/null || true
            multipass delete $vm 2>/dev/null || true
        done

        print_info "Purging deleted VMs..."
        multipass purge
    fi
else
    print_warn "Multipass not found, skipping VM cleanup"
fi

# 3. Clean up local files
print_info "Cleaning up local cache and logs..."

# Remove Ansible cache
rm -rf /tmp/ansible_facts/* 2>/dev/null || true
rm -f "$PROJECT_ROOT/ansible/ansible.log" 2>/dev/null || true

# Remove any downloaded kubeconfigs
find "$PROJECT_ROOT" -name "*.kubeconfig" -type f -delete 2>/dev/null || true
find "$PROJECT_ROOT" -name "k3s.yaml" -type f -delete 2>/dev/null || true

# Remove any retry files
find "$PROJECT_ROOT" -name "*.retry" -type f -delete 2>/dev/null || true

print_info ""
print_info "Cleanup completed successfully!"
print_info ""
print_info "To start fresh:"
echo "  1. Run: ./scripts/test_cluster.sh create"
echo "  2. Update ansible/inventory/local.ini with IPs"
echo "  3. Run: ansible-playbook ansible/playbooks/install.yml"
