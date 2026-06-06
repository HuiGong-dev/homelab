# Grafana dashboard and PVC incident

Use this note as both a post-incident record and a recovery runbook for the
Grafana side of `kube-prometheus-stack`.

## Date

2026-06-06

## Summary

While adding custom Grafana dashboards through the `kube-prometheus-stack`
dashboard sidecar, the Kubernetes storage dashboard was renamed and had its
Grafana dashboard UID changed more than once.

Grafana persisted the intermediate dashboard identities in its SQLite database.
This left two provisioned dashboards with the same title and internal dashboard
ID but different UIDs:

- `peR80gTGk`
- `kubernetes-storage-local-path`

The UI could not delete either duplicate because both were considered
provisioned dashboards. Grafana then started logging errors about multiple
provisioned dashboards for the same internal ID.

To reset the bad Grafana database state, the Grafana PVC was deleted. The first
reset attempt exposed a second issue: the Grafana chart remembered the deleted
PV name and kept recreating a PVC bound to a non-existent PV. The final fix was
to disable Grafana persistence temporarily, let Grafana start clean, then
re-enable persistence with `lookupVolumeName: false`.

Prometheus and Alertmanager data were not deleted.

## Impact

- Grafana briefly had duplicate `Kubernetes Storage` dashboards.
- Grafana provisioning failed for the affected dashboard.
- Grafana was temporarily unavailable while its deployment and PVC were reset.
- Prometheus metrics data remained intact.
- Alertmanager data remained intact.

## What Happened

### 1. Dashboard sidecar was working

The Grafana dashboard sidecar successfully discovered labeled dashboard
ConfigMaps and wrote JSON files into `/tmp/dashboards`.

Useful sidecar log lines:

```text
Writing /tmp/dashboards/homelab-kubernetes-storage-overview.json
Response: 200 OK {"message":"Dashboards config reloaded"}
```

This confirmed that the sidecar and the `grafana_dashboard: "1"` label were not
the root problem.

### 2. The old default dashboard was not the same problem

The sidecar also wrote chart-provided dashboards such as:

```text
/tmp/dashboards/persistentvolumesusage.json
```

That file comes from kube-prometheus-stack's built-in Grafana dashboards. It is
separate from the custom dashboard ConfigMap. It can be removed only by
disabling default dashboards or by accepting that chart dashboards coexist with
custom dashboards.

### 3. Grafana had duplicate provisioned dashboard records

The Grafana search API showed two dashboards with the same title:

```text
Kubernetes Storage /d/kubernetes-storage-local-path/kubernetes-storage
Kubernetes Storage /d/peR80gTGk/kubernetes-storage
```

Grafana logs showed the real problem:

```text
failed to save dashboard
error="unexpected number of dashboards for id 616527860543488. found: 2. desired: 1"

found more than one provisioned dashboard with ID 616527860543488
```

Because the dashboards were provisioned, the UI could not delete them.

### 4. Resetting only Grafana was safe

Grafana, Prometheus, and Alertmanager use separate storage:

```text
monitoring/kube-prometheus-stack-grafana
monitoring/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
monitoring/alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0
```

Deleting only the Grafana PVC resets Grafana's local SQLite database and UI
state. It does not delete Prometheus time series data.

### 5. The first PVC reset got stuck

After deleting the Grafana PVC, Flux/Helm recreated a PVC like this:

```yaml
spec:
  storageClassName: local-path
  volumeName: pvc-4b6cc457-1ff8-4528-a761-8d8d07f58b40
status:
  phase: Pending
```

But the referenced PV no longer existed:

```text
Error from server (NotFound): persistentvolumes "pvc-4b6cc457-1ff8-4528-a761-8d8d07f58b40" not found
```

Because `spec.volumeName` was set, Kubernetes waited for that exact PV instead
of allowing `local-path` to provision a new one.

The Grafana chart caused this by using:

```yaml
grafana:
  persistence:
    lookupVolumeName: true
```

That is the chart default. It attempts to preserve the old PV binding across
Helm upgrades, which is usually helpful but harmful after intentionally deleting
the PV.

## Root Cause

There were two interacting causes:

1. Grafana dashboard UIDs were changed during dashboard renaming.
2. Grafana persisted provisioned dashboard state in SQLite on the Grafana PVC.

The PVC reset then hit a second chart behavior:

1. The Grafana chart remembered the old PV name.
2. The old PV had already been deleted.
3. Helm kept rendering a PVC that referenced a non-existent PV.

## Recovery

### GitOps vs Emergency Apply

In normal operation, do not use `kubectl apply` for these infrastructure
resources. Let Flux apply the repository state:

```sh
git push
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infrastructure -n flux-system
flux reconcile helmrelease kube-prometheus-stack -n flux-system
```

The ordering matters because the HelmRelease reads chart values from the live
`kube-prometheus-stack-values` ConfigMap:

```yaml
valuesFrom:
  - kind: ConfigMap
    name: kube-prometheus-stack-values
    valuesKey: values.yaml
```

Reconciling only the HelmRelease does not read local file edits. It reads the
ConfigMap that already exists in the cluster. Therefore, the live ConfigMap must
be updated before reconciling the HelmRelease.

During this incident, `kubectl apply` was used as an emergency shortcut because
the cluster needed to be unstuck before a normal commit/push loop:

```sh
kubectl apply -f infrastructure/controllers/kube-prometheus-stack/values-configmap.yaml
kubectl apply -f infrastructure/controllers/kube-prometheus-stack/release.yaml
flux reconcile helmrelease kube-prometheus-stack -n flux-system
```

