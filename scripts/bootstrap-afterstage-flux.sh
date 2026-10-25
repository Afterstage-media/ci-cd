#!/usr/bin/env bash
set -Eeuo pipefail

# Bootstrap Flux on the isolated Afterstage cluster. Secret values are read
# from protected files on underkode and are never committed or printed.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl_cmd=(kubectl)
if [[ -n "${KUBECONFIG:-}" ]]; then
  kubectl_cmd=(env KUBECONFIG="$KUBECONFIG" kubectl)
fi

github_token_file="${AFTERSTAGE_SECRETS_GITHUB_TOKEN_FILE:-/home/fedemarkoo/.config/afterstage/github-read-token}"
age_key_file="${AFTERSTAGE_SOPS_AGE_KEY_FILE:-/home/fedemarkoo/.config/age/afterstage-prod-keys.txt}"

for command_name in kubectl flux; do
  command -v "$command_name" >/dev/null || {
    echo "$command_name no está instalado en underkode" >&2
    exit 127
  }
done
for protected_file in "$github_token_file" "$age_key_file"; do
  if [[ ! -r "$protected_file" ]]; then
    echo "Falta el archivo protegido requerido: $protected_file" >&2
    exit 1
  fi
done

context="$("${kubectl_cmd[@]}" config current-context)"
if [[ "$context" != "k3d-afterstage" ]]; then
  echo "Contexto incorrecto: se esperaba k3d-afterstage y se obtuvo $context" >&2
  exit 1
fi

"${kubectl_cmd[@]}" create namespace flux-system --dry-run=client -o yaml | "${kubectl_cmd[@]}" apply -f - >/dev/null
flux install --namespace=flux-system --export | "${kubectl_cmd[@]}" apply -f - >/dev/null

github_token="$(tr -d '\r\n' < "$github_token_file")"
"${kubectl_cmd[@]}" -n flux-system create secret generic afterstage-secrets-github \
  --from-literal=username=x-access-token \
  --from-literal=password="$github_token" \
  --dry-run=client -o yaml | "${kubectl_cmd[@]}" apply -f - >/dev/null

"${kubectl_cmd[@]}" -n flux-system create secret generic afterstage-sops-age \
  --from-file=age.agekey="$age_key_file" \
  --dry-run=client -o yaml | "${kubectl_cmd[@]}" apply -f - >/dev/null

"${kubectl_cmd[@]}" apply -f "$repo_root/deploy/flux/bootstrap.yaml" >/dev/null
flux reconcile source git afterstage --namespace=flux-system
flux reconcile kustomization afterstage-flux --namespace=flux-system --with-source
flux reconcile kustomization afterstage-secrets --namespace=flux-system --with-source
flux reconcile kustomization afterstage --namespace=flux-system --with-source
flux get all --namespace=flux-system
