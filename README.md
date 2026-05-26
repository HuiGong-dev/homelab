# Homelab

Personal platform engineering homelab running on Proxmox and Kubernetes.

## Tech stack

| Area              | Tools                         | Notes                                      |
| ----------------- | ----------------------------- | ------------------------------------------ |
| Virtualization    | Proxmox                       | VM host for the homelab                    |
| Provisioning      | OpenTofu                      | Declarative VM provisioning                |
| Configuration     | Ansible                       | Host bootstrap and service configuration   |
| Kubernetes        | k3s                           | Lightweight Kubernetes cluster             |
| Ingress           | Traefik                       | k3s built-in ingress controller            |
| Secret management | SOPS + age                    | Encrypted Ansible inventory secrets        |

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

## Secret management

Secrets are committed as encrypted YAML with SOPS and age.

- `.sops.yaml` defines the age recipient used for `*.sops.yml` files.
- `infra/ansible/ansible.cfg` enables the `community.sops.sops` vars plugin.
- `infra/ansible/inventories/homelab/group_vars/all.sops.yml` stores encrypted inventory values such as Cloudflare, Tailscale, and k3s credentials.
- Ansible reads the local age identity from `~/.sops/age.txt`.

## Common commands

```sh
cd infra/opentofu/environments/homelab
tofu plan
tofu apply
```

```sh
cd infra/ansible
ansible-playbook playbooks/test-sops.yml
```
