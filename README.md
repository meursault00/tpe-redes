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

This project provides a complete automation solution for deploying and managing Kubernetes clusters using Ansible and k3s. It supports both local development (Multipass VMs) and cloud deployment (AWS with Terraform integration).

### Features

- Automated k3s cluster installation
- Dynamic cluster scaling (add/remove workers)
- Health monitoring and status checks
- Complete cluster teardown
- Support for local and cloud deployments
- Idempotent playbooks (safe to run multiple times)

## Quick Start

### Prerequisites

1. **Ansible Core** (2.12+)
   ```bash
   pip install ansible
   ```

2. **Multipass** (for local VMs)
   ```bash
   # macOS
   brew install multipass
   ```

3. **Install Ansible collections**
   ```bash
   ansible-galaxy collection install -r ansible/requirements.yml
   ```

### Setup

1. **Create VMs**
   ```bash
   ./scripts/test_cluster.sh create
   ```

2. **Update inventory** (if needed)

   Edit `ansible/inventory/local.ini` with actual VM IPs:
   ```bash
   ./scripts/test_cluster.sh ips
   ```

3. **Test connectivity**
   ```bash
   cd ansible
   ansible all -m ping
   ```

4. **Install cluster**
   ```bash
   ansible-playbook playbooks/deploy-all.yml
   ```

5. **Check status**
   ```bash
   ansible-playbook playbooks/status.yml
   ```

## Project Structure

```
.
├── ansible/
│   ├── playbooks/          # Ansible playbooks
│   │   ├── deploy-all.yml  # Complete cluster installation
│   │   ├── scale.yml       # Scale cluster up/down
│   │   ├── status.yml      # Check cluster health
│   │   └── uninstall.yml   # Remove k3s completely
│   ├── roles/              # Ansible roles
│   │   ├── common/         # Common setup for all nodes
│   │   ├── master/         # Control plane configuration
│   │   └── worker/         # Worker node configuration
│   ├── inventory/          # Inventory files
│   │   ├── local.ini       # Local Multipass VMs
│   │   └── aws.ini         # AWS deployment (template)
│   └── ansible.cfg         # Ansible configuration
├── docs/                   # Documentation
│   ├── README.md           # Detailed docs
│   ├── arquitectura.md     # Architecture diagrams
│   └── PoC.pdf            # Proof of Concept
├── scripts/                # Utility scripts
│   ├── test_cluster.sh     # Cluster lifecycle management
│   └── cleanup.sh          # Complete cleanup
├── context/                # Assignment documents
└── README.md               # This file
```

## Usage

### Install Cluster

Complete installation (provision VMs + setup SSH + install k3s on master + join workers):

```bash
cd ansible
ansible-playbook playbooks/deploy-all.yml
```

### Check Status

View cluster health, nodes, pods, and services:

```bash
ansible-playbook playbooks/status.yml
```

### Scale Cluster

Add or remove worker nodes:

```bash
# Interactive mode
ansible-playbook playbooks/scale.yml

# Or with parameters
ansible-playbook playbooks/scale.yml -e "action=add node_count=2"
```

### Uninstall

Remove k3s from all nodes:

```bash
ansible-playbook playbooks/uninstall.yml
```

### Complete Cleanup

Uninstall k3s, destroy VMs, and clean up local files:

```bash
cd scripts
./cleanup.sh
```

## Scripts

### test_cluster.sh

Main script for cluster lifecycle management:

```bash
./scripts/test_cluster.sh create [N]   # Create cluster with N workers
./scripts/test_cluster.sh list          # List all VMs
./scripts/test_cluster.sh ips           # Show VM IPs
./scripts/test_cluster.sh ssh <name>    # SSH to a VM
./scripts/test_cluster.sh scale <N>     # Scale to N workers
./scripts/test_cluster.sh destroy       # Destroy all VMs
```

### cleanup.sh

Complete cleanup of all resources:

```bash
./scripts/cleanup.sh
```

## Architecture

### Components

- **Control Plane (Master)**: 1 node running k3s server
  - API Server, Scheduler, Controller Manager, etcd
  - IP: 192.168.64.23

- **Worker Nodes**: 2+ nodes running k3s agents
  - kubelet, kube-proxy, containerd
  - IPs: 192.168.64.24, 192.168.64.25

- **Network**:
  - Host: 192.168.64.0/24
  - Pods: 10.42.0.0/16 (Flannel)
  - Services: 10.43.0.0/16

See [docs/arquitectura.md](docs/arquitectura.md) for detailed architecture.

## Configuration

### Inventory

Two inventory files are provided:
- `local.ini`: Multipass VMs (default)
- `aws.ini`: AWS EC2 instances (template for future use)

### Variables

Customize in playbooks or inventory:
- `k3s_version`: k3s version (default: latest)
- `timezone`: System timezone
- `k3s_server_options`: Additional k3s server flags
- `k3s_agent_options`: Additional k3s agent flags

## Troubleshooting

### Can't connect to VMs

```bash
# Check VMs are running
multipass list

# Verify IPs match inventory
./scripts/test_cluster.sh ips

# Test SSH
ansible all -m ping -vvv
```

### k3s installation fails

```bash
# Check master logs
multipass exec k3s-master -- sudo journalctl -u k3s -f

# Check worker logs
multipass exec k3s-worker-1 -- sudo journalctl -u k3s-agent -f
```

### Worker not joining

```bash
# Verify master is accessible
ansible master -m shell -a "kubectl get nodes"

# Check token
ansible master -m shell -a "cat /var/lib/rancher/k3s/server/node-token"

# Manually test connection from worker
multipass exec k3s-worker-1 -- curl -k https://192.168.64.23:6443
```

## Development

### Testing Playbooks

```bash
# Syntax check
ansible-playbook playbooks/install.yml --syntax-check

# Dry run
ansible-playbook playbooks/install.yml --check

# Verbose output
ansible-playbook playbooks/install.yml -vvv
```

### Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for team guidelines.

## Documentation

- [Detailed Documentation](docs/README.md)
- [Architecture Diagrams](docs/arquitectura.md)
- [Proof of Concept](docs/PoC.pdf)
- [Assignment Details](context/)

## Important Dates

- **Pre-entrega**: Miércoles 24 de Septiembre (DONE)
- **Entrega Final**: Miércoles 5 de Noviembre
- **Presentaciones**: Jueves 6 y Martes 11 de Noviembre

## License

Academic project - ITBA 2025

## Support

For questions or issues, contact any team member via email.
