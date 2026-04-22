#!/usr/bin/env bash
set -euo pipefail

namespace="observability"
pids=()

cleanup() {
  for pid in "${pids[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}

trap cleanup EXIT INT TERM

kubectl -n "$namespace" port-forward svc/hotrod 8080:8080 >/tmp/hotrod-port-forward.log 2>&1 &
pids+=("$!")

kubectl -n "$namespace" port-forward svc/jaeger-ui 16686:16686 >/tmp/jaeger-port-forward.log 2>&1 &
pids+=("$!")

echo "HotROD: http://localhost:8080"
echo "Jaeger: http://localhost:16686"
echo "Press Ctrl+C to stop the port-forwards."

wait
