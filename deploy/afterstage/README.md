# afterstage en `underkode`

Este overlay está destinado exclusivamente al cluster k3d `afterstage` de la
miniPC `underkode`. No debe aplicarse con el contexto del cluster nativo de
Orux.

## Preflight

Desde `underkode`:

```bash
export KUBECONFIG="$HOME/.kube/afterstage.yaml"
kubectl get nodes
kubectl get namespace afterstage
kubectl -n afterstage get secret medio-under-secrets medio-under-x509 afterstage-cloudflared
kubectl -n afterstage get secret medio-under-secrets -o jsonpath='{.data.MONGODB_URI}'
```

Los dos Secrets son obligatorios y deben crearse fuera de Git. `MONGODB_URI`,
`JWT_SECRET` y el certificado `x509.pem` no deben sustituirse por valores de
ejemplo. El agente genera el contenido y `crear_nota_con_ia` sólo guarda el
borrador en Afterstage, por lo que no requiere una `AI_API_KEY`. Esa clave sólo
es opcional si se habilitan herramientas internas de regeneración editorial.

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
en el Secret `afterstage-cloudflared`.

## Verificación

```bash
curl --fail --silent --show-error https://afterstage.ar/health
curl --fail --silent --show-error https://afterstage.ar/monetizar
kubectl -n afterstage logs deployment/cloudflared --tail=100
```

Si el endpoint público devuelve 502, revisar primero `endpoints` y luego los
logs de `cloudflared`; un Service sin endpoints vuelve a producir el mismo
error aunque el túnel esté conectado.