This is not required if the normal Flux Kustomization reconciliation has already
applied the updated ConfigMap and HelmRelease. If `kubectl apply` is used during
incident recovery, make sure the same changes are committed to Git so Flux does
not later revert the live state.

### 1. Stabilize dashboard UID in Git

The custom storage dashboard should have a final semantic UID:

```json
"uid": "homelab-kubernetes-storage-overview"
```

Avoid reusing imported dashboard UIDs after a dashboard has been renamed or
repurposed.

### 2. Temporarily disable Grafana persistence

Set Grafana persistence off:

```yaml
grafana:
  persistence:
    enabled: false
```

Apply the values and reconcile:

```sh
kubectl apply -f infrastructure/controllers/kube-prometheus-stack/values-configmap.yaml
flux reconcile helmrelease kube-prometheus-stack -n flux-system
```

If Flux is stuck waiting on the broken PVC during rollback, temporarily add:

```yaml
upgrade:
  disableWait: true
  crds: CreateReplace
  remediation:
    retries: 3
rollback:
  disableWait: true
```

Then apply the HelmRelease and reconcile again:

```sh
kubectl apply -f infrastructure/controllers/kube-prometheus-stack/release.yaml
flux reconcile helmrelease kube-prometheus-stack -n flux-system
```

### 3. Delete only the broken Grafana PVC

Scale Grafana down and delete the Grafana PVC only:

```sh
kubectl -n monitoring scale deploy kube-prometheus-stack-grafana --replicas=0
kubectl -n monitoring delete pvc kube-prometheus-stack-grafana
```

Do not delete the Prometheus or Alertmanager PVCs:

```text
prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0
```

Reconcile, then scale Grafana back up:

```sh
flux reconcile helmrelease kube-prometheus-stack -n flux-system
kubectl -n monitoring scale deploy kube-prometheus-stack-grafana --replicas=1
```

At this point Grafana should run with `emptyDir` storage and a clean SQLite
database.

### 4. Re-enable Grafana persistence safely

Re-enable persistence with `lookupVolumeName: false`:

```yaml
grafana:
  persistence:
    enabled: true
    type: pvc
    storageClassName: local-path
    lookupVolumeName: false
    accessModes:
      - ReadWriteOnce
    size: 2Gi
```

Apply and reconcile:

```sh
kubectl apply -f infrastructure/controllers/kube-prometheus-stack/values-configmap.yaml
flux reconcile helmrelease kube-prometheus-stack -n flux-system
```

Confirm the new PVC binds to a fresh PV:

```sh
kubectl -n monitoring get pvc kube-prometheus-stack-grafana
kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana
```

Expected:

```text
kube-prometheus-stack-grafana   Bound   ...   2Gi   RWO   local-path
kube-prometheus-stack-grafana-* 3/3     Running
```

### 5. Remove temporary Helm recovery settings

After Grafana is running on the new PVC, remove:

```yaml
upgrade:
  disableWait: true
rollback:
  disableWait: true
```

Then reconcile normally:

```sh
kubectl apply -f infrastructure/controllers/kube-prometheus-stack/release.yaml
flux reconcile helmrelease kube-prometheus-stack -n flux-system
```

Confirm Flux is healthy:

```sh
kubectl -n flux-system get helmrelease kube-prometheus-stack
```

Expected:

```text
READY=True
STATUS=Helm upgrade succeeded
```

## Final State

The steady-state Grafana persistence values should be:

```yaml
grafana:
  persistence:
    enabled: true
    type: pvc
    storageClassName: local-path
    lookupVolumeName: false
    accessModes:
      - ReadWriteOnce
    size: 2Gi
```

The storage dashboard UID should be stable:

```json
"uid": "homelab-kubernetes-storage-overview"
```

## Lessons

- Grafana dashboard UID is the durable identity. File names and titles are not.
- Renaming a provisioned dashboard is safe only if the UID strategy is clear.
- Provisioned dashboards cannot always be removed cleanly from the UI.
- Grafana persistence makes dashboard mistakes durable.
- Resetting the Grafana PVC is safe for Prometheus data, but only if the
  Prometheus and Alertmanager PVCs are left alone.
- For Grafana on `local-path`, set `lookupVolumeName: false` before intentionally
  deleting and recreating the Grafana PVC.
- Temporary `upgrade.disableWait` and `rollback.disableWait` can help Flux escape
  a Helm remediation loop, but they should be removed after recovery.

## Useful Commands

Inspect Flux and HelmRelease state:

```sh
kubectl -n flux-system get helmrelease kube-prometheus-stack
kubectl -n flux-system describe helmrelease kube-prometheus-stack
flux reconcile helmrelease kube-prometheus-stack -n flux-system
```

Inspect Grafana dashboard sidecar logs:

```sh
kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana -c grafana-sc-dashboard --since=30m
```

Inspect Grafana logs:

```sh
kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana -c grafana --since=30m
```

Inspect Grafana PVC and pod state:

```sh
kubectl -n monitoring get pvc,pods -l app.kubernetes.io/name=grafana
kubectl -n monitoring get pvc kube-prometheus-stack-grafana -o yaml
kubectl -n monitoring describe deploy kube-prometheus-stack-grafana
```

Inspect local-path provisioner logs:

```sh
kubectl -n kube-system logs deploy/local-path-provisioner --tail=120
```

Render the infrastructure Kustomization locally:

```sh
flux build kustomization infrastructure \
  --path ./infrastructure \
  --kustomization-file ./clusters/homelab/infrastructure.yaml \
  --dry-run
```
