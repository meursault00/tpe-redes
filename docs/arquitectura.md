# Architecture Diagram

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Local Computer                                │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Ansible Control Node                       │   │
│  │                                                               │   │
│  │  • Executes playbooks                                         │   │
│  │  • Manages inventory                                          │   │
│  │  • SSH to all nodes                                           │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                              │ SSH                                   │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Kubernetes Cluster (k3s)                         │   │
│  │              Network: 192.168.64.0/24                         │   │
│  │                                                               │   │
│  │  ┌────────────────────────────────────────────────────────┐  │   │
│  │  │  Control Plane (Master)                                │  │   │
│  │  │  k3s-master - 192.168.64.23                            │  │   │
│  │  │                                                         │  │   │
│  │  │  • API Server                                           │  │   │
│  │  │  • Scheduler                                            │  │   │
│  │  │  • Controller Manager                                   │  │   │
│  │  │  • etcd                                                 │  │   │
│  │  └────────────────────────────────────────────────────────┘  │   │
│  │                          │                                    │   │
│  │                          │ k3s cluster network               │   │
│  │                          │                                    │   │
│  │  ┌───────────────────────┴─────────────────────────────────┐ │   │
│  │  │                                                           │ │   │
│  │  ▼                                                           ▼ │   │
│  │  ┌──────────────────────────┐      ┌──────────────────────┐ │   │
│  │  │  Worker Node 1           │      │  Worker Node 2        │ │   │
│  │  │  k3s-worker-1            │ ...  │  k3s-worker-N         │ │   │
│  │  │  192.168.64.24           │      │  192.168.64.25+       │ │   │
│  │  │                          │      │                       │ │   │
│  │  │  ┌─────────┐  ┌────────┐│      │  ┌─────────┐          │ │   │
│  │  │  │  Pod 1  │  │ Pod 2  ││      │  │  Pod N  │          │ │   │
│  │  │  │         │  │        ││      │  │         │          │ │   │
│  │  │  │┌───────┐│  │┌──────┐││      │  │┌───────┐│          │ │   │
│  │  │  ││  App  ││  ││ App  │││      │  ││  App  ││          │ │   │
│  │  │  │└───────┘│  │└──────┘││      │  │└───────┘│          │ │   │
│  │  │  └─────────┘  └────────┘│      │  └─────────┘          │ │   │
│  │  │                          │      │                       │ │   │
│  │  │  kubelet                 │      │  kubelet              │ │   │
│  │  │  kube-proxy              │      │  kube-proxy           │ │   │
│  │  │  containerd              │      │  containerd           │ │   │
│  │  └──────────────────────────┘      └──────────────────────┘ │   │
│  │                                                               │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

## Network Architecture

```
┌────────────────────────────────────────────────────┐
│            Host Network: 192.168.64.0/24           │
├────────────────────────────────────────────────────┤
│                                                    │
│  k3s-master:    192.168.64.23                      │
│  k3s-worker-1:  192.168.64.24                      │
│  k3s-worker-2:  192.168.64.25                      │
│  k3s-worker-N:  192.168.64.26+                     │
│                                                    │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│         Pod Network (Flannel): 10.42.0.0/16        │
├────────────────────────────────────────────────────┤
│                                                    │
│  Dynamic pod IP allocation                         │
│  Cross-node pod communication                      │
│                                                    │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│         Service Network: 10.43.0.0/16              │
├────────────────────────────────────────────────────┤
│                                                    │
│  ClusterIP services                                │
│  Internal service discovery                        │
│                                                    │
└────────────────────────────────────────────────────┘
```

## Ansible Workflow

```
1. Provision Phase (common role)
   └─> Install dependencies on all nodes
   └─> Configure networking
   └─> Disable swap
   └─> Load kernel modules

2. Master Setup (master role)
   └─> Install k3s server
   └─> Generate join token
   └─> Wait for cluster to be ready

3. Worker Join (worker role)
   └─> Get token from master
   └─> Install k3s agent
   └─> Join cluster
   └─> Verify connection

4. Verification (status playbook)
   └─> Check node status
   └─> List pods
   └─> Display cluster info
```

## Component Responsibilities

### Control Plane (Master)
- **API Server**: Entry point for all cluster operations
- **Scheduler**: Assigns pods to worker nodes
- **Controller Manager**: Maintains desired state
- **etcd**: Stores cluster state and configuration

### Worker Nodes
- **kubelet**: Manages pod lifecycle on the node
- **kube-proxy**: Handles network routing
- **containerd**: Container runtime
- **Pods**: Run application containers

### Ansible
- **Playbooks**: Define automation workflows
- **Roles**: Encapsulate configuration logic
- **Inventory**: Define cluster topology
- **Variables**: Customize deployment

## Scaling

Adding workers is dynamic:
```bash
scripts/test_cluster.sh scale 3  # Add 3 workers
ansible-playbook playbooks/scale.yml  # Configure them
```

## Security

- SSH key-based authentication
- No password authentication
- Token-based node joining
- Network policies (optional)

## Storage

- Local path provisioner (default in k3s)
- Can integrate external storage later
- Persistent volumes for stateful apps
