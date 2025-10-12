# Getting Started

## Prerequisites

Before you begin, ensure you have the following installed:

1. **Ansible Core** (version 2.12 or later)
   ```bash
   pip install ansible
   ```

2. **Multipass** (for VM management)
   ```bash
   # macOS
   brew install multipass
   ```

3. **SSH access** configured for your VMs

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd tpe-redes
```

### 2. Install Ansible Dependencies

```bash
ansible-galaxy install -r requirements.yml
```

### 3. Create VMs with Multipass

```bash
./scripts/create-vms.sh
```

This will create:
- 1 control plane node (k3s-master)
- 2 worker nodes (k3s-worker-1, k3s-worker-2)

### 4. Update Inventory

Get the IP addresses of your VMs:

```bash
multipass list
```

Update `inventory/hosts.yml` with the actual IP addresses.

### 5. Test Connectivity

```bash
ansible all -m ping
```

### 6. Provision the Cluster

Run the playbooks in sequence:

```bash
# Provision all nodes
ansible-playbook playbooks/provision.yml

# Initialize control plane
ansible-playbook playbooks/control-plane.yml

# Join worker nodes
ansible-playbook playbooks/join-workers.yml

# Check cluster status
ansible-playbook playbooks/status.yml
```

## Next Steps

- Read the [Pre-Entrega document](../context/Pre-Entrega-Redes.pdf) for architectural details
- Explore individual playbooks in the `playbooks/` directory
- Customize variables in `group_vars/` as needed

## Troubleshooting

### VMs not accessible via SSH

Ensure you can SSH into the VMs manually:
```bash
multipass shell k3s-master
```

### Ansible connection issues

Check your inventory file and ensure IP addresses are correct:
```bash
ansible all -m ping -vvv
```

### k3s installation fails

Check logs on the target node:
```bash
multipass exec k3s-master -- sudo journalctl -u k3s
```
