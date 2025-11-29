# Talos Cluster Testing DevContainer

A development container for testing Talos Linux clusters locally.

## Features

- **talosctl**: Talos Linux CLI tool for cluster management
- **kubectl**: Kubernetes command-line tool
- **Docker-in-Docker**: Run the Talos cluster containers within the devcontainer
- **Git & GitHub CLI**: Version control and GitHub integration

## Quick Start

1. Open this project in VS Code with the Dev Containers extension
2. Or use DevPod:
   ```bash
   cd /path/to/talos-cluster-testing
   devpod up . --ide cursor
   ```

## Starting the Talos Cluster

Once inside the devcontainer:

```bash
# Start the Talos cluster (control plane + worker)
docker compose up -d

# Check cluster status
docker compose ps

# Get the IP addresses
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' talos-workshop-talos-cp-1
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' talos-workshop-talos-worker-1

# Generate Talos configuration
# talosctl gen config talos-cluster https://<CONTROL_PLANE_IP>:6443

# Apply configuration (example)
# talosctl apply-config --insecure --nodes <CONTROL_PLANE_IP> --file controlplane.yaml

# Bootstrap etcd
# talosctl bootstrap --nodes <CONTROL_PLANE_IP>

# Get kubeconfig
# talosctl kubeconfig --nodes <CONTROL_PLANE_IP>
```

## Stopping the Cluster

```bash
# Stop the cluster
docker compose down

# Stop and remove volumes (reset)
docker compose down -v
```

## Tools Included

- **talosctl v1.7.4**: Talos Linux CLI
- **kubectl**: Kubernetes CLI (latest)
- **docker**: Container runtime
- **docker compose**: Multi-container orchestration

## Architecture

The compose.yaml defines:
- **talos-cp**: Talos control plane node
- **talos-worker**: Talos worker node

Both nodes run in privileged mode with necessary capabilities for Kubernetes.

## Workspace Path

This devcontainer uses `/work/talos-cluster` as the workspace folder to avoid conflicts with other projects.

## Container Name

The devcontainer is named `talos-devcontainer` for easy identification in OrbStack.

