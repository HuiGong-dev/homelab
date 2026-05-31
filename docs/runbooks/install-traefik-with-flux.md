# Install Traefik with Flux

This runbook installs Traefik as Flux-managed cluster infrastructure. k3s
packaged Traefik is disabled, and the Traefik Helm release is reconciled from
this repository.

## Why Flux-managed Traefik

Traefik is managed by Flux instead of the k3s packaged addon so ownership is in
one place. The Helm chart version, values, Cloudflare DNS challenge Secret,
dashboard route, and file-provider routes are all declared in GitOps-managed
cluster infrastructure. This avoids the previous split where k3s installed
Traefik while Ansible customized it by writing a `HelmChartConfig` into the k3s
manifests directory.

## Ownership

- k3s server config: `provisioning/ansible/roles/k3s_server`
- homelab k3s override: `provisioning/ansible/inventories/homelab/group_vars/k3s_servers.yml`
- Flux Helm repository: `infrastructure/sources/traefik.yaml`
- Flux Helm release: `infrastructure/controllers/traefik/release.yaml`
- Cloudflare API token Secret: `infrastructure/controllers/traefik/secrets.sops.yaml`

## 1. Disable packaged k3s Traefik

Confirm the homelab k3s server group disables the packaged Traefik addon:

```yaml
k3s_builtin_traefik_enabled: false
```

Apply the k3s playbook when changing this value:

```sh
cd provisioning/ansible
ansible-playbook playbooks/k3s.yml
```

This renders the k3s server config with `disable: - traefik` and removes the
old Ansible-managed Traefik `HelmChartConfig` manifest.

## 2. Manage the Cloudflare API token

The Traefik chart reads the Cloudflare DNS challenge token from this Secret:

```text
cloudflare-api-token
```

Edit the encrypted Secret with SOPS:

```sh
sops infrastructure/controllers/traefik/secrets.sops.yaml
```

For Kubernetes Secret manifests under `apps/` and `infrastructure/`, `.sops.yaml`
encrypts only `data` and `stringData`. Object fields such as `apiVersion`,
`kind`, `metadata.name`, and `metadata.namespace` stay readable.

If creating a new Kubernetes Secret file, write the plain manifest first, then
encrypt it:

```sh
sops -e -i infrastructure/controllers/traefik/secrets.sops.yaml
```

## 3. Reconcile with Flux

Commit and push the repository changes, then reconcile Flux:

```sh
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infrastructure -n flux-system --with-source
```

Check the Helm source and release:

```sh
flux get sources helm -n flux-system
flux get helmreleases -n flux-system
```

## 4. Verify Traefik

Check the namespace resources:

```sh
kubectl -n traefik get pods,svc,pvc,secret
kubectl -n flux-system get helmrelease traefik
kubectl -n traefik rollout status deployment/traefik --timeout=300s
```

Check logs if the HelmRelease is not ready:

```sh
kubectl -n traefik logs deployment/traefik
```

Test local DNS and HTTPS routes:

```sh
dig traefik.home.hgpe.dev @192.168.178.12
curl -I https://traefik.home.hgpe.dev
curl -I https://adguard.home.hgpe.dev
curl -I https://pve.home.hgpe.dev
```

## 5. Let's Encrypt notes

The Flux-managed install uses its own Traefik namespace and persistent volume,
so it may not reuse the old k3s packaged Traefik `acme.json`. On first install,
expect Traefik to request a fresh certificate for:

```text
home.hgpe.dev
*.home.hgpe.dev
```

For a dry run against Let's Encrypt staging, temporarily add this argument to
the HelmRelease values:

```yaml
- "--certificatesresolvers.cloudflare.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory"
```

Remove the staging CA argument before issuing production certificates.

## 6. Rollback

If Flux-managed Traefik needs to be backed out, suspend or remove the
HelmRelease first:

```sh
flux suspend helmrelease traefik -n flux-system
```

To return to k3s packaged Traefik, set:

```yaml
k3s_builtin_traefik_enabled: true
```

Then rerun:

```sh
cd provisioning/ansible
ansible-playbook playbooks/k3s.yml
```
