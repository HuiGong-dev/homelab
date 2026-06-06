# ADR-001: Manage Off-Cluster Service Routing, TLS, and DNS Declaratively via Kubernetes Resources

## Status

Accepted

The decision has been implemented and validated using Flux, cert-manager, Traefik `IngressRoute`, ExternalDNS, and AdGuard Home.

## Date

2026-06-05

## Context

The homelab cluster exposes both in-cluster applications and off-cluster services through Traefik.

Examples of off-cluster services include:

- Proxmox VE
- AdGuard Home
- Home Assistant
- Other services running outside the Kubernetes cluster but reachable from the cluster network

Previously, Traefik's file provider was used or considered for routing traffic to off-cluster services. Traefik ACME was also used for certificate generation via DNS-01 challenge.

The platform is now moving toward a more declarative GitOps-based model using:

- Flux for reconciliation
- Traefik as the ingress controller / reverse proxy
- cert-manager for certificate management
- ExternalDNS for DNS record automation
- Cloudflare DNS-01 for certificate validation
- AdGuard Home as the internal DNS target through ExternalDNS webhook

Both cert-manager and ExternalDNS support Traefik `IngressRoute` resources. This makes it possible to represent off-cluster services as Kubernetes resources instead of managing them through Traefik file provider configuration.

The goal is to keep routing, TLS, and DNS configuration fully declarative and managed through GitOps.

## Decision

Off-cluster services will be represented inside Kubernetes using `Service` and `EndpointSlice` resources, and exposed through Traefik `IngressRoute`.

TLS certificates will be managed by cert-manager, not by Traefik ACME.

DNS records will be managed by ExternalDNS based on annotations on the `IngressRoute` resources.

Traefik will only be responsible for routing traffic and consuming Kubernetes TLS secrets.

The preferred pattern is:

```text
External service
  ↓
Kubernetes Service + EndpointSlice
  ↓
Traefik IngressRoute
  ↓
cert-manager-managed TLS Secret
  ↓
ExternalDNS-managed DNS record
```

The `Service` should use the default `ClusterIP` type with an explicit
`EndpointSlice`, rather than `ExternalName`, when the backend is a known LAN IP.
This gives Traefik a normal Kubernetes Service backed by explicit endpoints.
`ExternalName` should be reserved for external services that already have a
stable DNS name managed outside the cluster, because it acts as a DNS alias
rather than as a Service with Kubernetes-managed endpoint data.

For example, an off-cluster Proxmox service can be modeled as:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pve
  namespace: networking
spec:
  ports:
    - name: https
      port: 8006
      targetPort: 8006
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: pve
  namespace: networking
  labels:
    kubernetes.io/service-name: pve
addressType: IPv4
ports:
  - name: https
    protocol: TCP
    port: 8006
endpoints:
  - addresses:
      - 192.168.178.10
```

The service can then be exposed through Traefik:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: pve
  namespace: networking
  annotations:
    external-dns.alpha.kubernetes.io/hostname: pve.home.hgpe.dev
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`pve.home.hgpe.dev`)
      kind: Rule
      services:
        - name: pve
          port: 8006
          scheme: https
  tls:
    secretName: home-hgpe-dev-wildcard-tls
```

The wildcard certificate for `*.home.hgpe.dev` will be issued and renewed by cert-manager using a Cloudflare DNS-01 `ClusterIssuer`.

## Alternatives Considered

### 1. Continue using Traefik file provider for off-cluster services

Traefik file provider can route traffic to external services and is simple for small static setups.

However, it has several downsides:

- It is outside the Kubernetes object model.
- cert-manager does not automatically manage certificates for file-provider routes.
- File-provider TLS configuration usually requires mounting certificate files into the Traefik pod.
- ExternalDNS cannot naturally infer desired DNS records from file-provider configuration.
- Routing configuration becomes split between Kubernetes resources and Traefik-specific files.
- GitOps reconciliation and drift detection are less consistent.

This option was rejected because it creates unnecessary operational split-brain.

### 2. Keep Traefik ACME for file-provider services and use cert-manager for Kubernetes resources

