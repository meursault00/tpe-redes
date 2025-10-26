# K3s Cluster Management with Ansible

Automated Kubernetes cluster deployment and management using Ansible and k3s.

## Project Information

**Course**: Redes de Información (72.20) - ITBA 2C 2025
**Topic**: Tema 5 - Gestión del Clúster de Kubernetes

**Team Members**:
- Bengolea, Iñaki (63515) - ibengolea@itba.edu.ar
- Braun, Santos (62090) - sbraun@itba.edu.ar
- López Menardi, Félix (62707) - flopezmenardi@itba.edu.ar

## Overview

This project provides a complete automation solution for deploying and managing Kubernetes clusters using Ansible and k3s. It supports local development using Multipass VMs on macOS with Apple Silicon.

### Features

- **Automated k3s cluster deployment**: One-command cluster creation with master and worker nodes
- **Dynamic cluster scaling**: Add or remove worker nodes on-demand with full automation
- **Intelligent inventory management**: Automatic IP detection and inventory updates
- **Common node configuration**: Unified setup for networking requirements (IPv4 forwarding, kernel modules)
- **Health monitoring**: Built-in verification that nodes join successfully
- **Complete cluster teardown**: Clean destruction of all resources
- **Idempotent playbooks**: Safe to run multiple times without side effects

## Quick Start

### Prerequisites

1. **Ansible Core** (2.12+)
   ```bash
   pip install ansible
   ```

2. **Multipass** (for local VMs on macOS)
   ```bash
   brew install multipass
   ```

3. **Install Ansible collections**
   ```bash
   ansible-galaxy collection install -r ansible/requirements.yml
   ```

4. **SSH Key Setup**

   The playbooks expect an SSH key at `~/.ssh/multipass_id_rsa`. This is automatically configured during VM provisioning.

### Deployment

#### 1. Deploy Complete Cluster

Deploy a new k3s cluster with 1 master and 2 worker nodes:

```bash
cd ansible
ansible-playbook playbooks/deploy-all.yml
```

This playbook will:
- Create 3 Multipass VMs (k3s-master, k3s-worker-1, k3s-worker-2)
- Auto-detect their IP addresses
- Update `inventory.yml` dynamically
- Configure all nodes with common requirements (networking, kernel modules)
- Install k3s master node
- Join worker nodes to the cluster
- Verify cluster health

**Expected output**: All nodes Ready in ~3-4 minutes

#### 2. Verify Cluster

```bash
# Check cluster status
multipass exec k3s-master -- sudo kubectl get nodes

# Check all pods
multipass exec k3s-master -- sudo kubectl get pods -A
```

#### 3. Scale Cluster

Add or remove worker nodes dynamically:

```bash
cd ansible

# Add 2 workers (creates k3s-worker-3, k3s-worker-4)
ansible-playbook -i inventory.yml playbooks/scale.yml -e "action=add node_count=2"

# Remove 1 worker (removes last worker, properly draining pods)
ansible-playbook -i inventory.yml playbooks/scale.yml -e "action=remove node_count=1"
```

**Note**: Always run scale.yml from the `ansible/` directory to ensure proper role path resolution.

#### 4. Destroy Cluster

Clean up all resources:

```bash
cd ansible
ansible-playbook playbooks/destroy.yml
```

This will:
- Discover all k3s-related VMs
- Stop and delete all VMs
- Purge deleted VMs from Multipass
- Reset inventory.yml to empty state

## Project Structure

```
.
├── ansible/
│   ├── playbooks/
│   │   ├── deploy-all.yml      # Complete cluster deployment
│   │   ├── provision.yml       # VM provisioning (called by deploy-all.yml)
│   │   ├── scale.yml           # Dynamic cluster scaling (add/remove workers)
│   │   ├── destroy.yml         # Complete cluster teardown
│   │   ├── cloud-init.yml      # Cloud-init configuration for VMs
│   │   └── join-token.txt      # K3s join token (generated, not in git)
│   ├── roles/
│   │   ├── common/             # Common setup for all nodes
│   │   │   └── tasks/
│   │   │       └── main.yml    # IPv4 forwarding, kernel modules, packages
│   │   ├── master/             # K3s master/control plane setup
│   │   │   └── tasks/
│   │   │       └── main.yml    # K3s server installation
│   │   └── worker/             # K3s worker/agent setup
│   │       └── tasks/
│   │           └── main.yml    # K3s agent installation and join
│   ├── inventory.yml           # Dynamic inventory (auto-updated by playbooks)
│   ├── inventory/
│   │   └── local.ini           # Alternative static inventory format
│   ├── ansible.cfg             # Ansible configuration
│   └── requirements.yml        # Required Ansible collections
├── docs/
│   ├── arquitectura.md         # Architecture documentation
│   ├── IMPLEMENTATION.md       # Implementation decisions and justifications (NEW)
│   └── Pre-Entrega-Redes.pdf  # Initial proposal/PoC
├── context/                    # Assignment materials
└── README.md                   # This file
```

