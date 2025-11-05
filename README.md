# K3s Cluster Management with Ansible

Automated Kubernetes cluster deployment and management using Ansible and k3s.

> **Quick Start**: If you just want to get a cluster up and running quickly, go directly to [QUICKSTART.md](QUICKSTART.md) for streamlined deployment instructions.

## Project Information

**Course**: Redes de Información (72.20) - ITBA 2C 2025
**Topic**: Tema 5 - Gestión del Clúster de Kubernetes

**Team Members**:
- Bengolea, Iñaki (63515) - ibengolea@itba.edu.ar
- Braun, Santos (62090) - sbraun@itba.edu.ar
- López Menardi, Félix (62707) - flopezmenardi@itba.edu.ar

## Overview

This project provides a complete automation solution for deploying and managing Kubernetes clusters using Ansible and k3s. It supports both local development using Multipass VMs on macOS with Apple Silicon and cloud deployment to AWS EC2 instances provisioned by Terraform.

### Features

- **Automated k3s cluster deployment**: One-command cluster creation with master and worker nodes
- **Dynamic cluster scaling**: Add or remove worker nodes on-demand with full automation
- **Intelligent inventory management**: Automatic IP detection and inventory updates
- **Common node configuration**: Unified setup for networking requirements (IPv4 forwarding, kernel modules)
- **Health monitoring**: Built-in verification that nodes join successfully
- **Automated cluster watching**: Continuous monitoring with auto-recovery for failed worker nodes
- **Complete cluster teardown**: Clean destruction of all resources
- **Idempotent playbooks**: Safe to run multiple times without side effects
- **Multi-environment support**: Deploy to local Multipass VMs or AWS EC2 instances via Terraform integration

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

#### 4. Monitor Cluster with Auto-Recovery

Start an automated cluster watcher that continuously monitors worker node health and automatically recovers failed nodes:

```bash
cd ansible
./scripts/watch_cluster.sh
```

This script provides:
- **Continuous monitoring**: Checks cluster health every 10 seconds
- **VM validation**: Verifies that worker VMs still exist in Multipass
- **Auto-recovery**: Automatically replaces failed worker nodes using the scale.yml playbook
- **Failure tracking**: Tracks consecutive failures before triggering recovery
- **Periodic health reports**: Runs health.yml every 60 seconds for detailed reporting

**How it works**:
Just like Kubernetes monitors pods and recreates them when they fail, our cluster watcher monitors the Multipass VMs that act as cluster nodes. While it can't handle master node failures, it provides automatic recovery for worker nodes:

1. **Detection**: Monitors `kubectl get nodes` and `multipass list` to detect missing/failed workers
2. **Validation**: Uses a failure counter to avoid false positives (3 consecutive failures required)
3. **Recovery**: When a worker VM dies or becomes unresponsive:
   - Removes the dead node from the k3s cluster
   - Deletes the failed VM from Multipass
   - Runs `scale.yml` to create a replacement worker
   - New worker automatically joins the cluster

This provides a "homemade" version of Kubernetes' self-healing capabilities at the infrastructure level, ensuring your cluster maintains the desired number of worker nodes even if VMs crash unexpectedly.

**Usage**:
```bash
# Start the watcher (runs indefinitely)
cd ansible
./scripts/watch_cluster.sh

# Monitor output for health status and auto-recovery actions
# Press Ctrl+C to stop monitoring
```

**Note**: The watcher should be run from the Ansible control node (your local machine) and requires the cluster to be already deployed.

#### 5. Destroy Cluster

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

## AWS/EC2 Deployment (Terraform Integration)

This project also supports deploying k3s clusters to AWS EC2 instances that have been provisioned by Terraform. This workflow assumes you have EC2 instances already created and configured.

### Prerequisites for AWS Deployment

1. **EC2 instances created** - At least 2 instances (1 master, 1+ workers) provisioned via Terraform
2. **Security group configuration**:
   - **SSH access (port 22)** - Your Ansible control node's public IP must be allowed
   - **Inter-instance communication** - All instances must be able to communicate with each other
   - **Kubernetes API (port 6443)** - Workers must be able to reach master on this port
   - **Kubelet (port 10250)** - For node-to-node communication
