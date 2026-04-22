#!/usr/bin/env bash
set -euo pipefail

token_file="${1:-./spacelift.config}"
private_key_file="${2:-./spacelift.key}"
kubeconfig_directory="${3:-$HOME/.kube-spacelift}"
container_name="${4:-spacelift-worker}"
worker_network="${5:-kind}"

spacelift_token="$(tr -d '\r\n' < "$token_file")"
spacelift_private_key="$(podman run --rm -v "$PWD:/w" -w /w alpine base64 -w0 "$private_key_file")"
podman_socket="$(podman info --format '{{.Host.RemoteSocket.Path}}' | sed 's#^unix://##')"
extra_mounts="${kubeconfig_directory}:/home/spacelift/.kube"

podman machine ssh 'sudo mkdir -p /opt/spacelift && sudo chown -R $(id -u):$(id -g) /opt/spacelift' >/dev/null
podman rm -f "$container_name" >/dev/null 2>&1 || true

podman run -d \
  --name "$container_name" \
  --network "$worker_network" \
  -e SPACELIFT_TOKEN="$spacelift_token" \
  -e SPACELIFT_POOL_PRIVATE_KEY="$spacelift_private_key" \
  -e SPACELIFT_WORKER_NETWORK="$worker_network" \
  -e SPACELIFT_WORKER_EXTRA_MOUNTS="$extra_mounts" \
  -e SPACELIFT_WORKER_RO_EXTRA_MOUNTS="$extra_mounts" \
  -e SPACELIFT_WORKER_WO_EXTRA_MOUNTS="$extra_mounts" \
  -v /opt/spacelift:/opt/spacelift \
  -v "${kubeconfig_directory}:/home/spacelift/.kube:ro" \
  -v "${kubeconfig_directory}:${kubeconfig_directory}:ro" \
  -v "${podman_socket}:/var/run/docker.sock" \
  public.ecr.aws/spacelift/launcher:latest

sleep 5
podman ps --filter "name=$container_name" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
podman logs --tail 30 "$container_name"