This would allow Traefik to continue managing certificates for file-provider routes while cert-manager handles Kubernetes-managed routes.

However, this creates two independent certificate management systems:

- Traefik ACME
- cert-manager

This increases operational complexity and makes certificate ownership less clear.

This option was rejected because certificate management should have a single owner.

### 3. Use standard Kubernetes Ingress resources

Standard `Ingress` resources are portable and work well for simple HTTP routing.

However, off-cluster services often need Traefik-specific settings, such as:

- backend scheme `https`
- custom `ServersTransport`
- middleware configuration
- more explicit Traefik routing behavior

Using standard `Ingress` for these cases would require Traefik-specific annotations, which are less readable and harder to maintain than `IngressRoute`.

This option remains acceptable for simple in-cluster applications, but is not the preferred pattern for off-cluster services.

### 4. Use Gateway API

Gateway API provides a modern and more expressive Kubernetes-native routing model.

It is a good future direction, especially for platform-style separation between infrastructure-owned gateways and application-owned routes.

However, for the current homelab setup, Gateway API introduces additional concepts and configuration overhead:

- `GatewayClass`
- `Gateway`
- `HTTPRoute`
- route attachment rules
- listener TLS ownership
- possible `ReferenceGrant` usage

This option may be revisited later as a dedicated learning or portfolio enhancement.

For the current phase, `IngressRoute` provides the best balance between clarity, functionality, and operational simplicity.

## Consequences

### Positive

- Routing, TLS, and DNS are fully declarative.
- Off-cluster services are managed through the same GitOps workflow as in-cluster services.
- cert-manager becomes the single owner of certificate lifecycle management.
- ExternalDNS can automatically create and update DNS records.
- Traefik configuration becomes simpler because Traefik only handles routing.
- No need to maintain separate Traefik file-provider dynamic configuration for off-cluster services.
- No need to keep Traefik ACME once cert-manager is fully adopted.
- The setup is easier to document, review, and reproduce.
- This pattern better represents a real platform-engineering workflow.

### Negative

- Off-cluster services must be modeled as Kubernetes resources.
- `Service` and `EndpointSlice` resources add some YAML overhead.
- The setup depends on Traefik CRDs.
- `IngressRoute` is Traefik-specific and less portable than standard `Ingress` or Gateway API.
- If the external service IP changes, the corresponding `EndpointSlice` must be updated.

## Operational Notes

Traefik ACME should be disabled after migration to cert-manager is complete.

The wildcard certificate should be created once and reused across internal services where appropriate.

ExternalDNS annotations should be added to `IngressRoute` resources to ensure DNS records are created automatically.

For services with HTTPS backends and self-signed certificates, a Traefik `ServersTransport` may be needed.

Example:

```yaml
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: pve-transport
  namespace: networking
spec:
  insecureSkipVerify: true
```

Then reference it from the `IngressRoute` service:

```yaml
services:
  - name: pve
    port: 8006
    scheme: https
    serversTransport: pve-transport
```

`insecureSkipVerify` is acceptable for internal homelab services when the network is trusted and the risk is understood, but using a trusted internal CA would be cleaner in a stricter environment.

## Final Decision Summary

Use Kubernetes-native resources to represent off-cluster services.

Use:

- `Service` + `EndpointSlice` for external backends
- Traefik `IngressRoute` for routing
- cert-manager for TLS certificates
- ExternalDNS for DNS records
- Flux for GitOps reconciliation

Do not keep Traefik ACME as a second certificate management system after cert-manager migration.

Do not use Traefik file provider for new off-cluster service routing unless there is a specific exception.

## Implementation Notes

This decision has been implemented with:

- cert-manager issuing a wildcard certificate for `*.home.hgpe.dev`
- the wildcard TLS Secret stored in the `traefik` namespace
- Traefik consuming the wildcard certificate through the default `TLSStore`
- ExternalDNS creating DNS records from `Ingress` and `IngressRoute` resources
- off-cluster services modeled with `Service` and `EndpointSlice`
- all resources reconciled through Flux
