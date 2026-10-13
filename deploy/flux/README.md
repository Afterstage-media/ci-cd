# GitOps con Flux para k3s

Flux obtiene el estado deseado directamente desde GitHub y reconcilia el overlay de producción. Las imágenes se construyen en GitHub Actions, se publican en GHCR y Flux Image Automation actualiza los tags en el repositorio.

## Requisitos

1. Instalar Flux en el cluster k3s (`flux bootstrap github ...`) o instalar sus controllers equivalentes.
2. El repositorio debe ser accesible por Flux. Para un repositorio privado, crear el Secret `flux-system`/deploy key durante el bootstrap.
3. Crear `ghcr-auth` en `flux-system` con un PAT de solo lectura para los paquetes:

```bash
kubectl -n flux-system create secret docker-registry ghcr-auth \
  --docker-server=ghcr.io \
  --docker-username=USUARIO \
  --docker-password=TOKEN_READ_PACKAGES
```

4. Crear `medio-under-secrets` en el namespace de la aplicación con valores reales usando SOPS, Sealed Secrets o el gestor de secretos del cluster. No aplicar ni commitear valores reales de `secret.example.yaml`.

## Instalar Flux resources

```bash
kubectl apply -f deploy/flux/gitrepository.yaml
kubectl apply -f deploy/flux/kustomization.yaml
kubectl apply -f deploy/flux/image-automation.yaml
flux get sources git
flux get kustomizations
flux get images all -A
```

El branch configurado es `main`. Para desplegar otra rama, cambiar `spec.ref.branch` en `gitrepository.yaml` y el checkout/push de `image-automation.yaml`. La automatización de imágenes hace commits en `main`; proteger el branch permitiendo el bot de Flux.

## Flujo

```text
push a main → GitHub Actions → GHCR main-N
                              ↓
                 Flux ImagePolicy detecta N
                              ↓
                 ImageUpdateAutomation commitea tag
                              ↓
                 GitRepository/Kustomization despliega k3s
```

El túnel nombrado se mantiene dentro del overlay de producción y apunta al Service `website`. La URL pública y el token siguen siendo secretos/configuración del cluster, no parte del repositorio.

## Releases y tags

El workflow `.github/workflows/release.yml` contiene el flujo de release versionado
del medio. En cada push a `main` calcula la próxima versión a partir de
Conventional Commits, crea un tag anotado e inmutable `vX.Y.Z` y publica la
release de GitHub. Las imágenes también se publican con ese tag,
además de `main-N` y `latest`; Flux continúa siguiendo `main-N` para despliegue
continuo y las releases quedan disponibles para rollback reproducible.

Los commits que disparan versiones deben usar `feat:`, `fix:`, `perf:` o indicar
un cambio incompatible. El workflow de `commit-policy` valida esta convención en
pull requests y en `main`.
