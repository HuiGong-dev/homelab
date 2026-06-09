# Install TopoLVM with Flux

This runbook installs TopoLVM as the CSI provider for local LVM-backed storage.
The Kubernetes pieces are managed by Flux from this repository. The backing
virtual disk and LVM volume group are prepared manually on the K3s server node.

## Ownership

- Manual Proxmox change: add an extra virtual disk to `k3s-server-01`
- Manual node prep: create the LVM physical volume and volume group
- Node selector label: `storage=topolvm`
- Flux Helm repository: `infrastructure/sources/topolvm.yaml`
- Flux Helm release: `infrastructure/controllers/topolvm/release.yaml`
- TopoLVM Helm values: `infrastructure/controllers/topolvm/values-configmap.yaml`

## 1. Add the server disk

In Proxmox, add a new virtual disk to the K3s server node.

Current setup:

- Node: `k3s-server-01`
- New disk inside the VM: `/dev/sdb`
- Stable disk ID:
  `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`

Inside the K3s server node, confirm that `/dev/sdb` maps to the stable disk ID:

```bash
ls -l /dev/disk/by-id/
```

Look for the `scsi-0QEMU_QEMU_HARDDISK_drive-scsi1` symlink and confirm it
points at `../../sdb`.

Use the stable `/dev/disk/by-id/` path for LVM commands, not `/dev/sdb`.
The `/dev/sdX` name can change after reboot or disk enumeration changes.

## 2. Create the LVM volume group

On the K3s server node, create the physical volume and volume group:

```bash
sudo pvcreate /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
sudo vgcreate topolvm-vg /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
```

Verify the LVM state:

```bash
sudo pvs
sudo vgs
sudo lvs
```

Expected result:

- Physical volume exists on
  `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`
- Volume group exists as `topolvm-vg`
- TopoLVM will create logical volumes in `topolvm-vg`

## 3. Label the storage node

TopoLVM's `lvmd` and CSI node plugin are restricted to nodes with this label:

```bash
kubectl label node k3s-server-01 storage=topolvm
```

Confirm the label:

```bash
kubectl get node k3s-server-01 --show-labels
```

The Helm values use this selector:

```yaml
lvmd:
  nodeSelector:
    storage: topolvm

node:
  nodeSelector:
    storage: topolvm
```

This prevents TopoLVM from trying to run `lvmd` on nodes that do not have the
`topolvm-vg` volume group.

## 4. Manage TopoLVM with Flux

TopoLVM is installed by the official Helm chart from:

```text
https://topolvm.github.io/topolvm
```

The Flux HelmRelease pins chart `16.1.1`, which installs TopoLVM app version
`0.41.0`.

The StorageClass is:

```text
topolvm-local-rwo
```

Important Helm values:

```yaml
lvmd:
  deviceClasses:
    - name: ssd
      volume-group: topolvm-vg
      default: true
      spare-gb: 10

storageClasses:
  - name: topolvm-local-rwo
    storageClass:
      fsType: ext4
      reclaimPolicy: Delete
      isDefaultClass: false
      volumeBindingMode: WaitForFirstConsumer
      allowVolumeExpansion: true
      additionalParameters:
        "topolvm.io/device-class": "ssd"
```

`topolvm-local-rwo` is intentionally not the default StorageClass. Existing
`local-path` workloads are not migrated automatically.

## 5. Reconcile and verify

Render the local manifests:

```bash
kubectl kustomize infrastructure
```

Reconcile Flux:

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infrastructure -n flux-system --with-source
```

Check the Helm source and release:

```bash
flux get sources helm -n flux-system
flux get helmreleases -n flux-system
```

Check TopoLVM resources:

```bash
kubectl -n topolvm-system get pods
kubectl get storageclass topolvm-local-rwo
kubectl -n topolvm-system get podmonitor
```

The `topolvm-lvmd` and `topolvm-node` pods should run only on the node labeled
`storage=topolvm`.

## 6. Test a PVC

Create a temporary PVC and pod that explicitly use the TopoLVM StorageClass:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: topolvm-smoke-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: topolvm-local-rwo
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: topolvm-smoke-test
spec:
  restartPolicy: Never
  containers:
    - name: shell
      image: busybox:1.37
      command:
        - sh
        - -c
        - "echo topolvm-ok > /data/test.txt && cat /data/test.txt && sleep 30"
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: topolvm-smoke-test
```

Verify the PVC binds and the pod completes:

```bash
kubectl get pvc topolvm-smoke-test
kubectl logs pod/topolvm-smoke-test
```

Delete the smoke-test resources after validation.