## Core Playbooks

### deploy-all.yml

Complete cluster deployment pipeline:

1. **SSH Key Setup**: Verifies SSH key exists
2. **Provision VMs**: Creates master and workers with cloud-init
3. **Dynamic Inventory**: Auto-detects IPs and updates inventory.yml
4. **Common Configuration**: Configures networking requirements on all nodes
5. **Master Installation**: Installs k3s server
6. **Worker Join**: Joins workers to cluster
7. **Verification**: Confirms cluster is healthy

**Usage**:
```bash
cd ansible
ansible-playbook playbooks/deploy-all.yml
```

### scale.yml

Dynamic cluster scaling with full automation (589 lines):

**Features**:
- Input validation (action must be add/remove, node_count 1-10)
- Prevents invalid operations (e.g., removing more workers than exist)
- Auto-detects next worker number (handles gaps: if worker-3 is missing, creates worker-4)
- Creates VMs with IP address retry logic
- Updates inventory.yml automatically after add/remove
- Applies common role only to new workers (skips existing)
- Proper kubectl drain before removal
- Removes nodes from k3s cluster before VM deletion
- Comprehensive verification and status display

**Scale Up Process**:
1. Validate inputs
2. Create new Multipass VMs
3. Detect and capture IP addresses
4. Update inventory.yml with new workers
5. Refresh Ansible inventory
6. Apply common role (networking setup) to new workers only
7. Join new workers to k3s cluster
8. Verify nodes are Ready
9. Display success summary

**Scale Down Process**:
1. Validate inputs
2. Identify workers to remove (last N workers)
3. Drain pods from workers gracefully
4. Delete nodes from k3s cluster
5. Stop and delete VMs
6. Update inventory.yml to remove workers
7. Refresh Ansible inventory
8. Display final cluster state

**Usage**:
```bash
cd ansible

# Add workers
ansible-playbook -i inventory.yml playbooks/scale.yml -e "action=add node_count=2"

# Remove workers
ansible-playbook -i inventory.yml playbooks/scale.yml -e "action=remove node_count=1"
```

### destroy.yml

Intelligent cluster teardown:

- Dynamically discovers all k3s VMs (not hardcoded list)
- Handles any number of workers
- Stops, deletes, and purges all k3s VMs
- Resets inventory.yml to empty state
- Creates backup before modifying inventory

**Usage**:
```bash
cd ansible
ansible-playbook playbooks/destroy.yml
```

## Roles

### common

Prepares all nodes (master and workers) with required system configuration:

**Critical tasks**:
- Enable IPv4 forwarding (net.ipv4.ip_forward=1) - Required for pod-to-pod communication across nodes
- Load kernel modules (br_netfilter, overlay) - Required for container networking
- Disable swap (Kubernetes requirement)
- Install essential packages (curl for k3s installer, plus debugging tools)

**Why this is separate**:
- k3s requires specific networking configuration
- Must be applied before k3s installation
- Common to both master and worker nodes
- See [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) for detailed justification

### master

Installs and configures k3s control plane:

- Installs k3s server
- Waits for API server to be ready
- Extracts node join token
- Saves token for worker nodes

### worker

Joins worker nodes to the cluster:

- Reads join token from master
- Installs k3s agent
- Configures connection to master node
- Verifies successful join

## Architecture

### Network Topology

- **Host Network**: 192.168.64.0/24 (Multipass default)
- **Pod Network**: 10.42.0.0/16 (Flannel CNI)
- **Service Network**: 10.43.0.0/16 (k3s default)

### Current Deployment

After running `deploy-all.yml`:

```
k3s-master      192.168.64.37    control-plane,master
k3s-worker-1    192.168.64.38    worker
k3s-worker-2    192.168.64.39    worker
```

*Note: IPs are dynamically assigned by Multipass and may differ*

### Components

- **Master Node**: Runs k3s server (API server, scheduler, controller manager, embedded etcd)
- **Worker Nodes**: Run k3s agent (kubelet, kube-proxy, containerd)
- **CNI**: Flannel (included with k3s)
- **Storage**: Local-path provisioner (included with k3s)
- **Ingress**: Traefik (included with k3s)

See [docs/arquitectura.md](docs/arquitectura.md) for detailed diagrams.

## Configuration

### Inventory Management

The project uses **dynamic inventory management**:

