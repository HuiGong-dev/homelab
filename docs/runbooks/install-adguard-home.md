# Install AdGuard Home

This guide installs AdGuard Home directly on a Linux VM using the official release archive and systemd service.

Assumption:

- AdGuard Home VM IP: `192.168.178.12`
- AdGuard Home install path: `/opt/AdGuardHome`
- DNS port: `53`
- Initial setup UI port: `3000`

---

## 1. Download and install AdGuard Home

```sh
cd /opt

sudo curl -L -o adguard.tar.gz \
  https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_amd64.tar.gz

sudo tar -xzf adguard.tar.gz

cd /opt/AdGuardHome

sudo ./AdGuardHome -s install
```

---

## 2. Check service status

```sh
sudo systemctl status AdGuardHome
```

If it is not running:

```sh
sudo systemctl start AdGuardHome
sudo systemctl enable AdGuardHome
```

---

## 3. Open the initial setup page

Open in browser:

```text
http://192.168.178.12:3000
```

During the setup wizard, use something like:

```text
DNS listen interface: 192.168.178.12
DNS port: 53

Web interface: 0.0.0.0 or 192.168.178.12
Web port: 80 or 3000
```

For my homelab setup, `192.168.178.12:80` is fine if Traefik routes to AdGuard Home later.

---

## 4. Check whether port 53 is already in use

DNS uses both UDP and TCP, so check both:

```sh
sudo ss -tulpen | grep ':53'
```

Alternative:

```sh
sudo lsof -i :53
```

If nothing else is using port `53`, AdGuard Home should be able to bind to it.

---

## 5. Fix port 53 conflict with systemd-resolved

On many Linux systems, `systemd-resolved` listens on local DNS port `53`, usually on `127.0.0.53`.

If `systemd-resolved` blocks AdGuard Home from using port `53`, disable only the DNS stub listener instead of disabling `systemd-resolved` completely.

Create a config file:

```sh
sudo mkdir -p /etc/systemd/resolved.conf.d

cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/adguardhome.conf
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
```

Replace `/etc/resolv.conf` with the systemd-resolved managed file:

```sh
sudo mv /etc/resolv.conf /etc/resolv.conf.backup
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
```

Restart `systemd-resolved` and AdGuard Home:

```sh
sudo systemctl reload-or-restart systemd-resolved
sudo systemctl restart AdGuardHome
```

Check again:

```sh
sudo ss -tulpen | grep ':53'
```

You should now see AdGuard Home listening on port `53`.

---

## 6. Test DNS locally on the AdGuard Home VM

Test using localhost:

```sh
dig google.com @127.0.0.1
```

Test using the VM LAN IP:

```sh
dig google.com @192.168.178.12
```

If both work, AdGuard Home is resolving DNS correctly.

---

## 7. Test DNS from another machine

From your laptop or another machine in the LAN:

```sh
dig google.com @192.168.178.12
```

For homelab local DNS:

```sh
dig pve.home.hgpe.dev @192.168.178.12
dig adguard.home.hgpe.dev @192.168.178.12
dig traefik.home.hgpe.dev @192.168.178.12
```

---

## 8. Configure the router DHCP DNS server

In the FRITZ!Box DHCP settings, set the local DNS server to:

```text
192.168.178.12
```

This makes LAN clients receive AdGuard Home as their DNS server automatically.

After changing DHCP DNS settings, reconnect clients or renew DHCP leases.

On macOS:

```sh
sudo ipconfig set en0 DHCP
```

Or simply disconnect and reconnect Wi-Fi.

---

## 9. Useful service commands

Check status:

```sh
sudo systemctl status AdGuardHome
```

Restart:

```sh
sudo systemctl restart AdGuardHome
```

Stop:

```sh
sudo systemctl stop AdGuardHome
```

Start:

```sh
sudo systemctl start AdGuardHome
```

Enable auto-start on boot:

```sh
sudo systemctl enable AdGuardHome
```

View logs:

```sh
journalctl -u AdGuardHome -f
```

---

## 10. Optional cleanup

Remove the downloaded archive:

```sh
cd /opt
sudo rm -f adguard.tar.gz
```

---

## Notes

Avoid this unless you really want the brute-force approach:

```sh
sudo systemctl disable --now systemd-resolved
sudo rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

It works on a dedicated DNS VM, but it is less clean.

The better approach is:

```text
Keep systemd-resolved installed
Disable only DNSStubListener
Let AdGuard Home own port 53
Use 127.0.0.1 as the VM's DNS resolver
```
