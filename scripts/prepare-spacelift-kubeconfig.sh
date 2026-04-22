#!/usr/bin/env bash
set -euo pipefail

context="${1:-kind-kind-cluster}"
cluster_name="${2:-kind-cluster}"
output_path="${3:-$HOME/.kube-spacelift/config}"
server="https://${cluster_name}-control-plane:6443"

mkdir -p "$(dirname "$output_path")"

kubectl config view --minify --raw --context="$context" \
  | sed -E "s#server: https://[^[:space:]]+#server: ${server}#" \
  > "$output_path"

echo "Wrote kubeconfig for Spacelift runs:"
echo "  $output_path"
echo "Server:"
echo "  $server"
echo
echo "Upload this file to the Spacelift stack mounted file path:"
echo "  kube/config"
echo
echo "Set this stack environment variable:"
echo "  TF_VAR_kubeconfig_path=/mnt/workspace/kube/config"
