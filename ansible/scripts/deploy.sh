#!/bin/bash

set -e

echo "🚀 Starting K3s cluster deployment..."
echo ""

# Step 0: Setup SSH key
echo "🔑 Step 0: Setting up SSH access..."
ansible-playbook playbooks/setup-ssh.yml
echo "✅ SSH setup complete"
echo ""

# Step 1: Provision VMs and update inventory
echo "📦 Step 1: Provisioning Multipass VMs..."
ansible-playbook playbooks/provision.yml
echo "✅ VMs provisioned and inventory updated"
echo ""

# Step 2: Wait for VMs to be ready
echo "⏳ Step 2: Waiting for VMs to initialize (30 seconds)..."
sleep 30
echo "✅ VMs should be ready"
echo ""

# Step 3: Setup control plane
echo "🎛️  Step 3: Setting up K3s control plane..."
ansible-playbook playbooks/control-plane.yml
echo "✅ Control plane setup complete"
echo ""

# Step 4: Join workers
echo "👷 Step 4: Joining worker nodes..."
ansible-playbook playbooks/join-workers.yml
echo "✅ Worker nodes joined"
echo ""

# Step 5: Verify cluster
echo "🔍 Step 5: Verifying cluster status..."
multipass exec k3s-master -- sudo kubectl get nodes
echo ""

echo "🎉 Deployment complete!"
echo ""
echo "Useful commands:"
echo "  • Check nodes:  multipass exec k3s-master -- sudo kubectl get nodes"
echo "  • Check pods:   multipass exec k3s-master -- sudo kubectl get pods -A"
echo "  • SSH to master: ssh -i ~/.ssh/multipass_id_rsa ubuntu@\$(grep -A1 k3s-master inventory.yml | grep ansible_host | awk '{print \$2}')"
echo ""