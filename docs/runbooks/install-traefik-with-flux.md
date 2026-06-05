# Install Traefik with Flux

This runbook installs Traefik as Flux-managed cluster infrastructure. k3s
packaged Traefik is disabled, and the Traefik Helm release is reconciled from
this repository.

## Why Flux-managed Traefik

Traefik is managed by Flux instead of the k3s packaged addon so ownership is in
one place. The Helm chart version, values, Cloudflare DNS challenge Secret,
dashboard route, and off-cluster routes are all declared in GitOps-managed
cluster infrastructure. This avoids the previous split where k3s installed
Traefik while Ansible customized it by writing a `HelmChartConfig` into the k3s
manifests directory.

## Ownership

- k3s server config: `provisioning/ansible/roles/k3s_server`
- homelab k3s override: `provisioning/ansible/inventories/homelab/group_vars/k3s_servers.yml`
- Flux Helm repository: `infrastructure/sources/traefik.yaml`
- Flux Helm release: `infrastructure/controllers/traefik/release.yaml`
- Traefik Helm values: `infrastructure/controllers/traefik/values-configmap.yaml`
- cert-manager Helm release: `infrastructure/controllers/cert-manager/release.yaml`
- Cloudflare API token Secret: `infrastructure/controllers/cert-manager/secrets.sops.yaml`
- TLS and routing resources: `platform/`

For day-to-day app and service routing, use
`docs/runbooks/onboard-app-or-service.md`.
For DNS, certificate, and Traefik routing failures, use
`docs/runbooks/troubleshoot-routing-dns-tls.md`.

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

cert-manager reads the Cloudflare DNS-01 token from this Secret:

```text
cloudflare-api-token
```

Edit the encrypted Secret with SOPS:

```sh
sops infrastructure/controllers/cert-manager/secrets.sops.yaml
```

For Kubernetes Secret manifests under `apps/` and `infrastructure/`, `.sops.yaml`
encrypts only `data` and `stringData`. Object fields such as `apiVersion`,
`kind`, `metadata.name`, and `metadata.namespace` stay readable.

If creating a new Kubernetes Secret file, write the plain manifest first, then
encrypt it:

```sh
sops -e -i infrastructure/controllers/cert-manager/secrets.sops.yaml
```

## 3. Manage Helm values

The HelmRelease references the chart values from a ConfigMap:

```yaml
valuesFrom:
  - kind: ConfigMap
    name: traefik-values
    valuesKey: values.yaml
```

Edit Traefik chart values in:

```text
infrastructure/controllers/traefik/values-configmap.yaml
```

The ConfigMap has `reconcile.fluxcd.io/watch: Enabled`, so Flux's
helm-controller should react quickly when the referenced values change.

## 4. Drift detection

The Traefik HelmRelease enables Flux Helm drift detection:

```yaml
driftDetection:
  mode: enabled
```

This makes Flux detect and correct manual changes to resources managed by the
Traefik Helm release. Make normal changes in `release.yaml` or
`values-configmap.yaml`, not with `kubectl edit` on Helm-managed resources.

## 5. Reconcile with Flux

Commit and push the repository changes, then reconcile Flux:

```sh
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infrastructure -n flux-system --with-source
flux reconcile kustomization platform-config -n flux-system --with-source
```

Check the Helm source and release:

```sh
flux get sources helm -n flux-system
flux get sources oci -n flux-system
flux get helmreleases -n flux-system
```

## 6. Verify Traefik

Check the namespace resources:

```sh
kubectl -n traefik get pods,svc,pvc,secret
kubectl -n flux-system get helmrelease traefik
kubectl -n traefik rollout status deployment/traefik --timeout=300s
kubectl get clusterissuer
kubectl -n traefik get certificate home-hgpe-dev-wildcard
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

## 7. Let's Encrypt notes

cert-manager, not Traefik, owns Let's Encrypt. The wildcard Certificate is
intentionally configured for staging validation first:

```text
home.hgpe.dev
*.home.hgpe.dev
```

After staging succeeds, switch the Certificate issuer manually by changing:

```yaml
issuerRef:
  name: letsencrypt-prod
```

Do not re-enable Traefik ACME or the file provider for this migration.

## 8. Rollback

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
