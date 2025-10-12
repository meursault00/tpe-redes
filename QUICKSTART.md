# Quick Start Guide

## One-Time Setup

```bash
# 1. Install dependencies
pip install ansible
brew install multipass  # macOS

# 2. Install Ansible collections
ansible-galaxy collection install -r ansible/requirements.yml
```

## Create and Deploy Cluster

```bash
# 1. Create VMs
./scripts/test_cluster.sh create

# 2. Get IPs and update inventory if needed
./scripts/test_cluster.sh ips

# 3. Test connectivity
cd ansible
ansible all -m ping

# 4. Install k3s cluster
ansible-playbook playbooks/install.yml

# 5. Check status
ansible-playbook playbooks/status.yml
```

## Daily Operations

```bash
# Check cluster status
ansible-playbook playbooks/status.yml

# Scale to 3 workers
./scripts/test_cluster.sh scale 3
ansible-playbook playbooks/scale.yml -e "action=add"

# Scale down to 2 workers
ansible-playbook playbooks/scale.yml -e "action=remove node_count=1"

# SSH to master
./scripts/test_cluster.sh ssh k3s-master

# Run kubectl commands
multipass exec k3s-master -- kubectl get nodes
multipass exec k3s-master -- kubectl get pods --all-namespaces
```

## Cleanup

```bash
# Complete cleanup (uninstall + destroy VMs + clean files)
./scripts/cleanup.sh

# Or step by step:
ansible-playbook ansible/playbooks/uninstall.yml  # Uninstall k3s
./scripts/test_cluster.sh destroy                  # Destroy VMs
```

## Troubleshooting

```bash
# Check VMs
multipass list

# Get VM IPs
./scripts/test_cluster.sh ips

# Test Ansible connection
ansible all -m ping -vvv

# Check k3s logs
multipass exec k3s-master -- sudo journalctl -u k3s -f
multipass exec k3s-worker-1 -- sudo journalctl -u k3s-agent -f

# SSH to troubleshoot
./scripts/test_cluster.sh ssh k3s-master
```

## File Locations

- Playbooks: `ansible/playbooks/*.yml`
- Roles: `ansible/roles/{common,master,worker}/`
- Inventory: `ansible/inventory/local.ini`
- Config: `ansible/ansible.cfg`
- Scripts: `scripts/*.sh`
- Docs: `docs/*.md`

## Git Workflow

```bash
# Initial commit
git init
git add .
git commit -m "feat: initial k3s cluster management structure

- Add ansible playbooks for install, scale, status, uninstall
- Implement roles for common, master, and worker nodes
- Add cluster management scripts
- Include comprehensive documentation"

git remote add origin <your-repo-url>
git push -u origin main
```
