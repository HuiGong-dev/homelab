# Application Monitoring Onboarding

## Goal

This document explains how applications are monitored on the homelab platform and what an application owner needs to do when deploying a new workload.

The platform provides default Kubernetes-level monitoring for all namespaces. Applications only need extra configuration when they expose custom application metrics.

## Monitoring Levels

### Level 1 — Platform Monitoring

All workloads are monitored automatically after deployment.

No application changes are required.

The platform collects standard Kubernetes metrics such as:

- Pod readiness
- Pod restarts
- Container CPU usage
- Container memory usage
- Deployment replica availability
- Workload availability
- Node scheduling status
- Persistent volume usage, where supported
- Basic network traffic

These metrics are collected through the Kubernetes monitoring stack, including Prometheus, kube-state-metrics, kubelet, and cAdvisor.

This level answers questions like:

- Is the workload running?
- Are the expected replicas available?
- Are Pods restarting?
- Is the workload using too much CPU or memory?
- Is the workload stuck in Pending or CrashLoopBackOff?
- Does the Service have ready endpoints?

## Level 2 — Application Metrics

Application-specific metrics are optional.

An application should expose metrics when the default Kubernetes metrics are not enough to understand its behavior.

Examples include:

- HTTP request count
- HTTP error rate
- Request latency
- Background job duration
- Queue length
- Import/export duration
- Business-specific counters
- Database or external dependency timing

Application metrics usually require the app to expose a `/metrics` endpoint in Prometheus format.

## Default Onboarding Flow

When a new app is deployed, the following monitoring is available automatically:

1. Deploy the application into Kubernetes.
2. Prometheus discovers Kubernetes workloads and collects platform-level metrics.
3. Grafana dashboards can show workload health, CPU, memory, restarts, availability, and related Kubernetes signals.
4. No custom metrics endpoint is required for this baseline monitoring.

The minimum requirement is that the app is deployed using standard Kubernetes resources such as:

- Deployment
- StatefulSet
- DaemonSet
- Service
- Ingress or IngressRoute, if the app is user-facing
- PersistentVolumeClaim, if the app needs storage

## Recommended Kubernetes Metadata

Applications should use consistent labels so dashboards and queries can group resources correctly.

Recommended labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: demo-app
    app.kubernetes.io/instance: demo-app
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: platform-demo
    app.kubernetes.io/managed-by: flux
```

These labels help with filtering in Grafana and make ownership clearer.

## Readiness and Liveness Probes

Every user-facing application should define readiness and liveness probes.

Example:

```yaml
readinessProbe:
  httpGet:
    path: /health/ready
    port: http
  initialDelaySeconds: 5
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /health/live
    port: http
  initialDelaySeconds: 15
  periodSeconds: 20
```

Readiness probes are especially important because Kubernetes only sends Service traffic to ready Pods.

A Pod can be running but not ready. In that case, it should not receive normal Service traffic.

## Optional: Exposing Application Metrics

If the app exposes Prometheus metrics, it should provide a `/metrics` endpoint.

Example:

```text
GET /metrics
```

The endpoint should return Prometheus-format metrics.

Example metrics:

```text
http_requests_total
http_request_duration_seconds
app_jobs_processed_total
app_queue_depth
```

Depending on the monitoring setup, the app may need a `ServiceMonitor`, `PodMonitor`, or scrape annotation.

Example ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-app
  namespace: demo-app
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: demo-app
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

## User-Facing Availability

Kubernetes workload health does not always mean the application is reachable by users.

A workload can be healthy while the user-facing route is broken because of DNS, Ingress, TLS, Traefik, or network issues.

For user-facing applications, blackbox monitoring should be added separately.

Example checks:

- `https://paperless.home.hgpe.dev`
- `https://grafana.home.hgpe.dev`
- `https://demo-app.home.hgpe.dev`

This answers the question:

> Can a real client reach the application?

## Monitoring Responsibilities

The platform provides:

- Prometheus scraping
- Kubernetes metrics collection
- Grafana dashboards
- Default workload health visibility
- Optional blackbox probing
- Alerting rules for common platform-level failures

The application owner provides:

- Correct Kubernetes labels
- Readiness and liveness probes
- Resource requests and limits where appropriate
- Optional `/metrics` endpoint for application-specific metrics
- Optional ServiceMonitor or PodMonitor if required

## Minimal App Monitoring Checklist

For every new app:

- [ ] App is deployed in its own namespace
- [ ] Workload has standard Kubernetes labels
- [ ] Service selector matches Pod labels correctly
- [ ] Readiness probe is configured
- [ ] Liveness probe is configured where useful
- [ ] Resource requests are configured
- [ ] Ingress or IngressRoute is configured if user-facing
- [ ] Grafana workload dashboard shows the app
- [ ] Blackbox probe is configured if user-facing
- [ ] Custom metrics are added only if the app needs application-level observability

## Summary

By default, applications receive Kubernetes-level monitoring automatically.

This is enough to understand whether a workload is running, ready, restarting, overusing resources, or unavailable.

For deeper application behavior, the app should expose custom Prometheus metrics and optionally provide a ServiceMonitor or PodMonitor.

The platform baseline works out-of-the-box. Application-specific observability is opt-in.