- `inventory.yml`: Main inventory file, automatically updated by playbooks
- Gets populated during `deploy-all.yml` with actual VM IPs
- Updated by `scale.yml` when adding/removing workers
- Reset to empty state by `destroy.yml`

**Do not manually edit inventory.yml** - it's managed by automation.

### Ansible Configuration

`ansible.cfg` settings:
- Roles path: `./roles` (relative to ansible/ directory)
- Inventory: `./inventory.yml`
- Host key checking: Disabled (for development)
- SSH connection optimization enabled

### Variables

Default variables (can be overridden):
- `k3s_version`: Latest stable (auto-detected by k3s installer)
- `timezone`: UTC (configurable in common role)
- Python interpreter: `/usr/bin/python3`
- SSH key: `~/.ssh/multipass_id_rsa`

## Troubleshooting

### VMs not accessible

```bash
# Check VMs are running
multipass list

# Verify inventory has correct IPs
cat ansible/inventory.yml

# Test connectivity
cd ansible
ansible all -m ping
```

### Scale playbook fails with "role not found"

Ensure you're running from the `ansible/` directory:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/scale.yml -e "action=add node_count=1"
```

### Worker nodes not joining cluster

```bash
# Check master is accessible
multipass exec k3s-master -- sudo kubectl get nodes

# Verify join token exists
cat ansible/playbooks/join-token.txt

# Check worker logs
multipass exec k3s-worker-1 -- sudo journalctl -u k3s-agent -f

# Manually test connectivity from worker
multipass exec k3s-worker-1 -- curl -k https://192.168.64.37:6443
```

### Orphaned VMs after testing

If you have leftover VMs that aren't in inventory:

```bash
# List all VMs
multipass list

# Destroy ALL k3s VMs (clean slate)
cd ansible
ansible-playbook playbooks/destroy.yml

# This now auto-discovers all k3s-* VMs regardless of inventory
```

### Inventory not updating after scale operations

This was a known issue that's been fixed. The scale playbook now:
- Backs up inventory before modifications
- Properly updates inventory after add/remove operations
- Refreshes Ansible's in-memory inventory

If you still see stale data, check for file editor conflicts (IDE may have cached the old version).

## Development Workflow

### Testing Changes

```bash
# 1. Start fresh
cd ansible
ansible-playbook playbooks/destroy.yml

# 2. Deploy cluster
ansible-playbook playbooks/deploy-all.yml

# 3. Test scaling up
ansible-playbook -i inventory.yml playbooks/scale.yml -e "action=add node_count=2"

# 4. Verify
multipass exec k3s-master -- sudo kubectl get nodes

# 5. Test scaling down
ansible-playbook -i inventory.yml playbooks/scale.yml -e "action=remove node_count=2"

# 6. Verify cleanup
multipass list
cat inventory.yml
```

### Syntax Checking

```bash
# Check playbook syntax
ansible-playbook playbooks/scale.yml --syntax-check

# Dry run (check mode)
ansible-playbook playbooks/deploy-all.yml --check

# Verbose output for debugging
ansible-playbook playbooks/scale.yml -vvv -e "action=add node_count=1"
```

## Git Workflow

### Before Pushing

Clean up temporary files:

```bash
# Remove backup files
rm ansible/inventory.yml.*~

# Remove generated secrets
rm ansible/playbooks/join-token.txt

# Remove logs
rm ansible/ansible.log

# These are already in .gitignore, but clean anyway for hygiene
```

### Files Not Tracked by Git

- `ansible.log` - Ansible execution logs
- `*.retry` - Ansible retry files
- `join-token.txt` - K3s cluster token (secret)
- `inventory.yml.*~` - Inventory backup files
- SSH keys (`*.pem`, `*.key`, `id_rsa*`)

See `.gitignore` for complete list.

## Documentation

- **[Implementation Details](docs/IMPLEMENTATION.md)** - Detailed explanation of design decisions and justifications
- **[Architecture](docs/arquitectura.md)** - Network diagrams and component overview
- **[Pre-entrega PoC](docs/Pre-Entrega-Redes.pdf)** - Initial proposal

## Key Design Decisions

For detailed justifications of implementation choices, see [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md), which covers:

- Why we use the common role (networking requirements)
- Why scale.yml is 589 lines (robustness vs. simplicity)
- Why we use dynamic inventory management
- Why destroy.yml auto-discovers VMs
- Trade-offs between code complexity and reliability

## Important Dates

- **Pre-entrega**: Miércoles 24 de Septiembre ✅ DONE
- **Entrega Final**: Miércoles 5 de Noviembre
- **Presentaciones**: Jueves 6 y Martes 11 de Noviembre

## License

Academic project - ITBA 2025

## Support

For questions or issues, contact any team member via email.
