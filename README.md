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
| Local Kubernetes cluster | `kind` on Podman is the walkthrough path below; k3d, minikube, or Docker Desktop also work |
| OpenTofu ≥ 1.6 | `brew install opentofu` or see https://opentofu.org/docs/intro/install |
| kubectl | Configured with a valid context for the cluster |
| Container runtime | Podman (walkthrough) or Docker — used to run the Spacelift Private Worker |
| openssl | Ships with Git for Windows (`C:\Program Files\Git\usr\bin\openssl.exe`), WSL, or any Linux/macOS host |
| Spacelift account | Free tier works; you need a **Private Worker Pool** |

> **Windows users:** the walkthrough assumes Podman Desktop with WSL2 backend and PowerShell. Paths and base64 flags differ on macOS/Linux — notes inline where they do.

---

## Credentials & files — what lives where

This workflow produces several credential files. **None of them should be committed.** A `.gitignore` in the repo root excludes `*.key`, `*.csr`, `*.pem`, `spacelift.config`, and a `credentials/` subdirectory. Either:

- Keep them in the repo root (gitignore catches them), or
- Put them in a `credentials/` subdir for tidiness (also gitignored):

```powershell
mkdir credentials -ErrorAction SilentlyContinue
cd credentials
# …run the openssl + base64 commands from here
```

---

## 1 — Local Deployment (without Spacelift)

```bash
tofu init
tofu plan
tofu apply
```

Target a specific kubeconfig context:

```bash
tofu apply \
  -var="kubeconfig_path=$HOME/.kube/config" \
  -var="kubeconfig_context=kind-kind-cluster"
```

---

## 2 — Spacelift Deployment (via Private Worker on Podman + kind)

### 2.1 — Create a kind cluster on Podman

```powershell
# Start the Podman VM (once per reboot)
podman machine start

# Tell kind to use Podman, then create a cluster
$env:KIND_EXPERIMENTAL_PROVIDER = "podman"
kind create cluster --name kind-cluster

# Verify
kubectl config get-contexts       # * should be on kind-kind-cluster
kubectl get nodes                 # one node, Ready
```

kind writes a context named `kind-kind-cluster` into `~/.kube/config` with `server: https://127.0.0.1:<random-port>`. That port is published from the kind container into the Podman VM's loopback.

### 2.2 — Generate a private key and CSR for the worker

Spacelift does **not** generate keys for you. You generate the private key locally, upload only the CSR, and Spacelift signs it.

Using the openssl that ships with Git for Windows:

```powershell
# Run from the repo root (or from a credentials/ subdir — both are gitignored)
$openssl = "C:\Program Files\Git\usr\bin\openssl.exe"
& $openssl genrsa -out spacelift.key 4096
& $openssl req -new -key spacelift.key -out spacelift.csr -subj "/CN=spacelift-worker"
```

Alternative — ephemeral Podman container (no host openssl needed):

```powershell
podman run --rm -v ${PWD}:/work -w /work alpine/openssl genrsa -out spacelift.key 4096
podman run --rm -v ${PWD}:/work -w /work alpine/openssl req -new -key spacelift.key -out spacelift.csr -subj "/CN=spacelift-worker"
```

You now have:
- `spacelift.key` — **private key**, never upload or commit
- `spacelift.csr` — certificate signing request, safe to upload

### 2.3 — Create the Worker Pool in Spacelift

1. In the Spacelift UI: **Settings → Worker Pools → Create Worker Pool**.
2. Name it (e.g. `local-k8s`).
3. **Upload `spacelift.csr`** using the file picker. The UI does not accept pasted text.
4. Click **Create**. Spacelift signs the CSR and downloads a `<pool-name>.config` file — this is the base64-encoded config blob consumed by the launcher as `SPACELIFT_TOKEN`.
5. Note the **Worker Pool ID** from the pool's detail page — you'll need it when creating the stack.

Save the `.config` file next to your key (or in `credentials/`). Rename to `spacelift.config` for convenience if you like:

```powershell
# If it downloaded to Downloads as e.g. local-k8s.config
Move-Item $env:USERPROFILE\Downloads\local-k8s.config .\spacelift.config
```

### 2.4 — Prepare a dedicated kubeconfig for the worker

Don't mount your entire `~/.kube/config` — it may contain unrelated contexts. Export a minified copy with just the kind context:

```powershell
mkdir $env:USERPROFILE\.kube-spacelift -ErrorAction SilentlyContinue
kubectl config view --minify --raw --context=kind-kind-cluster | `
  Out-File -Encoding ascii $env:USERPROFILE\.kube-spacelift\config
```

### 2.5 — Launch the Private Worker on Podman

The worker needs network access to the kind API server. Because kind on Podman publishes the API to the Podman VM's loopback (`127.0.0.1:<port>`), running the worker with `--network host` on Podman makes the same port reachable inside the worker container.

```powershell
# Base64-encode both credential files (GNU base64 inside a container — works regardless of host OS)
$SPACELIFT_TOKEN = podman run --rm -v ${PWD}:/w -w /w alpine base64 -w0 spacelift.config
$SPACELIFT_POOL_PRIVATE_KEY = podman run --rm -v ${PWD}:/w -w /w alpine base64 -w0 spacelift.key

podman run --rm -d `
  --name spacelift-worker `
  --network host `
  -e SPACELIFT_TOKEN="$SPACELIFT_TOKEN" `
  -e SPACELIFT_POOL_PRIVATE_KEY="$SPACELIFT_POOL_PRIVATE_KEY" `
  -v "$env:USERPROFILE\.kube-spacelift:/root/.kube:ro" `
  public.ecr.aws/spacelift/launcher:latest

# Confirm it started
podman logs -f spacelift-worker
```

Verify the worker shows up in **Spacelift UI → Settings → Worker Pools → local-k8s → Workers** as `Online`.

> **Alternative networking (if `--network host` gives trouble):** attach the worker to kind's Podman network and edit the kubeconfig's `server:` field to point at `kind-cluster-control-plane:6443`:
>
> ```powershell
> podman network ls                                   # confirm 'kind' network exists
> # then add: --network kind   to the podman run above
> # and edit $env:USERPROFILE\.kube-spacelift\config to set:
> #   server: https://kind-cluster-control-plane:6443
> ```

### 2.6 — Create the stack from the blueprint

1. In the Spacelift UI, go to **Blueprints**, click **Use blueprint**, and select the `observability-sandbox` blueprint that Spacelift detected from `spacelift.yaml`.
2. Fill in the inputs:
   - **Stack name** — e.g. `observability-sandbox`
   - **Private Worker Pool ID** — from step 2.3
   - **Kubeconfig path on the worker** — `/root/.kube/config` (default)
   - **VCS namespace / repository / branch** — your GitHub org and repo hosting this code
3. Click **Create stack** → **Trigger run**.

> Tracked runs on `main` require manual confirmation in the UI (`auto_deploy: false` in `spacelift.yaml`). If you want unattended runs in a personal sandbox, flip that field or attach an APPROVAL policy that auto-approves `PROPOSED` runs only — never auto-approve `TRACKED` runs without deliberate scoping.

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

