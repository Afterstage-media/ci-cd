# GitOps con Flux para Afterstage

Flux obtiene el estado deseado desde GitHub y reconcilia producción en el
cluster `k3d-afterstage` de `underkode`. El repositorio público de aplicación y
el repositorio privado de secretos se sincronizan por separado.

## Requisitos

1. Instalar Flux ejecutando `scripts/bootstrap-afterstage-flux.sh` en
   `underkode` con el contexto `~/.kube/afterstage.yaml`.
2. El bootstrap crea en `flux-system` la credencial GitHub para el repositorio
   privado y `afterstage-sops-age` con las dos identidades age de producción.
3. Crear `ghcr-auth` en `flux-system` con un PAT de solo lectura para los paquetes:

```bash
kubectl -n flux-system create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username=USUARIO \
  --docker-password=TOKEN_READ_PACKAGES
```

4. No crear manualmente los Secrets de la aplicación: la Kustomization
   `afterstage-secrets` descifra SOPS/age y los aplica desde
   `Afterstage-media/afterstage-secrets`.

## Recursos reconciliados

```bash
kubectl -n flux-system get gitrepositories
kubectl -n flux-system get kustomizations
flux reconcile kustomization afterstage --namespace=flux-system --with-source
flux get sources git
flux get kustomizations
```

El branch de producción es `main`. `afterstage-secrets` usa SOPS con dos
identidades age y Flux descifra sólo durante la reconciliación. El chart
Reloader reinicia backend y túneles cuando cambia un ConfigMap o Secret, porque
Kubernetes no reinicia automáticamente los pods que consumen variables de
entorno.

## Flujo

```text
push a main → GitRepository afterstage → Kustomization afterstage
push secretos → GitRepository afterstage-secrets → SOPS/age → Secrets
                                                               ↓
                                      Reloader → rollout de workloads
```

El túnel nombrado se mantiene dentro del overlay de producción y apunta al Service `website`. La URL pública y el token siguen siendo secretos/configuración del cluster, no parte del repositorio.

## Releases y tags

El workflow `.github/workflows/release.yml` contiene el flujo de release versionado
del medio. En cada push a `main` calcula la próxima versión a partir de
Conventional Commits, crea un tag anotado e inmutable `vX.Y.Z` y publica la
release de GitHub. Las imágenes continúan publicándose mediante GitHub Actions.
El despliegue de Afterstage sigue el manifiesto versionado en
`deploy/afterstage`; no depende de un commit automático de Flux para cambiar
tags.

Los commits que disparan versiones deben usar `feat:`, `fix:`, `perf:` o indicar
un cambio incompatible. El workflow de `commit-policy` valida esta convención en
pull requests y en `main`.
