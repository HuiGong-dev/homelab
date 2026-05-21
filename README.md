# Homelab

Personal platform engineering homelab running on Proxmox and Kubernetes.

## Layers

| Layer          | Path               | Purpose                                |
| -------------- | ------------------ | -------------------------------------- |
| Infrastructure | `infra/opentofu`   | Provision VMs on Proxmox               |
| Configuration  | `infra/ansible`    | Bootstrap Linux hosts                  |
| Platform       | `cluster/platform` | Kubernetes platform components         |
| Applications   | `cluster/apps`     | User-facing workloads                  |
| Documentation  | `docs`             | Runbooks, IP table, architecture notes |

## Current services

| Service      | URL                               | Notes                                      |
| ------------ | --------------------------------- | ------------------------------------------ |
| Proxmox      | `https://pve.home.hgpe.dev`       | Off-cluster service routed through Traefik |
| Traefik      | `https://traefik.home.hgpe.dev`   | k3s built-in Traefik                       |
| AdGuard Home | `https://adguard.home.hgpe.dev`   | Local DNS                                  |
| Paperless    | `https://paperless.home.hgpe.dev` | Document management                        |

## Common commands

```sh
cd infra/opentofu/environments/homelab
tofu plan
tofu apply
```
