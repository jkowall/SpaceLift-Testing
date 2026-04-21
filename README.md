# Observability Sandbox — Spacelift + OpenTofu + Kubernetes

This repository provisions a complete observability sandbox on a **local Kubernetes cluster** using [OpenTofu](https://opentofu.org/) and [Spacelift](https://spacelift.io/).

The sandbox consists of:
- **Jaeger all-in-one** — trace collector, store, and UI
- **HotROD** — demo ride-hailing app that emits realistic distributed traces

---

## Repository Layout

```
.
├── providers.tf     # Kubernetes provider + input variables
├── namespace.tf     # observability namespace
├── jaeger.tf        # Jaeger deployment, ClusterIP OTLP service, NodePort UI service
├── hotrod.tf        # HotROD deployment + NodePort service (wired to Jaeger)
└── spacelift.yaml   # Spacelift Blueprint (OpenTofu runner + Private Worker Pool)
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Local Kubernetes cluster | kind, k3d, minikube, Docker Desktop, or any kubeadm cluster |
| OpenTofu ≥ 1.6 | `brew install opentofu` or see https://opentofu.org/docs/intro/install |
| kubectl | Configured with a valid context for the cluster |
| Docker | Required to run the Spacelift Private Worker |
| Spacelift account | Free tier works; you need a **Private Worker Pool** token |

---

## 1 — Local Deployment (without Spacelift)

```bash
# Initialise providers
tofu init

# Preview the changes
tofu plan

# Apply
tofu apply
```

To target a specific cluster context:

```bash
tofu apply \
  -var="kubeconfig_path=$HOME/.kube/config" \
  -var="kubeconfig_context=docker-desktop"
```

---

## 2 — Spacelift Deployment (via Private Worker)

### 2.1 — Create a Private Worker Pool in Spacelift

1. In the Spacelift UI go to **Settings → Worker Pools → Create Worker Pool**.
2. Give it a name (e.g. `local-k8s`), then click **Generate**.
3. Copy the **Worker Pool ID** and the **Private Key** — you will need both.

### 2.2 — Launch the Spacelift Private Worker on your local machine

Run the official worker container, mounting your kubeconfig so it can reach the cluster:

```bash
docker run --rm -d \
  --name spacelift-worker \
  --network host \
  -e "SPACELIFT_TOKEN=<YOUR_WORKER_PRIVATE_KEY>" \
  -e "SPACELIFT_POOL_ID=<YOUR_WORKER_POOL_ID>" \
  -v "$HOME/.kube:/root/.kube:ro" \
  public.ecr.aws/spacelift/launcher:latest
```

> **Note:** `--network host` lets the container reach the Kubernetes API server on
> `127.0.0.1` / `localhost`. If your cluster API is on a different address, remove
> `--network host` and ensure the kubeconfig `server:` field uses an IP/hostname
> reachable from inside the container.

Verify the worker is connected in **Spacelift UI → Settings → Worker Pools → local-k8s → Workers**.

### 2.3 — Create the stack from the blueprint

1. In the Spacelift UI go to **Blueprints**, click **Use blueprint**, and select the
   `observability-sandbox` blueprint that Spacelift detected from `spacelift.yaml`.
2. Fill in the inputs:
   - **Private Worker Pool ID** — the pool ID from step 2.1
   - **Kubeconfig path on the worker** — `/root/.kube/config` (default)
3. Click **Create stack** → **Trigger run**.

The stack will run on your local worker and deploy the sandbox into the cluster.

---

## 3 — Accessing the UIs

After deployment (`tofu apply` or the Spacelift run completes), the services are
exposed as **NodePort** services.

### Jaeger UI

```
http://<NODE_IP>:30686
```

For single-node clusters (kind, minikube, Docker Desktop) `<NODE_IP>` is typically
`localhost` or `127.0.0.1`:

```
http://localhost:30686
```

### HotROD UI

```
http://localhost:30808
```

---

## 4 — Generating Traces with HotROD

1. Open **http://localhost:30808** in a browser.
2. You will see four coloured buttons, one per simulated customer:
   - **Rachel's Floral Designs**
   - **Rachel's Floral Designs (Fancy)**
   - **Amazing Coffee Roasters**
   - **Amazing Coffee Roasters (Uber)**
3. Click any button to dispatch a car. Each click triggers a chain of HTTP and
   gRPC calls across several micro-services, all instrumented with OpenTelemetry.
4. Switch to the **Jaeger UI** at **http://localhost:30686**, select the
   `frontend` service from the *Service* dropdown, and click **Find Traces** to
   see the generated spans.

---

## 5 — Port Reference Checklist

The following ports must be reachable **within the cluster** (pod-to-pod via
ClusterIP) and/or from your local machine (via NodePort):

### In-cluster (pod → service)

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 4317 | TCP (gRPC) | `jaeger-otlp` (ClusterIP) | OTLP gRPC trace ingest |
| 4318 | TCP (HTTP) | `jaeger-otlp` (ClusterIP) | OTLP HTTP trace ingest |

HotROD uses `jaeger-otlp.observability.svc.cluster.local:4318` (OTLP/HTTP) to
send traces to Jaeger.

### Host → cluster (NodePort)

| NodePort | Target Port | Service | Purpose |
|----------|-------------|---------|---------|
| **30686** | 16686 | `jaeger-ui` (NodePort) | Jaeger web UI |
| **30808** | 8080 | `hotrod` (NodePort) | HotROD web UI / dispatch buttons |

### Kubernetes API (Spacelift worker → cluster)

| Port | Purpose |
|------|---------|
| 6443 (or 443) | kubectl / provider authentication |

> Ensure your local firewall or security group rules allow Docker to reach these
> NodePort ranges (`30000–32767`) on the host network interface.

---

## 6 — Teardown

```bash
tofu destroy
```

This removes the namespace, deployments, and services. The `observability`
namespace and all resources inside it will be deleted.