3. **SSH key** - The generated PEM key file named `master-key.pem` in `~/.ssh/` directory
4. **Inventory file** - Create `inventory_terraform.yml` with EC2 instance IPs

### AWS Deployment Steps

#### 1. Prepare Inventory File

Create `ansible/inventory_terraform.yml` with your EC2 instance information:

```yaml
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/master-key.pem
  
  children:
    master:
      hosts:
        ec2-master:
          ansible_host: YOUR_MASTER_PUBLIC_IP
    workers:
      hosts:
        ec2-worker-1:
          ansible_host: YOUR_WORKER1_PUBLIC_IP
        ec2-worker-2:
          ansible_host: YOUR_WORKER2_PUBLIC_IP  # Optional: add more workers as needed
```

#### 2. Provision (Copy Inventory)

Test connectivity and copy the Terraform inventory to the active inventory file:

```bash
cd ansible
ansible-playbook playbooks/provision.yml -e deployment_mode=terraform
```

This will:
- Check for `inventory_terraform.yml`
- Copy it to `inventory.yml` (the active inventory)
- Skip Multipass VM creation

#### 3. Deploy K3s Cluster

Deploy the k3s cluster to your EC2 instances:

```bash
cd ansible
ansible-playbook playbooks/deploy-terraform.yml
```

This will:
- Test SSH connectivity to all EC2 instances
- Configure common requirements (networking, kernel modules)
- Install K3s master on the control plane node
- Join worker nodes to the cluster
- Verify deployment and display access instructions

#### 4. Verify AWS Deployment

Check your cluster status:

```bash
# SSH to master and check nodes
ssh -i ~/.ssh/master-key.pem ubuntu@YOUR_MASTER_PUBLIC_IP sudo kubectl get nodes

# Check all pods
ssh -i ~/.ssh/master-key.pem ubuntu@YOUR_MASTER_PUBLIC_IP sudo kubectl get pods -A

# Or use Ansible for verification
ansible-playbook playbooks/health.yml
```

### Important Security Group Requirements

Ensure your AWS security group allows:

| Port | Protocol | Source | Description |
|------|----------|--------|-------------|
| 22 | TCP | Your Public IP | SSH access from Ansible control node |
| 6443 | TCP | Security Group (self) | Kubernetes API server |
| 10250 | TCP | Security Group (self) | Kubelet API |
| 8472 | UDP | Security Group (self) | Flannel VXLAN |
| All Traffic | All | Security Group (self) | Inter-node communication (recommended) |

### AWS Workflow Summary

```bash
# 1. Create inventory_terraform.yml with your EC2 IPs
# 2. Test and activate Terraform inventory
ansible-playbook playbooks/provision.yml -e deployment_mode=terraform

# 3. Deploy k3s to EC2 instances  
ansible-playbook playbooks/deploy-terraform.yml

# 4. Verify deployment
ansible-playbook playbooks/health.yml
```

**Note**: The scaling functionality (`scale.yml`) is designed for Multipass VMs and won't work with EC2 instances. For AWS scaling, use Terraform or AWS Auto Scaling Groups.

## Project Structure

