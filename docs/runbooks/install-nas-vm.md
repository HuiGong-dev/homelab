# Install NAS VM

This runbook creates `nas-vm` in Proxmox with OpenTofu, attaches the Seagate USB
disk manually as root, and configures Samba with Ansible. The Seagate USB disk
is formatted manually once, then mounted by UUID at `/srv/nas`.

## 1. Identify the Seagate disk on Proxmox

Plug the disk into the Proxmox host and identify the stable USB passthrough
value:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
lsusb -t
```

Current Proxmox disk inventory:

- NAS target: `/dev/sdb`, `1.8T One Touch HDD`, serial `00000000NABLZBA2`
- Existing backup disk, do not use: `/dev/sda`, `1.8T Extreme 55DD`, serial
  `2604K2A01879`, mounted at `/mnt/pve-backup`

The current USB tree shows two mass-storage devices, so map `/dev/sdb` to its
actual USB path before setting OpenTofu variables:

```bash
udevadm info --query=property --name=/dev/sdb | grep -E '^(DEVPATH|ID_MODEL|ID_SERIAL|ID_VENDOR_ID|ID_MODEL_ID)='
```

Confirmed Seagate mapping:

```text
DEVPATH=.../usb3/3-3/3-3:1.0/.../block/sdb
ID_MODEL=One_Touch_HDD
ID_MODEL_ID=ab5a
ID_SERIAL=Seagate_One_Touch_HDD_00000000NABLZBA2-0:0
ID_VENDOR_ID=0bc2
```

Use USB path `3-3` for physical-port passthrough. The vendor/product fallback
would be `0bc2:ab5a`.

Prefer the physical port path when the disk will stay plugged into the same
host port. Vendor/product IDs also work, but they identify the model rather
than the physical port.

The OpenTofu Proxmox API token cannot attach real USB devices because Proxmox
requires root for that operation. Keep the VM in OpenTofu, but attach USB
manually after the VM exists.

Optional local note in `terraform.tfvars`:

```hcl
nas_usb_host = "3-3"
```

## 2. Create the VM

From the OpenTofu environment:

```bash
cd provisioning/opentofu/environments/homelab
tofu fmt
tofu validate
tofu plan
tofu apply
```

Expected VM settings:

- Name: `nas-vm`
- VM ID: `107`
- IP: `192.168.178.16/24`
- CPU/RAM: `1` vCPU, `2048` MB RAM
- Root disk: `20` GB

## 3. Attach the USB disk manually

On the Proxmox host, as root:

```bash
qm set 107 --usb0 host=3-3,usb3=1
```

Confirm the USB device is attached:

```bash
qm config 107
```

You should see:

```text
usb0: host=3-3,usb3=1
```

### If OpenTofu failed while setting USB

If an earlier `tofu apply` failed with:

```text
only root can set 'usb0' config for real devices
```

do not run a full environment destroy. The VM may already be in OpenTofu state.
After removing USB passthrough from OpenTofu config, run:

```bash
tofu state list | grep nas-vm
tofu plan
tofu apply
```

If Proxmox has VM `107` but OpenTofu does not list `module.nas-vm`, import it:

```bash
tofu import 'module.nas-vm.proxmox_virtual_environment_vm.this' '<proxmox-node-name>/107'
```

Only destroy the single partial VM if OpenTofu cannot reconcile it and you are
sure it contains no data:

```bash
tofu destroy -target='module.nas-vm.proxmox_virtual_environment_vm.this'
```

## 4. Bootstrap the VM

Run the baseline VM bootstrap:

```bash
cd provisioning/ansible
ansible-playbook playbooks/bootstrap.yml --limit nas-vm
```

## 5. Format the Seagate disk once

SSH into the VM and identify the passed-through disk:

```bash
ssh ansible@192.168.178.16
lsblk -f
```

Current VM disk layout:

- VM root disk: `/dev/sda`, mounted at `/`
- Seagate USB disk: `/dev/sdb`
- Seagate data partition to format: `/dev/sdb2`, currently `exfat`, label `NAS`

Carefully format `/dev/sdb2` as ext4. This destroys the existing exFAT data on
that partition.

```bash
sudo mkfs.ext4 -L seagate-nas /dev/sdb2
sudo blkid /dev/sdb2
```

Copy the UUID and set it in:

```text
provisioning/ansible/inventories/homelab/group_vars/nas_servers.yml
```

Example:

```yaml
nas_disk_uuid: "00000000-0000-0000-0000-000000000000"
```

## 6. Add Samba passwords with SOPS

Create or edit the encrypted NAS group vars file:

```bash
cd provisioning/ansible
sops inventories/homelab/group_vars/nas_servers.sops.yml
```

Add the Samba passwords:

```yaml
nas_samba_passwords:
  tmbackup: "replace-with-long-password"
  habackup: "replace-with-long-password"
  nasfiles: "replace-with-long-password"
