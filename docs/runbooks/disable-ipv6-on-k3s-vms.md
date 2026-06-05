# Keep k3s nodes IPv4-only

This runbook keeps the k3s nodes effectively IPv4-only when IPv6 addresses are
assigned by the guest OS but are not actually routable on the LAN.

The `disable_ipv6` Ansible role writes `/etc/sysctl.d/99-disable-ipv6.conf` and
applies it immediately with `sysctl -p`. It is included only in the k3s server
and k3s agent playbooks, so other homelab VMs keep their existing IPv6 behavior.

Host-level IPv6 disablement is not enough by itself. Kubernetes workloads can
still receive AAAA DNS answers and attempt IPv6 paths, so AdGuard Home also
handles this at the DNS layer. AAAA queries from the k3s nodes are answered with
`NOERROR` and no IPv6 records. Other VMs and LAN devices can still receive AAAA
records and use IPv6 normally.

## Apply

From `provisioning/ansible`:

```sh
ansible-playbook playbooks/k3s.yml
ansible-playbook playbooks/k3s-agent.yml
```

## Verify host networking

```sh
ansible k3s_servers:k3s_agents -m command -a "sysctl net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 net.ipv6.conf.lo.disable_ipv6"
ansible k3s_servers:k3s_agents -m command -a "ip -6 route"
```

The sysctl values should all be `1`, and `ip -6 route` should not show usable
IPv6 routes.

## Verify Kubernetes

On the k3s server:

```sh
/usr/local/bin/k3s kubectl get nodes -o wide
/usr/local/bin/k3s kubectl -n system-upgrade rollout status deployment/system-upgrade-controller --timeout=300s
```

If an already-running System Upgrade Controller pod keeps stale network state,
restart the deployment after applying the playbooks.

## Verify k3s DNS behavior

From a k3s node, AAAA lookups through AdGuard Home should return `NOERROR` with
no IPv6 answer. A records should still resolve normally.