```
.
├── ansible/
│   ├── playbooks/
│   │   ├── deploy-all.yml      # Complete cluster deployment (Multipass)
│   │   ├── deploy-terraform.yml # AWS/EC2 cluster deployment (Terraform integration)
│   │   ├── provision.yml       # VM provisioning (Multipass/Terraform modes)
│   │   ├── scale.yml           # Dynamic cluster scaling (add/remove workers)
│   │   ├── destroy.yml         # Complete cluster teardown (Multipass)
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
│   ├── scripts/
│   │   ├── deploy.sh           # Bash version of deploy-all playbook
│   │   └── watch_cluster.sh    # Automated cluster monitoring with worker node auto-recovery
│   ├── inventory.yml           # Dynamic inventory (auto-updated by playbooks)
│   ├── inventory_terraform.yml # Terraform/AWS inventory template (user-created)
│   ├── inventory/
│   │   └── local.ini           # Alternative static inventory format
│   ├── ansible.cfg             # Ansible configuration
│   └── requirements.yml        # Required Ansible collections
├── docs/
│   ├── components.md           # Cluster components and network architecture
│   └── Enunciado-TPE.pdf       # Project instructions
│   └── PoC.pdf                 # Initial proposal/PoC
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
- See Technical Notes section below for implementation details

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

## Deploying Applications

### The Store - E-commerce Demo Application

The project includes deployment automation for **The Store**, a microservices-based e-commerce platform with 5 services (catalog, cart, checkout, orders, UI).

#### Quick Deploy

Deploy The Store application to your k3s cluster:

```bash
cd ansible
ansible-playbook playbooks/deploy-app.yml
```

This will:
1. Ensure k3s cluster is running (deploys if needed)
2. Build Docker images for all 5 microservices
3. Distribute images to all worker nodes
4. Deploy application manifests to k3s
5. Wait for all pods to be Ready
6. Display access URL

**Access the application:**
```
http://<master-node-ip>
```

The playbook output will show the exact IP address.

#### Architecture

The Store consists of 5 microservices:

| Service | Language | Purpose |
|---------|----------|---------|
| **catalog** | Go | Product catalog with search |
| **cart** | Java (Spring Boot) | Shopping cart management |
| **orders** | Java (Spring Boot) | Order processing |
| **checkout** | Node.js (NestJS) | Checkout orchestration |
| **ui** | Java (Spring Boot) | Web frontend |

All services are deployed in the `retail-store` namespace with:
- ClusterIP services for inter-service communication
- Traefik Ingress routing external traffic to UI
- Secrets and ConfigMaps for configuration

#### Manual Build (Optional)

To rebuild images without deploying:

```bash
cd ansible
ansible-playbook playbooks/build-store-images.yml
```

Built images are saved in `ansible/images/` as tar files.

#### Verification

```bash
# Check all pods
multipass exec k3s-master -- sudo kubectl get pods -n retail-store

# Check services
multipass exec k3s-master -- sudo kubectl get svc -n retail-store

# Check ingress
multipass exec k3s-master -- sudo kubectl get ingress -n retail-store

# View logs
multipass exec k3s-master -- sudo kubectl logs -n retail-store <pod-name>
```

#### Troubleshooting

**Pods not starting:**
```bash
# Check pod details
multipass exec k3s-master -- sudo kubectl describe pod -n retail-store <pod-name>

# Check events
multipass exec k3s-master -- sudo kubectl get events -n retail-store --sort-by='.lastTimestamp'
```

**Can't access via browser:**
- Verify Ingress is configured: `kubectl get ingress -n retail-store`
- Add to `/etc/hosts`: `<master-ip> localhost`
- Check Traefik is running: `kubectl get pods -n kube-system | grep traefik`

**Images not loading:**
- Verify images on workers: `multipass exec k3s-worker-1 -- sudo ctr -n k8s.io images list | grep the-store`
- Rebuild images: `ansible-playbook playbooks/build-store-images.yml`
- Check imagePullPolicy in manifests (should be `IfNotPresent`)

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

See [docs/components.md](docs/components.md) for detailed component information and network architecture.

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

- **[Components & Architecture](docs/components.md)** - Cluster components and network architecture details

## Technical Notes

### Common Role Requirements
The `common` role configures essential requirements for k3s on all nodes:
- **IPv4 forwarding** (`net.ipv4.ip_forward=1`) - Required for pod-to-pod communication across nodes
- **Kernel modules** (`br_netfilter`, `overlay`) - Required for container networking
- **Swap disable** - Kubernetes requirement for memory management
- **Essential packages** - curl (required by k3s installer) and debugging tools

### Scale Playbook Design
The `scale.yml` playbook handles complex dynamic scaling:
- **State management** - Tracks existing workers, identifies gaps in numbering
- **Inventory manipulation** - YAML parsing, merging, automatic updates
- **Selective configuration** - Only applies roles to new workers, skips existing
- **Graceful operations** - Drains pods before removing workers
- **Comprehensive validation** - Prevents invalid operations, provides clear feedback

### Multi-Environment Support
- **Local Development**: Multipass VMs with automatic IP detection
- **Cloud Deployment**: AWS EC2 integration via Terraform inventory
- **Smart Provisioning**: Single playbook detects environment and adapts behavior
