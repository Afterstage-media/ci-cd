# afterstage en k3s

El despliegue usa el `local-path` de k3s para datos y medios, MongoDB Atlas para persistencia principal y Cloudflare Tunnel para exposición pública. El túnel apunta al servicio `website`, que enruta API, panel, notas, RSS y `/media` hacia el gestor.

## Preparar imágenes

En el nodo k3s, desde el repositorio:

```bash
docker build -t backend:latest ../backend
docker build -t frontend:latest -f infra/Dockerfile ..
# Si el runtime usa containerd sin Docker:
docker save backend:latest frontend:latest | sudo k3s ctr images import -
```

## Instalar

```bash
kubectl apply -f deploy/k3s/secret.example.yaml
# Editar el Secret antes de continuar: no commitear credenciales reales.
kubectl apply -k deploy/k3s
kubectl -n afterstage rollout status deployment/backend
kubectl -n afterstage rollout status deployment/website
```

El sitio queda dentro del cluster en `http://website.afterstage.svc.cluster.local`. Para usar el túnel nombrado:

```bash
kubectl apply -f deploy/k3s/cloudflared-named.yaml
kubectl -n afterstage logs -f deployment/cloudflared
```

Para una URL temporal de prueba:

```bash
kubectl apply -f deploy/k3s/cloudflared-quick.yaml
kubectl -n afterstage logs -f deployment/cloudflared-quick
```

La URL temporal cambia al reiniciar. Para Meta y publicaciones reales usar un túnel nombrado con hostname estable y configurar ese hostname en `PUBLIC_BASE_URL` y `CLOUDFLARE_TUNNEL_URL` del ConfigMap.

## Dominio de producción: afterstage.ar

> Este directorio describe el cluster k3s nativo de Orux. El sitio de
> `afterstage.ar` debe desplegarse en el cluster k3d aislado de `underkode`,
> usando `deploy/afterstage` y `~/.kube/afterstage.yaml`. No aplicar este
> overlay con el contexto por defecto de `kubectl`.

El proyecto queda preparado para publicar en `https://afterstage.ar`. El dominio todavía figura pendiente de pago en NIC Argentina, por lo que los pasos externos se completan cuando la registración quede activa:

1. En Cloudflare, agregar `afterstage.ar` como zona y conservar los nameservers que indique Cloudflare.
2. En el túnel nombrado asociado al token de `afterstage-secrets`, crear una ruta pública:
   - Hostname: `afterstage.ar`
   - Service: `http://website:80`
3. Opcionalmente agregar `www.afterstage.ar` con redirección al dominio raíz.
4. Aplicar el overlay de producción y verificar el rollout:

   ```bash
   kubectl apply -k deploy/k3s/overlays/production
   kubectl -n afterstage rollout status deployment/website
   kubectl -n afterstage rollout status deployment/backend
   kubectl -n afterstage logs deployment/cloudflared --tail=100
   ```

5. Comprobar `https://afterstage.ar/health` y luego regenerar sitemap/robots desde el backend para que usen el dominio público.

No se incluye ningún token o credencial en el repositorio. El `CLOUDFLARE_TUNNEL_TOKEN` debe continuar en el Secret `afterstage-secrets`.

## Actualizar

Construir/importar las imágenes nuevas y ejecutar:

```bash
kubectl -n afterstage rollout restart deployment/backend deployment/website
kubectl -n afterstage get pods,svc,pvc
```

Los PVC no se eliminan al actualizar deployments. MongoDB Atlas debe tener Network Access y el usuario configurados para el nodo/egress del cluster.
