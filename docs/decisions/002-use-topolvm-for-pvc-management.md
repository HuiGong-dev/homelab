# ADR-002: Use TopoLVM for serious PVC management

## Status

Accepted

## Date

2026-06-12

## Context

The homelab Kubernetes cluster originally used the default `local-path` storage backend for persistent workloads.

This worked for simple local persistence, but it caused problems for proper PVC capacity management. In Grafana, multiple PVCs showed the same usage and total size because kubelet reported backing filesystem statistics instead of meaningful per-PVC usage.

Example symptom before migration:

```text
paperless-consume   21.5 GiB / 241 GiB
paperless-data      21.5 GiB / 241 GiB
paperless-db-1      21.5 GiB / 241 GiB
paperless-export    21.5 GiB / 241 GiB
paperless-media     21.5 GiB / 241 GiB
```

This made PVC monitoring unreliable and unsuitable for capacity planning.

For more serious stateful workloads, the platform needs:

- meaningful per-PVC usage metrics
- predictable PVC sizing
- volume expansion support
- better local storage capacity planning
- more production-like storage behavior
- clearer operational visibility

TopoLVM was introduced as a local LVM-backed CSI storage backend. It provisions real logical volumes per PVC and exposes CSI storage capacity to Kubernetes.

## Decision

Use TopoLVM as the default storage backend for serious stateful workloads in the homelab.

The main StorageClass is:

```yaml
storageClassName: topolvm-local-rwo
```

`local-path` may still be used for temporary, disposable, or low-value test workloads, but it should not be used for workloads where capacity monitoring, restore testing, or operational visibility matters.

## Selected workloads

The first migrated workloads were:

### kube-prometheus-stack

The monitoring stack was migrated first because its data is disposable.

Old Prometheus, Alertmanager, and Grafana PVCs were deleted and recreated using `topolvm-local-rwo`.

This was a low-risk validation target.

### Paperless-ngx

Paperless was migrated after the monitoring stack.

Because Paperless contains important data, the migration used an application-level backup and restore flow:

```text
Paperless exporter backup
→ recreate PVCs with TopoLVM
→ restore documents using Paperless importer
→ verify documents in UI
```

This validated both the storage migration and the disaster recovery path.

## Alternatives considered

### Continue using local-path

Rejected.

`local-path` is simple and good enough for basic persistence, but it does not provide useful per-PVC capacity visibility in this setup.

It caused misleading Grafana PVC usage panels, making it hard to answer basic operational questions such as:

- How full is `paperless-media`?
- Which PVC is growing?
- When should a PVC be expanded?
- Which workload is consuming storage?

### Use TopoLVM only for selected workloads

Accepted as the practical rollout approach.

TopoLVM should be used for important workloads first. Not every test workload needs serious storage management.

### Use network storage instead

Deferred.

Network storage may be useful later, especially for workloads that need easier rescheduling across nodes. For now, the homelab is intentionally using local storage with explicit backup/restore procedures.

## Consequences

### Positive consequences

- PVC usage monitoring is now meaningful.
- Grafana can show actual per-PVC usage.
- Capacity planning is much clearer.
- PVC sizes are explicit and intentional.
- TopoLVM-backed PVCs can be expanded when needed.
- Stateful workload behavior is closer to real platform operations.
- Backup/restore procedures were tested during the Paperless migration.
- Storage migration became a useful platform engineering story.

Example result after migration:

```text
paperless-consume   24 KiB  / 9.75 GiB
paperless-data      460 KiB / 9.75 GiB
paperless-db-1      102 MiB / 9.75 GiB
paperless-export    24 KiB  / 19.5 GiB
paperless-media     13.5 MiB / 19.5 GiB
redis-data          140 KiB / 1.90 GiB
```

### Negative consequences / trade-offs

- TopoLVM is more complex than `local-path`.
- Local storage topology matters.
- Pods using TopoLVM-backed PVCs must be schedulable on nodes with TopoLVM capacity.
- Node affinity, node selectors, and old pinning rules can block scheduling.
- TopoLVM is not a backup solution.
- Application-level backup and restore are still required for important data.

## Important operational lesson

Avoid hostname-based node pinning for TopoLVM-backed workloads.

During the migration, Prometheus initially stayed pending because it still had old scheduling constraints from a previous node-drain maintenance scenario. It was pinned toward the old agent node, while TopoLVM capacity existed on `k3s-server-01`.

The scheduler effectively saw:

```text
agent node:
  Prometheus wanted to run here
  but no TopoLVM capacity existed

server node:
  TopoLVM capacity existed
  but Prometheus was not allowed to run here
```

This created a scheduling deadlock.

Preferred approach:

- rely on `WaitForFirstConsumer` and CSI topology where possible
- avoid pinning workloads to specific node names
- if scheduling constraints are needed, use role labels such as:

```yaml
nodeSelector:
  storage: topolvm
```

instead of:

```yaml
nodeSelector:
  kubernetes.io/hostname: k3s-server-01
```

## Implementation notes

### TopoLVM StorageClass

The StorageClass should use topology-aware binding:

```yaml
volumeBindingMode: WaitForFirstConsumer
```

This allows Kubernetes to schedule the pod and provision the volume based on node storage availability.

### Initial Paperless PVC sizing

Current Paperless usage is small, with only 18 documents and around 14 MiB of backup data.

Initial PVC sizes:

```text
paperless-media     20Gi
paperless-export    20Gi
paperless-data      10Gi
paperless-db-1      10Gi
paperless-consume   10Gi
redis-data          2Gi
```

This gives enough room for future document scanning while keeping requested storage reasonable.

Estimated future document pile:

```text
~1,500 physical sheets
~3,000 single-sided scanned pages
~1 MiB per page
≈ 3 GiB raw scan data
```

A 20Gi media PVC should be sufficient initially, with expansion available later if needed.

## Validation

Validation completed:

- TopoLVM smoke test succeeded.
- kube-prometheus-stack PVCs were recreated with `topolvm-local-rwo`.
- Prometheus scheduling issue was identified and fixed.
- Grafana, Alertmanager, and Prometheus all started successfully.
- Paperless PVCs were recreated with `topolvm-local-rwo`.
- Paperless documents were restored using the importer.
- Paperless UI showed restored documents.
- Grafana PVC usage panel now reports meaningful per-PVC usage.
- `kubectl get logicalvolumes -A` and `sudo lvs` confirmed TopoLVM logical volumes were created.

## Future follow-ups

- Add PVC usage alerts, for example:
  - warning at 80%
  - critical at 90%

- Document the Paperless restore process.
- Test PVC expansion with a non-critical workload.
- Consider whether all future stateful apps should default to `topolvm-local-rwo`.
- Keep `local-path` only for disposable workloads.
- Continue improving backup copies to VM-NAS and encrypted Cloudflare R2.
- Consider network storage later if multi-node rescheduling becomes more important.

## Decision summary

Use TopoLVM for serious PVC management because it provides real per-PVC capacity visibility, better expansion behavior, and more production-like storage operations than `local-path`.

`local-path` remains acceptable for disposable test workloads, but not for important stateful services such as Paperless, monitoring, databases, or platform services that require meaningful operational visibility.
