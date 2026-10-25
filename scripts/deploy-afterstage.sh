#!/usr/bin/env bash
set -euo pipefail

# Reconcile the Afterstage production resources managed by Flux.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl_cmd=(kubectl)
for command_name in kubectl flux; do
  command -v "$command_name" >/dev/null || {
    echo "$command_name no está instalado en underkode" >&2
    exit 127
  }
done

if [[ -n "${KUBECONFIG:-}" ]]; then
  kubectl_cmd=(env KUBECONFIG="$KUBECONFIG" kubectl)
fi

"${kubectl_cmd[@]}" config current-context
"${kubectl_cmd[@]}" get nodes
"${kubectl_cmd[@]}" get namespace afterstage >/dev/null

flux reconcile kustomization afterstage-flux --namespace=flux-system --with-source
flux reconcile kustomization afterstage-secrets --namespace=flux-system --with-source
flux reconcile kustomization afterstage --namespace=flux-system --with-source
"${kubectl_cmd[@]}" -n afterstage rollout status deployment/backend --timeout=180s
"${kubectl_cmd[@]}" -n afterstage rollout status deployment/website --timeout=180s
"${kubectl_cmd[@]}" -n afterstage get pod,svc,endpoints
