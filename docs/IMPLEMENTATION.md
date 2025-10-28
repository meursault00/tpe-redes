# Implementation Details and Design Justifications

This document explains the technical decisions made during the implementation of the k3s cluster management system, including justifications for code complexity, architectural choices, and trade-offs.

## Table of Contents

- [Overview](#overview)
- [Common Role Integration](#common-role-integration)
- [Scale.yml Complexity](#scaleyml-complexity)
- [Dynamic Inventory Management](#dynamic-inventory-management)
- [Destroy.yml Auto-Discovery](#destroyyml-auto-discovery)
- [Code Quality vs. Simplicity](#code-quality-vs-simplicity)
- [What Could Be Simplified](#what-could-be-simplified)

---

## Overview

When implementing this project, we faced a fundamental tension:

**Academic Simplicity** vs. **Production Quality**

- Academic projects typically favor minimal, easy-to-understand code
- Production systems require robustness, error handling, and maintainability

We chose to lean toward **production quality** for the following reasons:

1. The assignment asks for a system that "works" - not just a proof of concept
2. Kubernetes/k3s has strict requirements that must be met for functionality
3. Dynamic scaling is inherently complex and requires proper state management
4. Better to demonstrate professional-grade Ansible skills

However, we acknowledge that some features add complexity without significant benefit for an academic project. This document explains what's essential vs. what's "nice-to-have".

---

## Common Role Integration

### What It Does

The `common` role configures all nodes (master and workers) with:

1. **IPv4 forwarding** (`net.ipv4.ip_forward=1`)
2. **Kernel modules** (`br_netfilter`, `overlay`)
3. **Swap disable** (removes swap from /etc/fstab)
4. **Package installation** (curl, wget, vim, git, htop, net-tools, etc.)

### Why It Exists

**Critical functionality (REQUIRED for k3s to work):**

#### 1. IPv4 Forwarding

```yaml
- name: Enable IPv4 forwarding
  ansible.posix.sysctl:
    name: net.ipv4.ip_forward
    value: '1'
    sysctl_set: yes
    state: present
    reload: yes
```

**Justification:**
- **Essential for multi-node networking**: Without this, packets cannot be forwarded between pods on different nodes
- **How it works**: When a pod on worker-1 (10.42.2.5) wants to communicate with a pod on worker-2 (10.42.1.8), the packet must be forwarded through the host network
- **What happens without it**: Pods can only communicate within the same node; cross-node communication fails
- **Real-world evidence**: During testing, we observed connection timeouts between pods on different workers when this wasn't enabled

**Example failure scenario:**
```bash
# Without IPv4 forwarding:
$ kubectl exec -it pod-on-worker-1 -- ping pod-on-worker-2
PING 10.42.1.8: Timeout

# With IPv4 forwarding:
$ kubectl exec -it pod-on-worker-1 -- ping pod-on-worker-2
64 bytes from 10.42.1.8: seq=1 ttl=64 time=0.5 ms
```

#### 2. Kernel Modules

```yaml
- name: Load required kernel modules
  community.general.modprobe:
    name: "{{ item }}"
    state: present
  loop:
    - br_netfilter
    - overlay
```

**Justification:**
- **br_netfilter**: Required for iptables to see bridged traffic (k3s uses iptables for service routing)
- **overlay**: Required for overlay network filesystem used by containerd
- **Why they're separate from k3s**: These must be loaded at the kernel level before container runtime starts
- **What happens without them**: k3s installation may succeed, but networking and storage will fail

#### 3. Swap Disable

```yaml
- name: Disable swap (required for Kubernetes)
  ansible.builtin.command: swapoff -a
  when: ansible_swaptotal_mb > 0

- name: Remove swap from /etc/fstab
  ansible.builtin.lineinfile:
    path: /etc/fstab
    regexp: '\sswap\s'
    state: absent
```

**Justification:**
- **Kubernetes requirement**: k8s/k3s requires swap to be disabled for proper memory management
- **Why**: Kubernetes assumes it has predictable memory behavior; swap breaks this assumption
- **Note**: Multipass VMs have no swap by default, so this is defensive programming

**Less critical but useful (CONVENIENCE):**

#### 4. Package Installation

```yaml
- name: Install required packages
  ansible.builtin.apt:
    name:
      - curl          # Required by k3s installer script
      - wget          # Useful for debugging
      - vim           # Text editor
      - git           # Version control
      - htop          # Process monitoring
      - net-tools     # Network debugging (ifconfig, netstat)
    state: present
```

**Justification:**
- **curl**: Actually required by k3s installer (must have)
- **Others**: Debugging and convenience tools (nice-to-have)

**Could be removed:** vim, git, htop, net-tools, wget (leaves only curl)

### Integration into deploy-all.yml

We added a dedicated play in deploy-all.yml:

```yaml
- name: Prepare all nodes with common configuration
  hosts: all
  become: true
  gather_facts: true
  roles:
    - common
```

**Why separate play:**
- Must run BEFORE k3s installation
- Applies to both master and workers
- Allows gathering facts about the system first
- Makes it easy to see in Ansible output: "Preparing common configuration..." then "Installing k3s master..." etc.

**Why not inline in master/worker roles:**
- Violates DRY (Don't Repeat Yourself) - would duplicate code
- Common setup should be... common
- Easier to maintain in one place
- Better Ansible practice (separation of concerns)

### Conclusion

**Essential parts:** IPv4 forwarding, kernel modules (~20 lines)
**Nice-to-have:** Package installation beyond curl (~30 lines)
**Verdict:** Keep the essential parts, optionally simplify package list

---

## Scale.yml Complexity

### The Problem

The scale.yml playbook is **589 lines** - quite large for an academic project.

### Why It's Complex

Dynamic cluster scaling requires:

1. **State management**: Track which workers exist, which are new, which to remove
2. **Inventory manipulation**: YAML parsing, merging, writing back
3. **IP address detection**: Retry logic for VM startup timing
4. **Selective role application**: Only configure new workers, skip existing ones
5. **Graceful shutdown**: Drain pods, remove from k3s, then delete VM
6. **Error handling**: Validation, verification, meaningful error messages
7. **User feedback**: Status displays so user knows what's happening

### Line-by-Line Breakdown

| Component | Lines | Justification | Essential? |
|-----------|-------|---------------|------------|
| **PLAY 1: Validation** | 65 | Input checking, display scaling plan | ✅ Yes - prevents invalid operations |
| **PLAY 2: Create VMs** | 65 | VM creation with IP retry logic | ✅ Yes - core functionality |
| **PLAY 3: Update Inventory** | 85 | YAML parsing and inventory updates | ✅ Yes - critical for automation |
| **PLAY 4: Common Role** | 50 | Apply networking setup to new workers | ✅ Yes - required for k3s |
| **PLAY 5: Join Workers** | 45 | Join new workers to k3s cluster | ✅ Yes - core functionality |
| **PLAY 6: Verification** | 70 | Verify nodes joined successfully | ⚠️ Maybe - good practice but could simplify |
| **PLAY 7: Drain Nodes** | 75 | Gracefully drain pods before removal | ✅ Yes - prevents data loss |
| **PLAY 8: Delete VMs** | 45 | Stop and delete worker VMs | ✅ Yes - core functionality |
| **PLAY 9: Update Inventory** | 80 | Remove workers from inventory | ✅ Yes - maintains consistency |
| **PLAY 10: Final Verification** | 65 | Display final cluster state | ⚠️ Maybe - nice UX but not essential |
| **Status boxes/formatting** | ~44 | Unicode boxes, pretty output | ❌ No - aesthetic only |

**Total essential: ~440 lines**
**Total nice-to-have: ~150 lines**

### Key Features That Add Complexity But Provide Value

#### 1. Auto-Detection of Next Worker Number

```yaml
- name: Calculate next worker number
  ansible.builtin.set_fact:
    last_worker_num: >-
      {{
        (existing_workers.stdout_lines |
         map('regex_replace', '^k3s-worker-', '') |
         map('int') |
         max | default(0))
      }}
```

**Why:** Handles gaps in worker numbering (e.g., if worker-3 is deleted, creates worker-4, not worker-3)

**Could simplify:** Always use sequential numbering, track in a separate state file

#### 2. IP Address Retry Logic

```yaml
# Wait for VM to be fully running
while [ "$(multipass info "${WORKER_NAME}" --format csv | tail -n1 | cut -d',' -f2)" != "Running" ]; do
  echo "Waiting for ${WORKER_NAME} to reach Running state..."
  sleep 5
done

# Get the VM's IP address (retry up to 6 times)
for i in {1..6}; do
  IP=$(multipass info "${WORKER_NAME}" --format csv | tail -n1 | cut -d',' -f3)
  if [ -n "$IP" ] && [ "$IP" != "--" ]; then
    echo "${WORKER_NAME}:${IP}"
    exit 0
  fi
  sleep 5
done
```

**Why:** VMs don't get IPs instantly; without retry, playbook fails intermittently

**Value:** Makes playbook reliable instead of requiring manual reruns

#### 3. Selective Role Application

```yaml
- name: Check if node is newly added
  ansible.builtin.set_fact:
    is_new_node: "{{ inventory_hostname in hostvars['localhost']['new_workers'] | map(attribute='0') | list }}"

- name: Include common role for new nodes
  ansible.builtin.include_role:
    name: common
  when:
    - action == "add"
    - is_new_node | default(false)
```

**Why:** Don't reconfigure existing workers (faster, avoids unnecessary changes)

**Value:** Playbook is faster and safer

#### 4. Proper Pod Drainage

```yaml
- name: Drain pods from workers
  ansible.builtin.shell: |
    multipass exec k3s-master -- sudo kubectl drain "${WORKER}" \
      --ignore-daemonsets \
      --delete-emptydir-data \
      --force \
      --grace-period=30 \
      --timeout=120s
```

**Why:** Move pods to other workers before deleting node (prevents service disruption)

**Value:** Production-ready behavior; avoids killing running pods

### What Could Be Simplified

**Option A: Minimal version (~200 lines)**
- Remove all status boxes/pretty output (~44 lines)
- Remove verbose verification plays (~135 lines)
- Simple error messages instead of detailed debugging
- Remove input validation (trust user input)

**Option B: Medium version (~400 lines)**
- Keep all functionality
- Remove aesthetic formatting
- Simplify verification (quick checks only)

**Option C: Keep as-is (~589 lines)**
- Production-ready
- Excellent user feedback
- Comprehensive error handling

### Recommendation

For an academic project: **Option B** (400 lines)
- Demonstrates Ansible skills
- Actually works reliably
- Not overly verbose

---

## Dynamic Inventory Management

### What It Does

Instead of manually editing inventory files, the system:

1. Auto-detects VM IP addresses during provisioning
2. Updates `inventory.yml` automatically
3. Refreshes Ansible's in-memory inventory
4. Maintains inventory during scale operations

### Why Dynamic Instead of Static

**Problems with static inventory:**
```ini
# ansible/inventory/local.ini (static)
[master]
k3s-master ansible_host=192.168.64.10

[workers]
k3s-worker-1 ansible_host=192.168.64.11
k3s-worker-2 ansible_host=192.168.64.12
```

Issues:
- IPs change when VMs are recreated (Multipass assigns dynamically)
- Adding/removing workers requires manual editing
- Error-prone (typos, wrong IPs)
- Doesn't scale (imagine 10 workers)

**Solution: Dynamic inventory**

```yaml
# Automatically updated by playbooks
all:
  children:
    master:
      hosts:
        k3s-master:
          ansible_host: 192.168.64.37  # Auto-detected
    workers:
      hosts:
        k3s-worker-1:
          ansible_host: 192.168.64.38  # Auto-detected
        k3s-worker-2:
          ansible_host: 192.168.64.39  # Auto-detected
```

### Implementation

#### During Provisioning (provision.yml)

```yaml
- name: Get IP addresses for all VMs
  ansible.builtin.shell: |
    multipass info {{ item.name }} --format csv | tail -n1 | cut -d',' -f3
  loop: "{{ nodes }}"
  register: vm_ips

- name: Generate inventory file
  ansible.builtin.template:
    src: inventory.yml.j2
    dest: "{{ playbook_dir }}/../inventory.yml"
```

#### During Scaling (scale.yml)

```yaml
# Scale UP: Add new workers
- name: Build new workers dictionary
  ansible.builtin.set_fact:
    new_workers_dict: >-
      {{
        new_workers_dict | default({}) | combine({
          item[0]: {
            'ansible_host': item[1]
          }
        })
      }}
  loop: "{{ new_workers }}"

- name: Merge new workers into inventory
  ansible.builtin.set_fact:
    updated_inventory: >-
      {{
        inventory_data | combine({
          'all': {
            'vars': inventory_data.all.vars,
            'children': {
              'master': inventory_data.all.children.master,
              'workers': {
                'hosts': inventory_data.all.children.workers.hosts | combine(new_workers_dict)
              }
            }
          }
        }, recursive=True)
      }}

- name: Write updated inventory
  ansible.builtin.copy:
    content: "{{ updated_inventory | to_nice_yaml(indent=2) }}"
    dest: "{{ inventory_path }}"
    backup: yes
```

**Complexity:** ~60 lines for inventory updates (add + remove)

**Value:**
- Zero manual intervention
- Always accurate
- Supports any number of workers
- No typos possible

**Could simplify:** Use a simpler inventory format (INI instead of YAML)
- Trade-off: Less structure, harder to parse programmatically

### Inventory Refresh

After updating inventory file, we must refresh Ansible's in-memory cache:

```yaml
- name: Refresh Ansible inventory
  ansible.builtin.meta: refresh_inventory

- name: Wait for inventory refresh
  ansible.builtin.pause:
    seconds: 5
```

**Why the pause:** Ansible needs a moment to reload; without it, subsequent plays use stale data

**Worth it?** Absolutely - without this, scale operations would fail

---

## Destroy.yml Auto-Discovery

### Original Implementation (Hardcoded)

```yaml
vars:
  nodes:
    - k3s-master
    - k3s-worker-1
    - k3s-worker-2

tasks:
  - name: Delete instances
    command: multipass delete --purge {{ item }}
    loop: "{{ nodes }}"
```

**Problem:** Only destroys the original 3 VMs. If you scaled to 5 workers, 3 VMs are orphaned.

### New Implementation (Auto-Discovery)

```yaml
- name: Get list of all k3s VMs
  ansible.builtin.shell: |
    multipass list --format csv | grep '^k3s-' | cut -d',' -f1
  register: k3s_vms

- name: Stop all k3s VMs
  ansible.builtin.shell: |
    multipass stop {{ item }}
  loop: "{{ k3s_vms.stdout_lines }}"

- name: Delete all k3s VMs
  ansible.builtin.shell: |
    multipass delete {{ item }}
  loop: "{{ k3s_vms.stdout_lines }}"

- name: Purge deleted VMs
  ansible.builtin.shell: |
    multipass purge
```

**Benefit:**
- Discovers ANY VM starting with "k3s-"
- Handles scaled clusters
- No orphaned VMs
- Works regardless of inventory state

**Added complexity:** ~30 lines vs. 10 lines original

**Worth it?** Yes - prevents the confusing situation where destroy "works" but VMs remain

---

## Code Quality vs. Simplicity

### Professional Practices We Implemented

1. **Error handling**
   - Input validation
   - Graceful failures
   - Meaningful error messages

2. **Idempotency**
   - Safe to run multiple times
   - Checks current state before changing
   - `when` conditionals throughout

3. **User feedback**
   - Status displays
   - Progress indicators
   - Verification messages

4. **Documentation**
   - Inline comments
   - Header comments in each playbook
   - This IMPLEMENTATION.md file

5. **Version control hygiene**
   - .gitignore for secrets
   - No credentials in code
   - Backup before destructive operations

### Trade-offs

| Feature | Lines Added | Benefit | Academic Value |
|---------|-------------|---------|----------------|
| Input validation | ~40 | Prevents errors | Medium |
| Status boxes | ~44 | Nice UX | Low |
| IP retry logic | ~25 | Reliability | High |
| Verification plays | ~135 | Confirm success | Medium |
| Inventory backups | ~10 | Safety | Medium |
| Comprehensive comments | ~80 | Clarity | High |

### Our Philosophy

We chose **reliability over brevity** because:

1. A working system is better than a simple broken one
2. Demonstrates professional Ansible skills
3. Easier to debug when something goes wrong
4. Shows understanding of production requirements

However, we acknowledge that for an academic evaluation, **simpler might be better** if it still demonstrates core concepts.

---

## What Could Be Simplified

If we were to optimize for "minimum viable academic project", here's what could be removed:

### High Priority Removals (Little Impact on Functionality)

1. **Unicode status boxes** (~44 lines)
   ```yaml
   # Instead of:
   msg: |
     ╔════════════════════════════════════════════════════════╗
     ║            K3S CLUSTER SCALING OPERATION               ║
     ╚════════════════════════════════════════════════════════╝

   # Use simple:
   msg: "Scaling cluster: {{ action }} {{ node_count }} workers"
   ```

2. **Verbose package installation in common role** (~15 lines)
   ```yaml
   # Only install essentials:
   - name: Install required packages
     ansible.builtin.apt:
       name:
         - curl  # Required for k3s installer
       state: present
   ```

3. **Detailed verification plays** (~70 lines)
   ```yaml
   # Replace comprehensive verification with simple check:
   - name: Verify cluster
     shell: kubectl get nodes
   ```

### Medium Priority Removals (Some Impact on UX)

4. **Comprehensive debug messages** (~40 lines)
   - Keep essential messages only

5. **Extended wait times and retries** (~20 lines)
   - Use fixed short waits instead of adaptive logic

### Low Priority Removals (Impacts Reliability)

6. **Input validation** (~40 lines)
   - Trust user inputs (risky but simpler)

7. **Inventory backups** (~10 lines)
   - Don't backup before modifications

**Total potential savings: ~240 lines** (from 589 to ~350)

### Minimal Version

A truly minimal scale.yml (~200 lines) would:
- Remove ALL status formatting
- Remove verification plays
- Remove retry logic (assume success)
- Remove input validation
- Simple error messages only

**Trade-off:** Less robust, harder to debug, poorer UX, but demonstrates core concept

---

## Conclusion

### What We Built

A **production-grade k3s cluster management system** with:
- Automated provisioning
- Dynamic scaling
- Intelligent inventory management
- Proper error handling
- Comprehensive verification

### Why This Way

We prioritized **functionality and reliability** over **minimal code** because:

1. k3s has real requirements (networking, kernel modules) that must be met
2. Dynamic scaling is inherently complex (state management, inventory updates)
3. Better to demonstrate professional Ansible skills
4. A working system is more valuable than a simple broken one

### Could It Be Simpler?

**Yes.** We could reduce ~240 lines (~40%) by:
- Removing aesthetic formatting
- Simplifying verification
- Reducing error handling
- Trusting user inputs

**Should it be?**

For academic evaluation, **maybe**. Professors often prefer:
- Clarity over completeness
- Understanding over optimization
- Simplicity over robustness

For professional use, **no**. The current implementation is maintainable, reliable, and production-ready.

### Our Recommendation

Keep the current implementation because:
1. It works reliably
2. Demonstrates advanced Ansible skills
3. Well-documented (this file explains everything)
4. Can be easily defended in presentation

If professors want simpler, we can create a minimal branch with explanations of what was removed and why.

---

## Application Deployment System

### Overview

We implemented a complete deployment automation system for **The Store**, a microservices e-commerce application, to demonstrate real-world cluster usage beyond just infrastructure management.

### Why Deploy an Application?

**Academic value:**
- Shows complete infrastructure-to-application workflow
- Demonstrates Ansible handling complex multi-step processes
- Proves the k3s cluster actually works with real workloads
- Great for presentation/demo

**What we automate:**
1. Building Docker images from source
2. Distributing images to multiple nodes
3. Deploying Kubernetes manifests
4. Verification and access

### The Application: The Store

**What it is:**
- Modern microservices e-commerce platform
- 5 services: catalog (Go), cart (Java), checkout (Node.js), orders (Java), ui (Java)
- Pre-built Kubernetes manifests (671 lines)
- Real-world complexity (secrets, configmaps, deployments, services, ingress)

**Why this app:**
- Available in course materials
- Representative of production microservices
- Has all common Kubernetes resources
- Actually functional (can browse products, add to cart)

### Challenge 1: Docker Images

**Problem:**
- The Store builds images locally for Kind (local Kubernetes)
- k3s runs on remote Multipass VMs
- Can't use Docker registry (keeps project self-contained)
- Each worker needs the images

**Solutions considered:**

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Push to Docker Hub** | Standard practice | Requires account, public images, internet dependency | ❌ Rejected - external dependency |
| **Local registry in cluster** | Clean, professional | Complex setup, extra component | ❌ Rejected - too complex |
| **Build on each worker** | Simple conceptually | Slow, requires build tools on workers | ❌ Rejected - wastes resources |
| **Transfer tar files** | Self-contained, fast | Manual process, requires scripting | ✅ **Chosen** - best for demo |

**Our implementation:**
```yaml
# 1. Build images on localhost (has Docker)
docker build -t the-store-catalog:latest src/catalog/

# 2. Save to tar
docker save -o the-store-catalog.tar the-store-catalog:latest

# 3. Transfer to worker
multipass transfer the-store-catalog.tar k3s-worker-1:/tmp/

# 4. Import into containerd (k3s uses containerd, not Docker)
multipass exec k3s-worker-1 -- sudo ctr -n k8s.io images import /tmp/the-store-catalog.tar
```

**Why this works:**
- k3s uses containerd as container runtime
- `ctr` is containerd's CLI tool
- Namespace `k8s.io` is where k3s stores images
- Once imported, pods can use `imagePullPolicy: IfNotPresent`

**Trade-offs:**
- ✅ Fully automated via Ansible
- ✅ No external dependencies
- ✅ Fast (parallel transfer to all workers)
- ✅ Works offline
- ❌ Images tied to specific nodes (not a problem for demo)
- ❌ Need to rebuild/retransfer for updates (acceptable)

### Challenge 2: Ingress Controller

**Problem:**
- The Store manifests specify `kubernetes.io/ingress.class: nginx`
- k3s comes with Traefik ingress controller (not nginx)
- Installing nginx would be redundant and wasteful

**Solutions considered:**

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| **Install nginx ingress** | Manifests work as-is | Extra component, resource usage | ❌ Rejected - unnecessary |
| **Remove Ingress, use NodePort** | Simple | No path-based routing, non-standard | ❌ Rejected - less realistic |
| **Adapt to Traefik** | Uses built-in component | Need to modify manifests | ✅ **Chosen** - clean solution |

**Our implementation:**
```yaml
# One line change in kubernetes.yaml
annotations:
  kubernetes.io/ingress.class: traefik  # was: nginx
```

**Why Traefik:**
- Already installed in k3s (zero setup)
- Lightweight and fast
- Automatically watches Ingress resources
- Supports same Ingress spec as nginx (just different annotation)

**How it works:**
1. Ingress resource specifies `ingressClassName: traefik`
2. Traefik controller sees the resource
3. Automatically configures routes
4. Traffic to master-ip goes to ui service

### Challenge 3: Deployment Automation

**Problem:**
- Multi-step process (build, transfer, import, deploy)
- Need to handle 5 different images
- Multiple worker nodes to update
- Error handling and verification

**Our solution: Two playbooks**

#### build-store-images.yml (~90 lines)

**Purpose:** Build and package images
```yaml
Tasks:
1. Verify Docker is running
2. Check The Store source exists
3. Build each service image
4. Save each image to tar
5. Display summary with file sizes
```

**Why separate:**
- Can rebuild without redeploying
- Faster iteration during development
- Clear separation of concerns
- Reusable for CI/CD

#### deploy-app.yml (~230 lines)

**Purpose:** Complete deployment workflow
```yaml
Play 1: Pre-flight checks
- Ensure k3s cluster exists
- Deploy cluster if needed

Play 2: Build images (if needed)
- Check if tars exist
- Build if missing

Play 3: Distribute images
- Transfer tars to all workers
- Import into containerd
- Verify import succeeded

Play 4: Deploy manifests
- Transfer manifests to master
- Create namespace
- Apply resources
- Wait for pods Ready

Play 5: Verification
- Get pod status
- Get services
- Display access URL
- Show verification commands
```

**Key features:**
- Idempotent (safe to re-run)
- Checks before acting
- Parallel operations where possible
- Clear progress messages
- Comprehensive verification

### Implementation Details

#### Image Distribution (The Tricky Part)

**Challenge:** Get images from localhost to worker nodes' containerd

**Step-by-step:**
```bash
# On localhost (has Docker):
docker build -t the-store-catalog:latest .
docker save -o catalog.tar the-store-catalog:latest

# Transfer to worker:
multipass transfer catalog.tar k3s-worker-1:/tmp/

# On worker (has containerd):
ctr -n k8s.io images import /tmp/catalog.tar

# Verify:
ctr -n k8s.io images list | grep the-store
```

**Why `-n k8s.io`:**
- containerd uses namespaces to isolate images
- k3s stores its images in `k8s.io` namespace
- Default namespace won't work

**Ansible automation:**
```yaml
- name: Import images into containerd
  ansible.builtin.shell: |
    multipass exec {{ item[0] }} -- sudo ctr -n k8s.io images import /tmp/the-store-{{ item[1] }}.tar
  loop: "{{ workers | product(services) | list }}"
```

This creates a cartesian product: (worker-1, catalog), (worker-1, cart), ..., (worker-2, catalog), etc.

#### Manifest Adaptation

**Original Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx  # ❌ nginx not installed
spec:
  rules:
    - host: "localhost"
      http:
        paths:
          - path: /
            backend:
              service:
                name: ui
```

**Modified for Traefik:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: traefik  # ✅ uses k3s built-in
spec:
  rules:
    - host: "localhost"  # Access via master IP
      http:
        paths:
          - path: /
            backend:
              service:
                name: ui
```

**Access:**
- Get master IP: `multipass info k3s-master | grep IPv4`
- Browse to: `http://<master-ip>`
- Traefik routes traffic to ui service on port 80

### Why This Approach Works

**For academic project:**
1. ✅ Fully automated (impressive demo)
2. ✅ Self-contained (no external dependencies)
3. ✅ Demonstrates Ansible capabilities
4. ✅ Shows understanding of k3s/containerd
5. ✅ Real application, not just toy example

**Technical merit:**
1. ✅ Proper container image management
2. ✅ Correct use of containerd CLI
3. ✅ Kubernetes best practices (namespaces, labels)
4. ✅ Ingress routing configuration
5. ✅ Multi-node coordination

**Presentation value:**
1. ✅ Visual demo (can show web UI)
2. ✅ End-to-end workflow
3. ✅ Handles complexity gracefully
4. ✅ Professional quality

### Alternative Approaches (Not Chosen)

#### 1. Simplified Demo App

**What:** Deploy nginx or redis instead
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: nginx
        image: nginx:latest  # Public image, no build needed
```

**Why not:**
- ✅ Much simpler
- ❌ Doesn't demonstrate real complexity
- ❌ Public image (less impressive)
- ❌ No microservices architecture

#### 2. Registry-Based Deployment

**What:** Push images to Docker Hub, pull from there
```yaml
# Push to registry:
docker tag the-store-catalog:latest user/the-store-catalog:latest
docker push user/the-store-catalog:latest

# In deployment:
containers:
- name: catalog
  image: user/the-store-catalog:latest
  imagePullPolicy: Always
```

**Why not:**
- ✅ Standard practice
- ✅ Simpler workflow
- ❌ Requires Docker Hub account
- ❌ External dependency
- ❌ Images become public
- ❌ Less self-contained

#### 3. Build on Workers

**What:** Copy source to workers, build there
```bash
multipass exec k3s-worker-1 -- docker build -t the-store-catalog:latest /source/catalog
```

**Why not:**
- ✅ Images automatically available
- ❌ Workers need Docker + build tools
- ❌ Slow (build on each worker separately)
- ❌ Wastes resources
- ❌ k3s uses containerd, not Docker

### Complexity Justification

**Total lines added:**
- build-store-images.yml: 90 lines
- deploy-app.yml: 230 lines
- Manifest modifications: 1 line
- **Total: ~320 lines**

**Is it worth it?**

**Yes, because:**
1. Demonstrates complete platform (not just infrastructure)
2. Solves real problems (image distribution to containerd)
3. Professional quality (error handling, verification)
4. Reusable for any containerized app
5. Great for presentation

**Could be simpler:**
- Manual steps in documentation (~50 lines)
- Simple nginx deployment (~10 lines)
- Trade-off: Less impressive, less learning

### Lessons Learned

1. **containerd vs Docker:** k3s uses containerd; need `ctr` not `docker`
2. **Image distribution:** Tar files work well for local clusters
3. **Ingress flexibility:** Easy to swap nginx/traefik with annotation change
4. **Ansible loops:** `product` filter creates cartesian products elegantly
5. **Verification matters:** Wait loops prevent race conditions

---

## Appendix: Line Counts

**Total project size:**
```
# Infrastructure Management
ansible/playbooks/deploy-all.yml:        ~180 lines
ansible/playbooks/scale.yml:             ~589 lines
ansible/playbooks/destroy.yml:           ~88 lines
ansible/roles/common/tasks/main.yml:     ~67 lines
ansible/roles/master/tasks/main.yml:     ~30 lines
ansible/roles/worker/tasks/main.yml:     ~20 lines

# Application Deployment (NEW)
ansible/playbooks/build-store-images.yml: ~90 lines
ansible/playbooks/deploy-app.yml:        ~230 lines
ansible/manifests/the-store/*.yaml:      ~671 lines (adapted)
------------------------------------------------------
Total:                                   ~1,965 lines
```

**Essential core (minimal version):**
```
deploy-all.yml:   ~140 lines (remove verification)
scale.yml:        ~350 lines (remove formatting/verbose checks)
destroy.yml:      ~60 lines (keep auto-discovery)
common role:      ~20 lines (only critical networking)
master role:      ~30 lines (no change)
worker role:      ~20 lines (no change)
----------------------------------------
Total:            ~620 lines (-35%)
```

---

## Network Connectivity Issues and Resolution

### The Problem: "No Route to Host" SSH Failures

During development of the application deployment system, we encountered a critical issue where Ansible would consistently fail to connect to VMs with "No route to host" errors, despite:

- VMs showing as "Running" in multipass
- IP addresses being correctly assigned
- Cloud-init completing successfully
- Manual SSH with proper keys available

#### Investigation Timeline

**Initial Hypothesis (INCORRECT):**
1. SSH not ready yet → Added 60s wait
2. Ansible config not loaded → Added ANSIBLE_CONFIG environment variable
3. wait_for_connection timing → Increased to 180s timeout
4. **Result:** Still failed after 185+ seconds

**Actual Root Cause Discovery:**

After systematic investigation, we discovered:

```bash
# Even multipass exec failed!
$ multipass exec k3s-master -- echo "test"
exec failed: ssh connection failed: 'Failed to connect: No route to host'

# Direct ping also failed
$ ping -c 2 192.168.64.49
Request timeout for icmp_seq 0

# But VMs were Running with correct IPs
$ multipass list
k3s-master    Running    192.168.64.49    Ubuntu 22.04 LTS
```

The issue was **NOT an SSH daemon problem** - the entire network layer was corrupted at the host bridge level.

#### Root Cause: k3s Flannel CNI Network Corruption

**What happens:**

1. k3s uses **Flannel CNI** for pod networking (creates 10.42.x.x overlay)
2. Flannel creates:
   - iptables rules for pod-to-pod routing
   - Virtual interfaces: `flannel.1`, `cni0`, multiple `veth*` devices
   - Overlay network tunneling via VXLAN

3. When VMs experience lifecycle events (stop/start, network disruptions, crashes):
   - Flannel state becomes inconsistent between nodes
   - iptables rules may block traffic incorrectly
   - The physical bridge interface loses proper routing
   - **This cascades to block ALL network access**, including SSH from host

**Evidence from k3s logs:**
```
time="2025-10-27T19:19:20" level=error msg="dial tcp 10.42.0.11:10250: connect: no route to host"
E1027 19:19:20 error resolving kube-system/metrics-server: no endpoints available
```

The pod network corruption prevented k3s from reaching its own pods, which then corrupted the host network routing.

#### Solution: Network Health Detection and Recovery

We implemented a **pre-flight network health check** in [deploy-app.yml](../ansible/playbooks/deploy-app.yml:26-89):

**Detection Phase:**
```yaml
- name: Validate network health if cluster exists
  ansible.builtin.shell: |
    for vm in k3s-master k3s-worker-1 k3s-worker-2; do
      if multipass list | grep -q "$vm.*Running"; then
        IP=$(multipass info $vm --format csv | tail -n1 | cut -d',' -f3)
        if ! ping -c 2 -W 3 $IP > /dev/null 2>&1; then
          echo "WARNING: $vm ($IP) is unreachable"
          exit 1
        fi
      fi
    done
```

**Recovery Phase:**
```yaml
- name: Recover from network corruption
  ansible.builtin.shell: |
    multipass stop k3s-master k3s-worker-1 k3s-worker-2
    sleep 10
    multipass start k3s-master k3s-worker-1 k3s-worker-2
    sleep 30
    # Verify recovery...
```

**Why this works:**

- VM stop/start causes Flannel to reinitialize cleanly
- iptables rules are recreated correctly
- Bridge networking reestablishes proper routes
- Takes ~40 seconds but guarantees working state

#### Key Learnings

1. **Container networking is complex**: CNI plugins like Flannel manage significant network state that can become corrupted

2. **"Running" != "Accessible"**: VM lifecycle state and network health are separate concerns

3. **Symptoms can mislead**: "SSH not ready" was actually "network completely broken"

4. **Fail-fast is better**: Detecting corruption early and recovering is more user-friendly than waiting 3+ minutes for timeout

5. **Academic context value**: This demonstrates understanding of:
   - Container networking fundamentals (CNI, overlay networks)
   - System debugging methodology (hypothesis testing, eliminating causes)
   - Robust automation design (detect failures, automatic recovery)

#### Improvements to deploy-all.yml

We also optimized the SSH readiness check in [deploy-all.yml](../ansible/playbooks/deploy-all.yml:8-43):

**Changes:**
- Reduced initial wait from 90s → 30s (unnecessary delay)
- Use `wait_for` module from localhost (proper ansible.cfg context)
- Clear labeling: "Waiting for SSH on {IP}"
- Explicit ping test before proceeding with configuration

**Result:** Clean deployments complete in ~60-90 seconds (down from 3+ minutes of failures)

#### Alternative Approaches Considered

**Option A: Always destroy/recreate**
```yaml
- name: Clean slate deployment
  command: multipass delete --purge k3s-master k3s-worker-1 k3s-worker-2
```
**Pros:** Guaranteed clean state
**Cons:** Destroys existing deployments, slower (~2 minutes for VM creation)

**Option B: k3s service restart**
```yaml
- name: Restart k3s service
  shell: multipass exec {{ item }} -- sudo systemctl restart k3s
```
**Pros:** Faster than VM restart (~10 seconds)
**Cons:** Doesn't fix corrupted host bridge networking

**Option C: Manual intervention**
- Detect issue and fail with instructions
**Pros:** Simplest code
**Cons:** Poor user experience, requires manual steps

**Our choice:** Automatic detection + recovery (Option from our implementation)
- Best balance of reliability and user experience
- Demonstrates production-ready automation thinking

---

**Last updated:** October 27, 2025
**Authors:** Bengolea, Braun, López Menardi
**Course:** Redes de Información (72.20) - ITBA
