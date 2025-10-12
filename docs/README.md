# Documentation

## Quick Start

### Prerequisites

1. **Ansible Core** (version 2.12+)
   ```bash
   pip install ansible
   ```

2. **Multipass** (for local VMs)
   ```bash
   # macOS
   brew install multipass
   ```

3. **SSH access** configured

### Installation

1. **Create VMs**
   ```bash
   cd scripts
   ./test_cluster.sh create
   ```

2. **Install cluster**
   ```bash
   cd ansible
   ansible-playbook playbooks/install.yml
   ```

3. **Check status**
   ```bash
   ansible-playbook playbooks/status.yml
   ```

## Playbooks

### install.yml
Complete cluster installation:
- Provisions all nodes with common dependencies
- Installs k3s master (control plane)
- Joins worker nodes to the cluster

```bash
ansible-playbook playbooks/install.yml
```

### scale.yml
Add or remove worker nodes:

```bash
# Interactive mode
ansible-playbook playbooks/scale.yml

# Or with parameters
ansible-playbook playbooks/scale.yml -e "action=add node_count=2"
```

### status.yml
Check cluster health and status:

```bash
ansible-playbook playbooks/status.yml
```

### uninstall.yml
Remove k3s from all nodes:

```bash
ansible-playbook playbooks/uninstall.yml
```

## Architecture

See `arquitectura.png` for visual representation.

### Components

- **Control Plane (Master)**: 1 node running k3s server
- **Worker Nodes**: 2+ nodes running k3s agents
- **Network**: 192.168.64.0/24 (Multipass default)
- **CNI**: Flannel (included in k3s)

### Roles

- **common**: Base configuration for all nodes
- **master**: k3s control plane setup
- **worker**: k3s agent configuration

## Inventory

Two inventory files are provided:

- `local.ini`: For Multipass VMs (default)
- `aws.ini`: Template for AWS deployment (future)

## Configuration

### Variables

Global variables in playbooks:
- `k3s_version`: k3s version to install (default: latest)
- `timezone`: System timezone
- `k3s_server_options`: Additional k3s server flags
- `k3s_agent_options`: Additional k3s agent flags

### Customization

Edit inventory files to:
- Change IP addresses
- Add/remove nodes
- Modify SSH settings

## Troubleshooting

### Can't connect to VMs

```bash
# Check VMs are running
multipass list

# Test SSH connectivity
ansible all -m ping
```

### k3s installation fails

```bash
# Check logs on master
multipass exec k3s-master -- sudo journalctl -u k3s

# Check logs on worker
multipass exec k3s-worker-1 -- sudo journalctl -u k3s-agent
```

### Node not joining cluster

```bash
# Verify master is accessible
ansible master -m shell -a "kubectl get nodes"

# Check token on master
ansible master -m shell -a "cat /var/lib/rancher/k3s/server/node-token"
```

## More Information

- See `PoC.pdf` for detailed proof of concept
- See main `README.md` in project root
- See context files for assignment details
