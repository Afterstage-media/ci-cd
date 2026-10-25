# Medio Under en `underkode`

Este overlay está destinado exclusivamente al cluster k3d `afterstage` de la
miniPC `underkode`. No debe aplicarse con el contexto del cluster nativo de
Orux.

## Preflight

Desde `underkode`:

```bash
export KUBECONFIG="$HOME/.kube/afterstage.yaml"
kubectl get nodes
kubectl get namespace afterstage
kubectl -n afterstage get secret medio-under-secrets medio-under-x509
kubectl -n afterstage get secret medio-under-secrets -o jsonpath='{.data.MONGODB_URI}'
```

Los dos Secrets son obligatorios y deben crearse fuera de Git. `MONGODB_URI`,
`JWT_SECRET` y el certificado `x509.pem` no deben sustituirse por valores de
ejemplo.

## Aplicar

Con el repositorio `ci-cd` disponible en `underkode`:

```bash
export KUBECONFIG="$HOME/.kube/afterstage.yaml"
kubectl apply -k deploy/afterstage
kubectl -n afterstage rollout status deployment/backend --timeout=180s
kubectl -n afterstage rollout status deployment/website --timeout=180s
kubectl -n afterstage get pod,svc,endpoints
```

El túnel nombrado debe tener la ruta `afterstage.ar -> http://website:80` en
Cloudflare. La configuración del túnel no se guarda en Git; el token continúa
en el Secret `medio-under-secrets`.

Para habilitar fotos R2, configurar en `afterstage-config` `MEDIA_GATEWAY_URL`
y `MEDIA_PUBLIC_BASE_URL`, y en `medio-under-secrets`
`MEDIA_GATEWAY_SERVICE_TOKEN`. El frontend debe construirse con
`VITE_R2_MEDIA_UPLOADS=true`; mientras esté en `false` conserva el flujo local
legado. El Worker y su bucket se administran en el repositorio separado
`afterstage-storage-gateway`.

## Verificación

```bash
curl --fail --silent --show-error https://afterstage.ar/health
curl --fail --silent --show-error https://afterstage.ar/monetizar
kubectl -n afterstage logs deployment/cloudflared --tail=100
```

Si el endpoint público devuelve 502, revisar primero `endpoints` y luego los
logs de `cloudflared`; un Service sin endpoints vuelve a producir el mismo
error aunque el túnel esté conectado.
