# Runbook: K3s Cluster Upgrade

## Purpose

This runbook describes the operational process for upgrading the homelab K3s cluster.

It covers:

- Version update flow with Renovate
- Applying upgrade manifests with Ansible
- Node upgrade execution with system-upgrade-controller
- Handling CNPG PodDisruptionBudgets
- Working around local-path storage limitations
- Pre-upgrade and post-upgrade validation
- Lessons learned from the `v1.36.1+k3s1` upgrade

## Scope

This runbook applies to the homelab K3s cluster with:

- One K3s server node
- One K3s agent node
- Flux-managed workloads
- Ansible-managed system-upgrade-controller manifests
- Renovate-managed version bump pull requests
- local-path-provisioner for local persistent storage
- CloudNativePG for PostgreSQL
- cert-manager for TLS certificates

## Upgrade Strategy

K3s upgrades are performed through system-upgrade-controller.

The upgrade flow is:

```text
Renovate detects a new K3s version
↓
Renovate creates a pull request
↓
Pull request is reviewed and merged
↓
Temporary maintenance changes are applied if required
↓
Ansible playbook updates the system-upgrade-controller Plan resources
↓
system-upgrade-controller drains and upgrades nodes
↓
Cluster health is validated
↓
Temporary maintenance changes are reverted
```

Important ownership model:

```text
Renovate = update discovery and PR creation
Git = desired version source
Ansible = applies upgrade Plan manifests
system-upgrade-controller = performs node upgrade
Flux = reconciles workload manifests
```

Merging a Renovate PR does **not** directly upgrade the cluster. The actual upgrade starts only after Ansible applies the updated Plan resources and the system-upgrade-controller acts on them.

## Key Decisions

The current upgrade strategy is:

- Use system-upgrade-controller for K3s node upgrades.
- Use separate upgrade Plans for server and agent nodes.
- Upgrade the server node before the agent node.
- Keep node drain enabled.
- Use a string value for `drain.timeout`, for example `"10m"`.
- Accept planned downtime for local-path-backed stateful workloads.
- Pin local-path-backed stateful workloads to their storage-owning node.
- Temporarily disable CNPG PDBs during planned maintenance when required.
- Be aware that Flux may revert manual changes to GitOps-managed resources.

## Pre-Upgrade Checklist

### 1. Review Release Notes

Before upgrading, review the target K3s release notes.

Check for:

- Kubernetes version changes
- Known issues
- Bundled component changes
- containerd changes
- CoreDNS changes
- Traefik changes, if relevant
- metrics-server changes
- local-path-provisioner changes

Confirm the upgrade path is valid. Avoid skipping more than one Kubernetes minor version.

### 2. Confirm Current Node Versions

```bash
kubectl get nodes -o wide
```

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'
```

### 3. Check Cluster Health

```bash
kubectl get nodes
kubectl get pods -A
```

Show non-running pods:

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
```

Check Flux health:

```bash
flux get kustomizations -A
flux get helmreleases -A
```

### 4. Check Node Capacity

