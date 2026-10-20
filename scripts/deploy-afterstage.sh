#!/usr/bin/env bash
set -euo pipefail

# Deploy the Medio Under production overlay to the isolated k3d cluster on underkode.
# Secrets and Cloudflare ingress are intentionally managed outside this script.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl_cmd=(kubectl)

if [[ -n "${KUBECONFIG:-}" ]]; then
  kubectl_cmd=(env KUBECONFIG="$KUBECONFIG" kubectl)
fi

"${kubectl_cmd[@]}" config current-context
"${kubectl_cmd[@]}" get nodes
"${kubectl_cmd[@]}" get namespace afterstage >/dev/null

for secret in medio-under-secrets medio-under-x509; do
  if ! "${kubectl_cmd[@]}" -n afterstage get secret "$secret" >/dev/null 2>&1; then
    echo "Missing required secret in namespace afterstage: $secret" >&2
    exit 1
  fi
done

for key in MONGODB_URI JWT_SECRET; do
  if [[ -z $("${kubectl_cmd[@]}" -n afterstage get secret medio-under-secrets -o "jsonpath={.data.${key}}") ]]; then
    echo "Missing required key ${key} in secret medio-under-secrets" >&2
    exit 1
  fi
done

"${kubectl_cmd[@]}" apply -k "$repo_root/deploy/afterstage"
"${kubectl_cmd[@]}" -n afterstage rollout status deployment/backend --timeout=180s
"${kubectl_cmd[@]}" -n afterstage rollout status deployment/website --timeout=180s
"${kubectl_cmd[@]}" -n afterstage get pod,svc,endpoints
