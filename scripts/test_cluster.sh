#!/bin/bash
# Script to manage test cluster lifecycle

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

# Configuration
MASTER_NAME="k3s-master"
WORKER_PREFIX="k3s-worker"
DEFAULT_WORKERS=2

# VM specs
CPUS=2
MEMORY="2G"
DISK="10G"
IMAGE="jammy"  # Ubuntu 22.04 LTS

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function check_multipass() {
    if ! command -v multipass &> /dev/null; then
        print_error "Multipass is not installed"
        echo "Install it with: brew install multipass"
        exit 1
    fi
}

function create_cluster() {
    local num_workers=${1:-$DEFAULT_WORKERS}

    print_info "Creating k3s cluster with 1 master and $num_workers workers..."

    # Create master
    print_info "Creating master node: $MASTER_NAME"
    multipass launch --name $MASTER_NAME \
        --cpus $CPUS \
        --memory $MEMORY \
        --disk $DISK \
        $IMAGE

    # Create workers
    for i in $(seq 1 $num_workers); do
        WORKER_NAME="${WORKER_PREFIX}-${i}"
        print_info "Creating worker node: $WORKER_NAME"
        multipass launch --name $WORKER_NAME \
            --cpus $CPUS \
            --memory $MEMORY \
            --disk $DISK \
            $IMAGE
    done

    print_info "Waiting for VMs to be ready..."
    sleep 5

    print_info "VMs created successfully!"
    multipass list

    print_info ""
    print_info "Next steps:"
    echo "  1. Verify SSH access: ansible all -m ping"
    echo "  2. Install cluster: ansible-playbook ansible/playbooks/install.yml"
}

function destroy_cluster() {
    print_warn "This will destroy all k3s VMs!"
    read -p "Are you sure? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "Aborted"
        exit 0
    fi

    print_info "Destroying k3s cluster VMs..."

    VMS=$(multipass list --format csv | grep "k3s-" | cut -d',' -f1 || true)

    if [ -z "$VMS" ]; then
        print_warn "No k3s VMs found"
        exit 0
    fi

    for vm in $VMS; do
        print_info "Stopping and deleting: $vm"
        multipass stop $vm 2>/dev/null || true
        multipass delete $vm 2>/dev/null || true
    done

    print_info "Purging deleted VMs..."
    multipass purge

    print_info "All k3s VMs destroyed successfully!"
}

function list_vms() {
    print_info "k3s cluster VMs:"
    multipass list | grep -E "(Name|k3s-)" || print_warn "No k3s VMs found"
}

function get_ips() {
    print_info "k3s VM IP addresses:"
    VMS=$(multipass list --format csv | grep "k3s-" | cut -d',' -f1 || true)

    if [ -z "$VMS" ]; then
        print_warn "No k3s VMs found"
        exit 0
    fi

    for vm in $VMS; do
        IP=$(multipass info $vm | grep IPv4 | awk '{print $2}')
        echo "  $vm: $IP"
    done
}

function ssh_to_vm() {
    local vm_name=$1

    if [ -z "$vm_name" ]; then
        print_error "VM name required"
        echo "Usage: $0 ssh <vm-name>"
        exit 1
    fi

    print_info "Connecting to $vm_name..."
    multipass shell $vm_name
}

function scale_cluster() {
    local num_workers=$1

    if [ -z "$num_workers" ]; then
        print_error "Number of workers required"
        echo "Usage: $0 scale <number>"
        exit 1
    fi

    CURRENT_WORKERS=$(multipass list --format csv | grep -c "k3s-worker" || echo 0)
    print_info "Current workers: $CURRENT_WORKERS"
    print_info "Target workers: $num_workers"

    if [ $num_workers -gt $CURRENT_WORKERS ]; then
        # Add workers
        ADD_COUNT=$((num_workers - CURRENT_WORKERS))
        print_info "Adding $ADD_COUNT worker(s)..."

        for i in $(seq $((CURRENT_WORKERS + 1)) $num_workers); do
            WORKER_NAME="${WORKER_PREFIX}-${i}"
            print_info "Creating worker node: $WORKER_NAME"
            multipass launch --name $WORKER_NAME \
                --cpus $CPUS \
                --memory $MEMORY \
                --disk $DISK \
                $IMAGE
        done

        print_info "Workers added. Run: ansible-playbook ansible/playbooks/scale.yml -e 'action=add'"

    elif [ $num_workers -lt $CURRENT_WORKERS ]; then
        # Remove workers
        print_warn "Removing workers is not fully automated"
        print_info "Run: ansible-playbook ansible/playbooks/scale.yml -e 'action=remove'"
    else
        print_info "Already at target worker count"
    fi
}

function show_help() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
    create [N]      Create cluster with N workers (default: $DEFAULT_WORKERS)
    destroy         Destroy all cluster VMs
    list            List all k3s VMs
    ips             Show IP addresses of all VMs
    ssh <name>      SSH into a VM
    scale <N>       Scale to N worker nodes
    help            Show this help message

Examples:
    $0 create           # Create cluster with $DEFAULT_WORKERS workers
    $0 create 3         # Create cluster with 3 workers
    $0 list             # List all VMs
    $0 ips              # Show VM IPs
    $0 ssh k3s-master   # SSH to master
    $0 scale 4          # Scale to 4 workers
    $0 destroy          # Destroy cluster

After creating VMs:
    1. Update ansible/inventory/local.ini with actual IPs
    2. Test connectivity: ansible all -m ping
    3. Install cluster: ansible-playbook ansible/playbooks/install.yml

EOF
}

# Main
check_multipass

case "${1:-help}" in
    create)
        create_cluster ${2:-$DEFAULT_WORKERS}
        ;;
    destroy)
        destroy_cluster
        ;;
    list)
        list_vms
        ;;
    ips)
        get_ips
        ;;
    ssh)
        ssh_to_vm $2
        ;;
    scale)
        scale_cluster $2
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