```

The role requires at least 12 characters for each password.

## 7. Configure Samba

Run the NAS playbook:

```bash
ansible-playbook playbooks/nas.yml
```

The playbook installs Samba, mounts the disk at `/srv/nas`, creates these
directories, and exports them as private SMB shares:

- `/srv/nas/timemachine` as `TimeMachine`
- `/srv/nas/home-assistant-backups` as `HomeAssistantBackups`
- `/srv/nas/shared` as `Shared`

## 8. Verify

On the VM:

```bash
findmnt /srv/nas
lsblk -f
testparm -s
systemctl status smbd nmbd avahi-daemon
```

From macOS:

```text
smb://nasfiles@192.168.178.16/Shared
smb://nasfiles@192.168.178.16/TimeMachine
smb://nasfiles@192.168.178.16/HomeAssistantBackups
```

Use `nasfiles` from macOS when you want one login that can browse all shares.
The dedicated `tmbackup` and `habackup` users still exist for service-specific
access.

## macOS SMB credential gotcha

macOS tends to keep one SMB login session per server name/IP. If different
shares require different users, Finder may try to reuse the first login and
show a misleading error such as "The share does not exist on the server."

This NAS config allows `nasfiles` to access all three shares, which is the
least fussy option for Finder.

Disconnect all mounted shares from `192.168.178.16`, then connect directly with
the right user:

```text
smb://nasfiles@192.168.178.16/Shared
```

If Finder still reuses the wrong credential, remove the saved SMB password for
`192.168.178.16` or `nas-vm` from macOS Keychain Access and reconnect.

On the NAS VM, confirm the share exists and points at a real directory:

```bash
testparm -s
ls -ld /srv/nas/timemachine
pdbedit -L
```

## 9. Set up Time Machine on macOS

First confirm Finder can connect to the backup share:

```text
smb://nasfiles@192.168.178.16/TimeMachine
```

Then configure Time Machine:

1. Open **System Settings**.
2. Go to **General** -> **Time Machine**.
3. Click **Add Backup Disk...**.
4. Select `TimeMachine` on `nas-vm` or `192.168.178.16`.
5. Use **Registered User** credentials:
   - Username: `nasfiles`
   - Password: the `nasfiles` Samba password
6. Enable backup encryption when prompted.
7. Start the first backup from the Time Machine menu or wait for the automatic
   backup.

If `TimeMachine` does not appear in the disk list, connect to the share in
Finder first, then reopen Time Machine settings.

This share is currently uncapped, so Time Machine can eventually use most of the
free NAS disk. Add a Samba `fruit:time machine max size` setting later if you
want a hard limit.

## Notes

- Ansible never formats the Seagate disk. If `nas_disk_uuid` is empty, the disk
  is missing, or `/srv/nas` is not mounted as ext4, the role stops.
- If the disk is moved to another Proxmox USB port, rerun
  `qm set 107 --usb0 host=<new-port>,usb3=1` as root and update the optional
  `nas_usb_host` note.
- If you intentionally rotate a Samba password, set
  `nas_force_samba_password_update: true` for one playbook run, then set it
  back to `false`.