```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

Check node allocatable resources and requests:

```bash
kubectl describe node <node-name>
```

Pay attention to the `Allocated resources` section.

The agent node should have enough capacity to temporarily host movable/stateless workloads during server maintenance.

### 5. Check Stateful Workloads

List all PVCs and PVs:

```bash
kubectl get pvc -A
kubectl get pv -o wide
```

List pods using PVCs:

```bash
kubectl get pods -A -o json \
  | jq -r '
    .items[]
    | select((.spec.volumes // [])[]?.persistentVolumeClaim != null)
    | "\(.metadata.namespace)/\(.metadata.name) node=\(.spec.nodeName) pvc=" +
      ((.spec.volumes // [])
      | map(select(.persistentVolumeClaim != null)
      | .persistentVolumeClaim.claimName)
      | join(","))'
```

Inspect local-path PV node affinity:

```bash
kubectl describe pv <pv-name>
```

If a PV is tied to a specific node, the workload should be treated as node-local.

### 6. Check PDBs

```bash
kubectl get pdb -A
```

Pay special attention to CNPG-created PDBs, for example:

```text
paperless-db-primary
```

A PDB for a single-instance database can block node drain.

### 7. Clean Up Obsolete Resources

Before upgrading, check for obsolete or leftover resources.

Examples:

- Old Traefik PVC/PV from previous ACME storage
- Old K3s bundled Traefik `HelmChartConfig`
- Unused HelmChart resources
- Unused PVCs

Check whether a PVC is still mounted:

```bash
kubectl get pods -A -o yaml | grep -B5 -A10 "<pvc-name>"
```

Only delete resources after confirming they are no longer used.

### 8. Etcd Snapshot Check

Before and after a K3s upgrade, verify recent etcd snapshots:

```bash
sudo k3s etcd-snapshot list
```

## Upgrade Plan Configuration

The cluster uses two system-upgrade-controller Plans:

```text
k3s-server-upgrade-plan
k3s-agent-upgrade-plan
```

The server plan targets the control-plane/server node.

The agent plan targets non-control-plane nodes and waits for the server plan to complete.

### Server Plan

```yaml
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-server-upgrade-plan
  namespace: system-upgrade
spec:
  concurrency: 1
  version: v1.36.1+k3s1
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
  serviceAccountName: system-upgrade
  cordon: true
  drain:
    force: true
    ignoreDaemonSets: true
    deleteEmptydirData: true
    gracePeriod: 120
    timeout: '10m'
  upgrade:
    image: rancher/k3s-upgrade
```

### Agent Plan

```yaml
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-agent-upgrade-plan
  namespace: system-upgrade
spec:
  concurrency: 1
  version: v1.36.1+k3s1
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: DoesNotExist
  serviceAccountName: system-upgrade
  cordon: true
  drain:
    force: true
    ignoreDaemonSets: true
    deleteEmptydirData: true
    gracePeriod: 120
    timeout: '10m'
  prepare:
    image: rancher/k3s-upgrade
    args:
      - prepare
      - k3s-server-upgrade-plan
  upgrade:
    image: rancher/k3s-upgrade
```

## Important Drain Timeout Note

`drain.timeout` must be configured as a string duration.

Correct:

```yaml
timeout: '10m'
```

Incorrect:

```yaml
timeout: 600
```

Although the field is `IntOrString`, an integer may be interpreted as nanoseconds.

Observed failure:

```text
global timeout reached: 600ns
```

Recommended Ansible variables:

```yaml
k3s_upgrade_drain_timeout: '10m'
k3s_upgrade_drain_grace_period: 120
```

Recommended template:

```yaml
drain:
  force: true
  ignoreDaemonSets: true
  deleteEmptyDirData: true
  gracePeriod: { { k3s_upgrade_drain_grace_period } }
  timeout: '{{ k3s_upgrade_drain_timeout }}'
```

Add a comment in the variable file:

```yaml
# Must be a string duration, e.g. "10m".
# Integer values may be interpreted as nanoseconds by system-upgrade-controller/kubectl drain.
k3s_upgrade_drain_timeout: '10m'
```

## local-path Storage Limitation

The cluster currently uses local-path-provisioner for persistent volumes.

This storage is node-local.

Important limitations:

- Volumes are tied to the node where they were created.
- Pods using local-path volumes cannot freely move to another node.
- Draining the storage-owning node causes downtime for those workloads.
- Adding RAM or CPU to another node does not make local-path data available there.
- local-path does not provide high availability.

Example failure mode:

```text
Stateful pod runs on server node
↓
PVC is backed by local-path PV on server node
↓
Server node is drained
↓
Pod is evicted
↓
Scheduler tries to place pod on agent node
↓
PV node affinity prevents the pod from starting
↓
Pod remains Pending
```

Current policy:

```text
Stateless workloads may move between nodes.
Stateful local-path workloads are pinned to the storage-owning node.
Planned downtime is accepted for local-path-backed stateful workloads.
Important data must be backed up.
```

Potential future storage options:

- NFS-backed storage
- Longhorn
- Rook/Ceph
- External database
- S3-compatible backup and restore workflow

## Stateful Workload Placement

Local-path-backed stateful workloads should be pinned to the node where their data lives.

Use the exact node hostname:

```bash
kubectl get nodes -o wide
```

Example:

```yaml
nodeSelector:
  kubernetes.io/hostname: <server-node-name>
```

Workloads that may need pinning:

- Paperless
- Paperless Redis
- CNPG/PostgreSQL
- Prometheus
- Grafana
- AlertManager
- Loki, if added later with local-path storage

Workloads that should usually remain movable:

- Flux
- cert-manager
- ExternalDNS
- Traefik
- CoreDNS
- metrics-server
- kube-state-metrics
- Prometheus operator
- stateless demo applications

## CNPG PDB Maintenance Handling

CloudNativePG creates PodDisruptionBudgets to protect PostgreSQL pods from voluntary disruptions.

For a single-instance CNPG cluster, the PDB can block node drain.

If planned downtime is acceptable, temporarily disable the CNPG PDB before the node upgrade.

### Disable CNPG PDB

```bash
kubectl -n paperless patch cluster <cluster-name> \
  --type merge \
  -p '{"spec":{"enablePDB":false}}'
```

Verify:

```bash
kubectl -n paperless get pdb
kubectl -n paperless get cluster
```

### Re-enable CNPG PDB

After the upgrade:

```bash
kubectl -n paperless patch cluster <cluster-name> \
  --type merge \
  -p '{"spec":{"enablePDB":true}}'
```

Verify:

```bash
kubectl -n paperless get pdb
kubectl -n paperless get pods -o wide
kubectl -n paperless get cluster
```

## Flux Maintenance Handling

Flux may revert manual changes to GitOps-managed resources.

Example:

```text
Manual patch: enablePDB=false
↓
Flux detects drift
↓
Flux restores the Git-defined state
↓
PDB becomes enabled again
↓
Node drain may be blocked
```

For planned maintenance, use one of the following patterns.

### Preferred Pattern: Suspend the Relevant Kustomization

Suspend the Kustomization managing the CNPG cluster:

```bash
flux suspend kustomization <kustomization-name> -n flux-system
```

Patch the cluster:

```bash
kubectl -n paperless patch cluster <cluster-name> \
  --type merge \
  -p '{"spec":{"enablePDB":false}}'
```

Perform the upgrade.

Re-enable the PDB:

```bash
kubectl -n paperless patch cluster <cluster-name> \
  --type merge \
  -p '{"spec":{"enablePDB":true}}'
```

Resume Flux:

```bash
flux resume kustomization <kustomization-name> -n flux-system
```

Reconcile:

```bash
flux reconcile kustomization <kustomization-name> -n flux-system --with-source
```

### Alternative Pattern: Temporary Git Change

Create a temporary Git commit that disables the PDB.

After maintenance, revert the commit.

This is more auditable but slower.

### Fast Pattern: Patch Live Immediately Before Upgrade

Patch the resource live and start the upgrade before the next Flux reconciliation.

This works for short windows, but it is less reliable and should not be the default.

## Upgrade Procedure

### 1. Run Renovate Manually

If Renovate is self-hosted as a CronJob, create a one-off Job:

```bash
kubectl -n <renovate-namespace> create job \
  --from=cronjob/<renovate-cronjob-name> \
  renovate-manual-$(date +%s)
```

Watch Renovate:

```bash
kubectl -n <renovate-namespace> get pods -w
```

Check logs:

```bash
kubectl -n <renovate-namespace> logs job/<job-name> -f
```

### 2. Review and Merge the PR

Review the K3s version bump.

Confirm the target version is correct.

Merge the PR.

### 3. Apply Temporary Maintenance Changes

If CNPG PDB may block drain, disable it.

Recommended: suspend the relevant Flux Kustomization first.

```bash
flux suspend kustomization <kustomization-name> -n flux-system
```

Then:

```bash
kubectl -n paperless patch cluster <cluster-name> \
  --type merge \
  -p '{"spec":{"enablePDB":false}}'
```

Verify:

```bash
kubectl -n paperless get pdb
```

### 4. Run Ansible

Run the Ansible playbook that updates the system-upgrade-controller manifests.

Example:

```bash
cd ~/homelab/provisioning/ansible
ansible-playbook k3s.yaml
```

### 5. Watch system-upgrade-controller

```bash
kubectl -n system-upgrade get plans -o wide
kubectl -n system-upgrade get pods -w
```

Watch nodes:

```bash
kubectl get nodes -w
```

Useful combined watch:

```bash
watch -n 2 'kubectl get nodes && echo "---" && kubectl -n system-upgrade get pods && echo "---" && kubectl get pods -A | grep -v Running | grep -v Completed'
```

### 6. Confirm Node Versions

```bash
kubectl get nodes -o wide
```

All nodes should report the target K3s version.

## Post-Upgrade Validation

### 1. Node Health

```bash
kubectl get nodes -o wide
```

All nodes should be `Ready`.

### 2. Pod Health

```bash
kubectl get pods -A
```

Check non-running pods:

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
```

### 3. Flux Health

```bash
flux get kustomizations -A
flux get helmreleases -A
```

### 4. Storage Health

```bash
kubectl get pvc -A
kubectl get pv -o wide
```

### 5. CNPG Health

```bash
kubectl -n paperless get cluster
kubectl -n paperless get pods -o wide
kubectl -n paperless get pdb
```

If the PDB was disabled, re-enable it:

```bash
kubectl -n paperless patch cluster <cluster-name> \
  --type merge \
  -p '{"spec":{"enablePDB":true}}'
```

If Flux was suspended, resume it:

```bash
flux resume kustomization <kustomization-name> -n flux-system
```

Reconcile:

```bash
flux reconcile kustomization <kustomization-name> -n flux-system --with-source
```

### 6. Certificate Health

```bash
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl get orders -A
kubectl get challenges -A
```

### 7. Important Routes

```bash
curl -Ik https://grafana.home.hgpe.dev
curl -Ik https://paperless.home.hgpe.dev
curl -Ik https://traefik.home.hgpe.dev
```

### 8. Observability

Check Grafana dashboards for:

- Node readiness
- Pod restarts
- CPU usage
- Memory usage
- API server availability
- CoreDNS errors
- Traefik errors
- Prometheus target health

Check Prometheus targets if needed.

## Rollback Notes

Rollback is not the primary path for K3s upgrades.

Preferred recovery options:

1. Fix configuration issues and let the cluster converge.
2. Restore from Proxmox VM backup/snapshot if the node is severely broken.
3. Restore application data from backups if stateful workloads are affected.

Before future upgrades, create or verify recent backups/snapshots for:

- K3s server VM
- K3s agent VM
- Important application data
- CNPG backups
- Paperless data

## Lessons Learned

### 1. Upgrade Plans Must Cover All Nodes

The first upgrade setup was created when the cluster had only one server node.

After adding an agent node, a separate agent upgrade Plan was required.

### 2. Agent Capacity Matters

The agent node originally had `4 GiB` RAM.

Cluster memory usage was around `5.11 GiB`.

The agent was increased to `8 GiB` RAM before the upgrade to better support temporary workload movement.

### 3. Drain Should Stay Enabled

Do not disable drain just because the cluster is small.

Drain provides a controlled shutdown and eviction process.

Abrupt node upgrades are riskier, especially for stateful workloads.

### 4. `drain.timeout` Must Be a String

An integer timeout caused the drain operation to fail with:

```text
global timeout reached: 600ns
```

Use:

```yaml
timeout: '10m'
```

### 5. local-path Is Not HA Storage

local-path is node-local storage.

It is simple and suitable for the current homelab, but it does not allow stateful workloads to move freely across nodes.

Planned downtime for local-path-backed stateful workloads is accepted.

### 6. CNPG PDBs Can Block Drain

CNPG-created PDBs protect the database.

For planned maintenance with accepted downtime, the PDB may need to be temporarily disabled.

### 7. Flux Can Revert Manual Maintenance Changes

Manual changes to GitOps-managed resources can be reverted by Flux.

Future maintenance should suspend the relevant Kustomization or commit a temporary maintenance state to Git.

### 8. Cleanups Before Upgrade Reduce Confusion

Old resources from previously disabled components should be cleaned up before upgrades.

In this case, old Traefik ACME storage and HelmChartConfig resources were removed.

### 9. Watching the Upgrade Is Valuable

Watching node drain and upgrade behavior made the process easier to understand and validate.

Useful commands:

```bash
kubectl get nodes -w
kubectl -n system-upgrade get pods -w
kubectl get pods -A -o wide
```

## Final Maintenance Policy

For future K3s upgrades:

1. Review release notes.
2. Let Renovate create the PR.
3. Merge the version bump.
4. Prepare maintenance changes.
5. Suspend Flux if live patches are needed.
6. Disable CNPG PDB if required.
7. Run Ansible to apply upgrade Plans.
8. Let system-upgrade-controller upgrade server first, then agent.
9. Validate node, pod, storage, certificate, and GitOps health.
10. Re-enable CNPG PDB.
11. Resume Flux.
12. Document anything unexpected.
