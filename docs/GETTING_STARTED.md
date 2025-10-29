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

## Terraform Integration

This project supports deploying to AWS EC2 instances provisioned by Terraform, in addition to local Multipass VMs.

### Prerequisites for Terraform Mode

1. **EC2 Instances**: 1 master + N worker instances created by Terraform (or another group).
2. **SSH Key**: A private key (`.pem`) file for accessing the instances as `ubuntu` or `ec2-user`.
3. **Inventory File**: Create `inventory_terraform.yml` in the repository root with your EC2 IPs and SSH key path.

### Example inventory_terraform.yml

```yaml
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ~/.ssh/terraform_key.pem
  children:
    master:
      hosts:
        ec2-master:
          ansible_host: 3.88.45.101   # Replace with your EC2 public/private IP
    workers:
      hosts:
        ec2-worker-1:
          ansible_host: 3.92.176.42
        ec2-worker-2:
          ansible_host: 44.200.67.89
```

**Notes**:
- Use absolute paths for `ansible_ssh_private_key_file` (e.g., `/Users/saints/.ssh/terraform_key.pem`) to avoid expansion issues.
- Ensure the key file has permissions `chmod 600`.
- Confirm the `ansible_user` matches your AMI (e.g., `ubuntu` for Ubuntu AMIs, `ec2-user` for Amazon Linux).

### Quick Start with Terraform

1. **Prepare Inventory**: Create `inventory_terraform.yml` as shown above.

2. **Provision (Skip VM Creation)**:
   ```bash
   ansible-playbook ansible/playbooks/provision.yml -e deployment_mode=terraform
   ```
   This copies `inventory_terraform.yml` to `inventory.yml` and skips Multipass provisioning.

3. **Install Cluster**:
   ```bash
   ansible-playbook ansible/playbooks/install.yml
   ```

4. **Check Status**:
   ```bash
   ansible-playbook ansible/playbooks/status.yml
   ```

### Key Differences from Multipass Mode

- No local VM creation; assumes EC2 instances are already running.
- Use your `.pem` key for SSH authentication.
- The `provision.yml` playbook respects `deployment_mode=terraform` to skip Multipass tasks.
- If `inventory_terraform.yml` is missing, the playbook will warn you to provide it.

### Troubleshooting Terraform Mode

- **SSH Connection Fails**: Test manually:
  ```bash
  ssh -i ~/.ssh/terraform_key.pem ubuntu@<ec2-ip>
  ```
- **Ansible Ping Fails**: Use verbose mode:
  ```bash
  ansible all -i inventory_terraform.yml -m ping -vvvv
  ```
- **Key Permissions**: Ensure `chmod 600 ~/.ssh/terraform_key.pem`.
- **Wrong User**: Check AMI documentation for the correct SSH user.
