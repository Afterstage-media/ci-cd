# afterstage en `underkode`

Este overlay está destinado exclusivamente al cluster k3d `afterstage` de la
miniPC `underkode`. No debe aplicarse con el contexto del cluster nativo de
Orux.

## Secretos de producción

Los valores reales viven en el repositorio privado
`Afterstage-media/afterstage-secrets`, cifrados con SOPS + age y con umbral de
dos identidades. En `underkode` deben existir, con permisos `0600`:

- `/home/fedemarkoo/.config/afterstage/github-read-token`: token de lectura
  para `Afterstage-media/afterstage-secrets`.
- `/home/fedemarkoo/.config/age/afterstage-prod-keys.txt`: las dos identidades
  age requeridas para descifrar producción.

El despliegue sincroniza ese repositorio, descifra en memoria y aplica sólo
`afterstage-secrets` y `afterstage-cloudflared` al namespace `afterstage`. No
se guardan valores descifrados en el checkout de la aplicación ni en Git.

## Preflight

Desde `underkode`:

```bash
export KUBECONFIG="$HOME/.kube/afterstage.yaml"
kubectl get nodes
kubectl get namespace afterstage
./scripts/deploy-afterstage.sh
```

Los dos Secrets son obligatorios y deben crearse fuera de Git. `MONGODB_URI`,
`JWT_SECRET` e `INBOUND_EMAIL_WEBHOOK_SECRET` no deben
sustituirse por valores de ejemplo. Para habilitar respuestas desde `/admin/correo`
también deben cargarse `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS` y `SMTP_FROM` en
`afterstage-secrets`. El agente genera el contenido y `crear_nota_con_ia` sólo
guarda el borrador en Afterstage, por lo que no requiere una `AI_API_KEY`. Esa
clave sólo es opcional si se habilitan herramientas internas de regeneración editorial.

El token del túnel vive únicamente en `afterstage-cloudflared`. La conexión a
MongoDB usa `MONGODB_URI` contra Atlas/cloud; no se despliega MongoDB local ni
se monta un certificado X.509 en el backend. No aplicar los archivos
`*.example.yaml`: sólo documentan el contrato de claves.

## Aplicar

Con el repositorio `ci-cd` disponible en `underkode`:

```bash
export KUBECONFIG="$HOME/.kube/afterstage.yaml"
./scripts/deploy-afterstage.sh
```

El túnel nombrado debe tener la ruta `afterstage.ar -> http://website:80` en
Cloudflare. La configuración del túnel no se guarda en Git; el token continúa
en el Secret `afterstage-cloudflared`.

Para habilitar fotos R2, configurar en `afterstage-config` `MEDIA_GATEWAY_URL`
y `MEDIA_PUBLIC_BASE_URL`, y en `afterstage-secrets`
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
