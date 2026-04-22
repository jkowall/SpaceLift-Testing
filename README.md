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

### Portable Podman setup

For portability across Windows and macOS, avoid kubeconfigs that point at a
host-local API URL like `https://127.0.0.1:<port>` or at a hard-coded Podman
container IP. Instead:

1. Put the Spacelift launcher and run containers on kind's Podman network.
2. Use kind's stable control-plane container name as the Kubernetes API host:
   `https://kind-cluster-control-plane:6443`.
3. Upload the generated kubeconfig as a Spacelift mounted file at `kube/config`.
4. Set `TF_VAR_kubeconfig_path=/mnt/workspace/kube/config` on the stack.

Windows PowerShell:

```powershell
.\scripts\prepare-spacelift-kubeconfig.ps1
.\scripts\start-spacelift-worker.ps1
```

macOS/Linux shell with Podman:

```bash
./scripts/prepare-spacelift-kubeconfig.sh
./scripts/start-spacelift-worker.sh
```

To make this repeatable on the same machine, copy the local worker example config
and keep it next to your ignored credentials:

```powershell
Copy-Item .\local.spacelift-worker.example.psd1 .\local.spacelift-worker.psd1
```

Then restore the kubeconfig and worker with one command:

```powershell
.\scripts\restore-spacelift-worker.ps1
```

`local.spacelift-worker.psd1` is gitignored because it can point at local secret
files and machine-specific paths.

Both scripts assume the README defaults:

| Setting | Default |
|---|---|
| kind cluster name | `kind-cluster` |
| kubeconfig context | `kind-kind-cluster` |
| Podman network | `kind` |
| Spacelift mounted file path | `kube/config` |
| Terraform variable | `TF_VAR_kubeconfig_path=/mnt/workspace/kube/config` |

If you use another kind cluster name, pass the context and cluster name:

```powershell
.\scripts\prepare-spacelift-kubeconfig.ps1 `
  -Context kind-my-cluster `
  -ClusterName my-cluster
```

```bash
./scripts/prepare-spacelift-kubeconfig.sh kind-my-cluster my-cluster
```

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

Don't mount your entire `~/.kube/config` — it may contain unrelated contexts.
Generate a minified copy with just the kind context and a container-reachable
API server name:

```powershell
.\scripts\prepare-spacelift-kubeconfig.ps1
```

On macOS/Linux with Podman:

```bash
./scripts/prepare-spacelift-kubeconfig.sh
```

Upload the generated kubeconfig to the Spacelift stack as a secret mounted file
at `kube/config`, and set `TF_VAR_kubeconfig_path=/mnt/workspace/kube/config`.

### 2.5 — Launch the Private Worker on Podman

The worker needs two things:

1. **Network access to the kind API server.** Run the launcher and spawned run containers on kind's Podman network, where `kind-cluster-control-plane:6443` is reachable.
2. **A Docker-compatible socket** so the launcher can spawn run containers. Spacelift's launcher was written for Docker; Podman exposes a compatible API socket that works as a drop-in replacement once mounted at `/var/run/docker.sock`.

First, find Podman's socket path (usually `/run/user/1000/podman/podman.sock` rootless or `/run/podman/podman.sock` rootful):

```powershell
podman info --format '{{.Host.RemoteSocket.Path}}'

# If it says "not active", enable it:
podman machine ssh 'systemctl --user enable --now podman.socket'
```

Start the worker:

```powershell
.\scripts\start-spacelift-worker.ps1
```

On macOS/Linux with Podman:

```bash
./scripts/start-spacelift-worker.sh
```

> **Common errors and fixes:**
> - `could not unmarshal iot config` — token got base64-encoded twice. Re-run the `Get-Content` line above (don't pipe `spacelift.config` through `base64`).
> - `couldn't ping docker daemon ... /var/run/docker.sock` — Podman's socket isn't mounted or isn't running. Check `podman info --format '{{.Host.RemoteSocket.Path}}'` and confirm the `-v <sock>:/var/run/docker.sock` mount path matches. Enable the socket with `podman machine ssh 'systemctl --user enable --now podman.socket'` if needed.

Verify the worker shows up in **Spacelift UI → Settings → Worker Pools → local-k8s → Workers** as `Online`.

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
created in the cluster and Terraform prints local access commands as outputs.
For kind on Podman, use `kubectl port-forward`; kind does not automatically
publish Kubernetes NodePorts to your Windows or macOS host.

Start both HotROD and Jaeger port-forwards:

```powershell
.\scripts\open-observability.ps1
```

On macOS/Linux:

```bash
./scripts/open-observability.sh
```

### Jaeger UI

```
http://localhost:16686
```

### HotROD UI

```
http://localhost:8080
```

---

## 4 — Generating Traces with HotROD

1. Open **http://localhost:8080** in a browser.
2. You will see four coloured buttons, one per simulated customer:
   - **Rachel's Floral Designs**
   - **Rachel's Floral Designs (Fancy)**
   - **Amazing Coffee Roasters**
   - **Amazing Coffee Roasters (Uber)**
3. Click any button to dispatch a car. Each click triggers a chain of HTTP and
   gRPC calls across several micro-services, all instrumented with OpenTelemetry.
4. Switch to the **Jaeger UI** at **http://localhost:16686**, select the
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

### Host → cluster access

| Local URL | Command | Purpose |
|-----------|---------|---------|
| `http://localhost:16686` | `kubectl -n observability port-forward svc/jaeger-ui 16686:16686` | Jaeger web UI |
| `http://localhost:8080` | `kubectl -n observability port-forward svc/hotrod 8080:8080` | HotROD web UI / dispatch buttons |

### Kubernetes API (Spacelift worker → cluster)

| Port | Purpose |
|------|---------|
| 6443 (or 443) | kubectl / provider authentication |

The services still use NodePort internally, but the documented local access path
is port-forwarding because it works consistently across Podman on Windows and
macOS.

---

## 6 — Teardown

```bash
tofu destroy
```

This removes the namespace, deployments, and services. The `observability`
namespace and all resources inside it will be deleted.

