# Install Home Assistant OS VM manually

This runbook creates the `home-assistant` VM directly on Proxmox using the Home
Assistant OS KVM/Proxmox image. This VM is intentionally manual instead of
OpenTofu-managed because importing the HAOS disk through the bpg/proxmox
provider requires SSH access with root or passwordless sudo on the Proxmox
node.

HAOS is an appliance OS. It does not use cloud-init, so OpenTofu cannot inject
an SSH user, SSH keys, or static network config the same way it can for Ubuntu
cloud-image VMs.

Assumptions:

- Proxmox node: `pve`
- VM name: `home-assistant`
- VM ID: `106`
- DHCP reservation IP: `192.168.178.15`
- MAC address: `BC:24:11:48:41:01`
- Bridge: `vmbr0`
- Disk datastore: `local-lvm`
- Image/template datastore: `local`
- HAOS version: `17.3`

Reserve `192.168.178.15` for `BC:24:11:48:41:01` in the router before or after
creating the VM.

## 1. Download the HAOS image

Run these commands on the Proxmox host as root.

If a previous OpenTofu attempt already downloaded this file, keep it:

```bash
ls -lh /var/lib/vz/template/iso/haos_ova-17.3.qcow2.img
```

If it exists, use it as the image path:

```bash
IMAGE=/var/lib/vz/template/iso/haos_ova-17.3.qcow2.img
```

Otherwise download and decompress the official KVM/Proxmox image:

```bash
cd /var/lib/vz/template/iso

HAOS_VERSION=17.3

wget "https://github.com/home-assistant/operating-system/releases/download/${HAOS_VERSION}/haos_ova-${HAOS_VERSION}.qcow2.xz"
unxz -k "haos_ova-${HAOS_VERSION}.qcow2.xz"

IMAGE="/var/lib/vz/template/iso/haos_ova-${HAOS_VERSION}.qcow2"
```

## 2. Check whether VM 106 already exists

```bash
qm status 106
qm config 106
```

If VM `106` exists from a failed test and contains no data you need, remove it:

```bash
qm stop 106
qm destroy 106 --purge
```

Only destroy it if you are sure it is disposable.

## 3. Create the VM shell

```bash
qm create 106 \
  --name home-assistant \
  --memory 4096 \
  --cores 2 \
  --machine q35 \
  --bios ovmf \
  --net0 virtio=BC:24:11:48:41:01,bridge=vmbr0 \
  --ostype l26 \
  --agent enabled=1
```

## 4. Import and attach the HAOS disk

```bash
qm importdisk 106 "$IMAGE" local-lvm
```

Attach the imported disk. If `qm importdisk` reports a different volume than
`local-lvm:vm-106-disk-0`, use the reported volume in the `--scsi0` value.

```bash
qm set 106 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:vm-106-disk-0,discard=on,iothread=1
```

## 5. Add UEFI disk and boot settings

```bash
qm set 106 \
  --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=0 \
  --boot order=scsi0 \
  --serial0 socket \
  --vga std \
  --onboot 1
```

## 6. Resize the disk

```bash
qm resize 106 scsi0 32G
```

HAOS should grow into the larger virtual disk on boot.

## 7. Start Home Assistant

```bash
qm start 106
qm status 106
```

Wait a few minutes, then open:

```text
http://192.168.178.15:8123
```

If the DHCP reservation has not taken effect yet, check the VM console or the
router lease table for the current address.

## 8. Verify

On Proxmox:

```bash
qm config 106
qm guest cmd 106 network-get-interfaces
```

The guest-agent command may fail until HAOS has fully booted.

From another machine:

```bash
curl -I http://192.168.178.15:8123
```

## 9. Reverse proxy note

If Home Assistant is routed behind Traefik or another reverse proxy, Home
Assistant must explicitly trust the proxy IP. Without this, browser requests
through the proxy can fail with HTTP `400`.

The HAOS console is limited, so install the community File Editor app/add-on
from Home Assistant and edit:

```text
/homeassistant/configuration.yaml
```

Add or update:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.178.13
    - 192.168.178.14
```

Replace the example IP addresses with the actual IP address or addresses of the
proxy sending requests to Home Assistant. Restart Home Assistant after saving
the file.

## 10. SSH note

Do not expect normal SSH access from cloud-init. HAOS does not create a Linux
user from Proxmox metadata. If shell access is needed later, use Home
Assistant's supported add-on or console workflows from inside Home Assistant.
