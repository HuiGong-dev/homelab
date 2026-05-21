# How to create templateon proxmox

The idea matches Proxmox’s cloud-init model: the template stays generic, and clones receive the actual user/SSH/IP config later via cloud-init/OpenTofu. Proxmox documents cloning a cloud-init template and then setting SSH key/IP on the clone, not baking personal users into the template.

## 0. Check whether VMID 9000 already exists

Assume we want to create a template with id 9000. It could be any number available on proxmox.

On the Proxmox host:

```bash
qm status 9000
```

If it exists and you don’t need it anymore:

```bash
qm stop 9000
qm destroy 9000 --purge
```

Only destroy it if you’re sure. No “oopsie archaeology” here.

## 1. Install image customization tooling on Proxmox

```bash
apt update
apt install -y libguestfs-tools
```

This lets you inject `qemu-guest-agent` into the cloud image before turning it into a template.

## 2. Download Ubuntu 24.04 cloud image

```bash
cd /var/lib/vz/template/iso

wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img \
  -O ubuntu-24.04-noble-server-cloudimg-amd64.img
```

## 3. Install qemu guest agent into the image

```bash
virt-customize \
  -a ubuntu-24.04-noble-server-cloudimg-amd64.img \
  --install qemu-guest-agent
```

## 4. Create the VM shell

Adjust `vmbr0` and `local-lvm` if your storage/bridge names differ.

```bash
qm create 9000 \
  --name ubuntu-2404-cloudinit-template \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --agent enabled=1
```

## 5. Import the cloud image as disk

```bash
qm importdisk 9000 \
  /var/lib/vz/template/iso/ubuntu-24.04-noble-server-cloudimg-amd64.img \
  local-lvm
```

Then attach it:

```bash
qm set 9000 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:vm-9000-disk-0,discard=on
```

Proxmox examples commonly use `qm importdisk`, attach the imported disk, add a cloud-init drive, and then convert the VM to a template.

## 6. Add cloud-init drive

```bash
qm set 9000 --ide2 local-lvm:cloudinit
```

## 7. Set boot order and console

```bash
qm set 9000 --boot order=scsi0
qm set 9000 --serial0 socket --vga serial0
```

The serial console is useful when networking/cloud-init goes sideways.

## 8. Resize root disk

For a reusable homelab template, I’d give the base disk 10 GB.

```bash
qm resize 9000 scsi0 10G
```

## 9. Do **not** set user or SSH key on the template

Important part:

```bash
# Do NOT do this on the template:
# qm set 9000 --ciuser ansible
# qm set 9000 --sshkey ~/.ssh/id_ed25519.pub
```

For the template itself, leave these unset.

Check config:

```bash
qm config 9000
```

You should see things like:

```text
ide2: local-lvm:cloudinit
scsi0: local-lvm:vm-9000-disk-0
agent: enabled=1
```

But ideally **no**:

```text
ciuser:
sshkeys:
cicustom:
```

## 10. Convert to template

```bash
qm template 9000
```

Now you have a clean base template.

## 11. Use OpenTofu to create the real first user

In your OpenTofu VM resource, your clone should set the initial user there:

```hcl
initialization {
  user_account {
    username = "ansible"
    keys = [
      trimspace(file("~/.ssh/id_ed25519_ansible.pub"))
    ]
  }

  ip_config {
    ipv4 {
      address = "dhcp"
    }
  }
}
```
