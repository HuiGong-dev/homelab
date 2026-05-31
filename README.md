# Homelab

Personal platform engineering homelab running on Proxmox and Kubernetes.

## Tech stack

| Area              | Tools                         | Notes                                      |
| ----------------- | ----------------------------- | ------------------------------------------ |
| Virtualization    | Proxmox                       | VM host for the homelab                    |
| Provisioning      | OpenTofu                      | Declarative VM provisioning                |
| Configuration     | Ansible                       | Host bootstrap and service configuration   |
| Kubernetes        | k3s                           | Lightweight Kubernetes cluster             |
| GitOps            | Flux                          | CLI-first Kubernetes reconciliation        |
| Ingress           | Traefik                       | Flux-managed ingress controller            |
| Secret management | SOPS + age                    | Encrypted Ansible and Kubernetes secrets   |

## Layers

| Layer                  | Path                         | Purpose                                      |
| ---------------------- | ---------------------------- | -------------------------------------------- |
| Provisioning           | `provisioning/opentofu`      | Provision VMs on Proxmox                     |
| Configuration          | `provisioning/ansible`       | Bootstrap Linux hosts                        |
| Cluster entrypoints    | `clusters`                   | Per-cluster Flux bootstrap and wiring        |
| Cluster infrastructure | `infrastructure`             | Kubernetes operators, controllers, and repos |
| Applications           | `apps`                       | User-facing Kubernetes workloads             |
| Documentation          | `docs`                       | Runbooks, IP table, architecture notes       |

## GitOps

Flux reconciles the Kubernetes cluster from this repository. It fits this homelab well because it has first-class SOPS + age support for encrypted secrets, is lightweight, works cleanly from the CLI, and models GitOps primitives as native Kubernetes CRDs. That makes it a good match for a platform-engineering workflow where cluster state should be declarative, inspectable, and automation-friendly.

## Current services

| Service      | URL                               | Notes                                      |
| ------------ | --------------------------------- | ------------------------------------------ |
| Proxmox      | `https://pve.home.hgpe.dev`       | Off-cluster service routed through Traefik |
| Traefik      | `https://traefik.home.hgpe.dev`   | Flux-managed Traefik dashboard             |
| AdGuard Home | `https://adguard.home.hgpe.dev`   | Local DNS                                  |
| Paperless    | `https://paperless.home.hgpe.dev` | Document management                        |

## Secret management

Secrets are committed as encrypted YAML with SOPS and age.

- `.sops.yaml` defines the age recipient used for `*.sops.yml` files.
- Kubernetes Secret manifests under `apps/` and `infrastructure/` encrypt only
  `data` and `stringData`, leaving Kubernetes object metadata readable.
- `provisioning/ansible/ansible.cfg` enables the `community.sops.sops` vars plugin.
- `provisioning/ansible/inventories/homelab/group_vars/all.sops.yml` stores encrypted inventory values such as Cloudflare, Tailscale, and k3s credentials.
- Ansible reads the local age identity from `~/.sops/age.txt`.

## Ingress

k3s packaged Traefik is disabled for the homelab cluster in
`provisioning/ansible/inventories/homelab/group_vars/k3s_servers.yml`.
Traefik is installed by Flux from `infrastructure/controllers/traefik` using the
Helm repository in `infrastructure/sources/traefik.yaml`.

Traefik is Flux-managed instead of k3s-managed so the ingress controller,
certificate resolver settings, dashboard route, file-provider routes, and
Cloudflare token Secret all live in the same GitOps layer. This avoids the old
split where k3s installed Traefik while Ansible customized it by writing a
`HelmChartConfig` into the k3s manifests directory.

See `docs/runbooks/install-traefik-with-flux.md` for install and verification
steps.

## Common commands

```sh
cd provisioning/opentofu/environments/homelab
tofu plan
tofu apply
```

```sh
cd provisioning/ansible
ansible-playbook playbooks/test-sops.yml
```
