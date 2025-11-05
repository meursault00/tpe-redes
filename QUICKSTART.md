# Quick Start Guide

## One-Time Setup

```bash
# 1. Install dependencies
pip install ansible
brew install multipass  # macOS

# 2. Install Ansible collections
cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Local Deployment (Multipass)

```bash
# 1. Deploy complete cluster (creates VMs + installs k3s)
cd ansible
ansible-playbook playbooks/deploy-all.yml

# 2. Verify cluster
multipass exec k3s-master -- sudo kubectl get nodes
```

## Deploy The Store Application

```bash
# Deploy e-commerce demo app (5 microservices)
cd ansible
ansible-playbook playbooks/deploy-app.yml

# Access at: http://<master-ip> (IP shown in playbook output)
```

## Cluster Monitoring with Auto-Recovery

```bash
# Start cluster watcher (runs forever, monitors worker node health)
cd ansible
./scripts/watch_cluster.sh

# In separate terminal, continue normal operations
# Watcher will auto-replace failed worker VMs
```

## Daily Operations

```bash
# Check cluster health
ansible-playbook playbooks/health.yml

# Check detailed status
ansible-playbook playbooks/status.yml

# Scale up (add 2 workers)
ansible-playbook playbooks/scale.yml -e "action=add node_count=2"

# Scale down (remove 1 worker)  
ansible-playbook playbooks/scale.yml -e "action=remove node_count=1"

# SSH to master
multipass exec k3s-master -- bash

# Run kubectl commands
multipass exec k3s-master -- sudo kubectl get pods -A
```

## Cleanup

```bash
# Destroy entire cluster and VMs
cd ansible
ansible-playbook playbooks/destroy.yml
```

## Terraform Deployment (AWS EC2)

```bash
# 1. Create inventory_terraform.yml with EC2 IPs and SSH key
# 2. Test connectivity and copy inventory
ansible-playbook playbooks/provision.yml -e deployment_mode=terraform

# 3. Deploy k3s to EC2
ansible-playbook playbooks/deploy-terraform.yml

# 4. Verify
ansible-playbook playbooks/health.yml
```

**Requirements**: EC2 instances with proper security groups, `master-key.pem` in `~/.ssh/`

## Troubleshooting

```bash
# Check VMs
multipass list

# Test Ansible connection
ansible all -m ping -vvv

# Check k3s logs
multipass exec k3s-master -- sudo journalctl -u k3s -f

# SSH to debug
multipass exec k3s-master -- bash
```
