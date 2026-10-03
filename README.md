# Talos Container Lab

A small Docker Compose lab for experimenting with the container platform in
[Talos Linux](https://www.talos.dev/) without dedicating physical machines. The
topology starts one control-plane container and one worker container with
separate persistent state volumes.

This repository is useful for learning how Talos containers are isolated and
for testing host compatibility. It is a lab scaffold, not a complete
Kubernetes cluster: machine configuration, control-plane bootstrap, networking,
and workload deployment are intentionally left to the operator.

Security reporting: [SECURITY.md](SECURITY.md).

## Topology

```text
Docker host
├── talos-cp
│   └── cp-state volume
└── talos-worker
    └── worker-state volume
```

Both services run the pinned `ghcr.io/siderolabs/talos:v1.7.4` image. Their root
filesystems are read-only; writable runtime paths use temporary filesystems or
named volumes. Talos needs privileged container access and an unconfined seccomp
profile in this experiment.

## Requirements

- Docker Engine with Compose v2
- A Linux host or Linux virtual machine that permits privileged containers
- Enough local resources for two Talos containers

Docker Desktop and other virtualized runtimes may impose additional limits on
privileged containers. Validate the Compose file on macOS or Windows, but use a
Linux VM when the containers cannot reach the required kernel features.

## Validate the configuration

Render the fully resolved Compose model before starting anything:

```bash
docker compose config
```

The command checks the YAML, service references, volume declarations, and
interpolation without creating containers.

## Start the lab

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100
```

At this point, Compose has started the two Talos containers. It has not created
a usable Kubernetes control plane. Continue with your own Talos machine
configuration and bootstrap procedure if the experiment requires a cluster.

Stop the containers while preserving their named state volumes:

```bash
docker compose down
```

Remove the volumes only when you intentionally want to reset the lab:

```bash
docker compose down --volumes
```

## Repository layout

| Path | Purpose |
| --- | --- |
| [`compose.yaml`](compose.yaml) | Two-node Talos container topology and storage mounts |
| [`SECURITY.md`](SECURITY.md) | Vulnerability reporting and supported branch |
| [`LICENSE`](LICENSE) | License retained from the original lab scaffold |

## Safety notes

- The services are privileged. Run the lab only on a machine or disposable VM
  you control.
- Named volumes retain node state between runs. Treat `down --volumes` as a
  destructive reset.
- The Compose file does not manage secrets, expose a Kubernetes API port, or
  configure production networking.

## License

This repository is available under the [MIT License](LICENSE).
