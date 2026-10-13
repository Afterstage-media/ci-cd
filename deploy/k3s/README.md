# Medio Under en k3s

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
kubectl -n medio-under rollout status deployment/backend
kubectl -n medio-under rollout status deployment/website
```

El sitio queda dentro del cluster en `http://website.medio-under.svc.cluster.local`. Para usar el túnel nombrado:

```bash
kubectl apply -f deploy/k3s/cloudflared-named.yaml
kubectl -n medio-under logs -f deployment/cloudflared
```

Para una URL temporal de prueba:

```bash
kubectl apply -f deploy/k3s/cloudflared-quick.yaml
kubectl -n medio-under logs -f deployment/cloudflared-quick
```

La URL temporal cambia al reiniciar. Para Meta y publicaciones reales usar un túnel nombrado con hostname estable y configurar ese hostname en `PUBLIC_BASE_URL` y `CLOUDFLARE_TUNNEL_URL` del ConfigMap.

## Actualizar

Construir/importar las imágenes nuevas y ejecutar:

```bash
kubectl -n medio-under rollout restart deployment/backend deployment/website
kubectl -n medio-under get pods,svc,pvc
```

Los PVC no se eliminan al actualizar deployments. MongoDB Atlas debe tener Network Access y el usuario configurados para el nodo/egress del cluster.
