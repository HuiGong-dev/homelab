# Disable IPv6 on k3s VMs

This runbook keeps the k3s nodes IPv4-only when IPv6 addresses are assigned by
the guest OS but are not actually routable on the LAN.

The `disable_ipv6` Ansible role writes `/etc/sysctl.d/99-disable-ipv6.conf` and
applies it immediately with `sysctl -p`. It is included only in the k3s server
and k3s agent playbooks, so other homelab VMs keep their existing IPv6 behavior.

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
