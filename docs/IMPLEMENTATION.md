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

## Appendix: Line Counts

**Total project size:**
```
ansible/playbooks/deploy-all.yml:     ~180 lines
ansible/playbooks/scale.yml:          ~589 lines
ansible/playbooks/destroy.yml:        ~88 lines
ansible/roles/common/tasks/main.yml:  ~67 lines
ansible/roles/master/tasks/main.yml:  ~30 lines
ansible/roles/worker/tasks/main.yml:  ~20 lines
----------------------------------------
Total:                                ~974 lines
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

**Last updated:** October 26, 2025
**Authors:** Bengolea, Braun, López Menardi
**Course:** Redes de Información (72.20) - ITBA
