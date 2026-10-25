#!/usr/bin/env bash
set -euo pipefail

# Deploy the afterstage production overlay to the isolated k3d cluster on underkode.
# Production secrets are pulled from the private SOPS repository and never stored
# in the application repository or passed as shell arguments.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubectl_cmd=(kubectl)
sops_bin="${SOPS_BIN:-/home/fedemarkoo/.local/bin/sops}"
secrets_repo_dir="${AFTERSTAGE_SECRETS_DIR:-/home/fedemarkoo/.config/afterstage/secrets-repo}"
github_token_file="${AFTERSTAGE_SECRETS_GITHUB_TOKEN_FILE:-/home/fedemarkoo/.config/afterstage/github-read-token}"
age_key_file="${AFTERSTAGE_SOPS_AGE_KEY_FILE:-/home/fedemarkoo/.config/age/afterstage-prod-keys.txt}"
secrets_repo="${AFTERSTAGE_SECRETS_REPO:-https://github.com/Afterstage-media/afterstage-secrets.git}"
secrets_branch="${AFTERSTAGE_SECRETS_BRANCH:-main}"

if [[ ! -x "$sops_bin" ]]; then
  echo "SOPS no está disponible en $sops_bin" >&2
  exit 1
fi
if [[ ! -r "$github_token_file" ]]; then
  echo "Falta el token de lectura del repositorio privado: $github_token_file" >&2
  exit 1
fi
if [[ ! -r "$age_key_file" ]]; then
  echo "Falta la identidad age de producción: $age_key_file" >&2
  exit 1
fi

install -d -m 700 "$(dirname "$secrets_repo_dir")"
askpass_file="$(mktemp)"
chmod 700 "$askpass_file"
cat >"$askpass_file" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *) cat "$github_token_file" ;;
esac
EOF
trap 'rm -f "$askpass_file"' EXIT
git_env=(env GIT_ASKPASS="$askpass_file" GIT_TERMINAL_PROMPT=0)
if [[ -d "$secrets_repo_dir/.git" ]]; then
  "${git_env[@]}" git -C "$secrets_repo_dir" fetch --depth=1 origin "$secrets_branch"
  git -C "$secrets_repo_dir" reset --hard "origin/$secrets_branch" >/dev/null
else
  "${git_env[@]}" git clone --branch "$secrets_branch" --depth=1 "$secrets_repo" "$secrets_repo_dir" >/dev/null
fi

secrets_path="$secrets_repo_dir/projects/afterstage/prod/afterstage-secrets.sops.yaml"
cloudflared_path="$secrets_repo_dir/projects/afterstage/prod/afterstage-cloudflared.sops.yaml"
for encrypted_secret in "$secrets_path" "$cloudflared_path"; do
  if [[ ! -f "$encrypted_secret" ]]; then
    echo "Falta secreto cifrado en el repositorio privado: $encrypted_secret" >&2
    exit 1
  fi
done

if [[ -n "${KUBECONFIG:-}" ]]; then
  kubectl_cmd=(env KUBECONFIG="$KUBECONFIG" kubectl)
fi

"${kubectl_cmd[@]}" config current-context
"${kubectl_cmd[@]}" get nodes
"${kubectl_cmd[@]}" get namespace afterstage >/dev/null

SOPS_AGE_KEY_FILE="$age_key_file" "$sops_bin" -d "$secrets_path" | "${kubectl_cmd[@]}" -n afterstage apply -f - >/dev/null
SOPS_AGE_KEY_FILE="$age_key_file" "$sops_bin" -d "$cloudflared_path" | "${kubectl_cmd[@]}" -n afterstage apply -f - >/dev/null

for secret in afterstage-secrets afterstage-cloudflared; do
  if ! "${kubectl_cmd[@]}" -n afterstage get secret "$secret" >/dev/null 2>&1; then
    echo "Missing required secret in namespace afterstage: $secret" >&2
    exit 1
  fi
done

for key in MONGODB_URI JWT_SECRET; do
  if [[ -z $("${kubectl_cmd[@]}" -n afterstage get secret afterstage-secrets -o "jsonpath={.data.${key}}") ]]; then
    echo "Missing required key ${key} in secret afterstage-secrets" >&2
    exit 1
  fi
done

"${kubectl_cmd[@]}" apply -k "$repo_root/deploy/afterstage"
"${kubectl_cmd[@]}" -n afterstage rollout restart deployment/backend deployment/cloudflared
"${kubectl_cmd[@]}" -n afterstage rollout status deployment/backend --timeout=180s
"${kubectl_cmd[@]}" -n afterstage rollout status deployment/website --timeout=180s

# MongoDB Atlas is the only production database. The old local StatefulSet is
# intentionally removed after the Atlas-backed backend is healthy. The PVC is
# left untouched so it remains a recoverable snapshot until explicitly retired.
"${kubectl_cmd[@]}" -n afterstage delete service/mongodb statefulset/mongodb --ignore-not-found --wait=true
"${kubectl_cmd[@]}" -n afterstage get pod,svc,endpoints
