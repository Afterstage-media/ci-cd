#!/usr/bin/env python3
"""Validate the production-only ConfigMap/Secret contract for Afterstage."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIGMAP = ROOT / "deploy/k3s/configmap.yaml"
PRODUCTION_OVERLAY = ROOT / "deploy/afterstage/kustomization.yaml"
BACKEND = ROOT / "deploy/k3s/backend.yaml"
SECRET = ROOT / "deploy/k3s/secret.example.yaml"
CLOUDFLARED_SECRET = ROOT / "deploy/k3s/cloudflared-secret.example.yaml"
X509_SECRET = ROOT / "deploy/k3s/x509-secret.example.yaml"

PLACEHOLDER = re.compile(
    r"(REEMPLAZAR|REPLACE|EXAMPLE|EJEMPLO|CHANGE[-_ ]?ME|CLUSTER\.EXAMPLE|USUARIO|PASSWORD|TOKEN_DEL_TUNEL)",
    re.IGNORECASE,
)
SENSITIVE_KEY = re.compile(
    r"(PASSWORD|PASSWD|TOKEN|SECRET|PRIVATE_KEY|CERTIFICATE|PEM|API_KEY|CREDENTIAL|MONGODB_URI)",
    re.IGNORECASE,
)


def fail(message: str) -> None:
    raise ValueError(message)


def mapping(path: Path, marker: str) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    try:
        start = lines.index(marker)
    except ValueError as error:
        fail(f"{path}: falta {marker}")
        raise AssertionError from error

    values: dict[str, str] = {}
    for line in lines[start + 1 :]:
        if line and not line.startswith(" "):
            break
        match = re.match(r"^\s{2}([A-Za-z0-9_.-]+):(?:\s*(.*))?$", line)
        if match:
            values[match.group(1)] = (match.group(2) or "").strip().strip('"').strip("'")
    return values


def require(path: Path, text: str, needle: str) -> None:
    if needle not in text:
        fail(f"{path}: falta {needle}")


def validate() -> None:
    config_text = CONFIGMAP.read_text(encoding="utf-8")
    require(CONFIGMAP, config_text, "name: afterstage-config")
    require(CONFIGMAP, config_text, "namespace: afterstage")
    config = mapping(CONFIGMAP, "data:")
    expected_config = {
        "NODE_ENV": "production",
        "MONGODB_DB": "afterstage",
        "PUBLIC_BASE_URL": "https://afterstage.ar",
        "CORS_ORIGINS": "https://afterstage.ar",
        "PUBLIC_INCLUDE_DEMO_DATA": "false",
        "META_INSTAGRAM_APP_ID": "1422226186554406",
        "META_INSTAGRAM_REDIRECT_URI": "https://afterstage.ar/api/integrations/instagram/callback",
    }
    for key, expected in expected_config.items():
        if config.get(key) != expected:
            fail(f"{CONFIGMAP}: {key} debe ser {expected!r}")
    sensitive_config = sorted(key for key in config if SENSITIVE_KEY.search(key))
    if sensitive_config:
        fail(f"{CONFIGMAP}: claves sensibles en ConfigMap: {', '.join(sensitive_config)}")
    if any("mongodb+srv://" in value or "@" in value for value in config.values()):
        fail(f"{CONFIGMAP}: no se permiten URIs o credenciales Mongo")
    overlay_text = PRODUCTION_OVERLAY.read_text(encoding="utf-8")
    require(PRODUCTION_OVERLAY, overlay_text, "path: /data/MONGODB_DB")
    require(PRODUCTION_OVERLAY, overlay_text, "value: medio_under")

    secret_text = SECRET.read_text(encoding="utf-8")
    require(SECRET, secret_text, "name: afterstage-secrets")
    secret = mapping(SECRET, "stringData:")
    for key in ("JWT_SECRET", "MONGODB_URI"):
        if key not in secret or not secret[key]:
            fail(f"{SECRET}: falta la clave requerida {key}")
    if "CLOUDFLARE_TUNNEL_TOKEN" in secret:
        fail(f"{SECRET}: el token de Cloudflare debe estar separado")
    for path, name, key in (
        (CLOUDFLARED_SECRET, "afterstage-cloudflared", "TUNNEL_TOKEN"),
        (X509_SECRET, "afterstage-x509", "x509.pem"),
    ):
        text = path.read_text(encoding="utf-8")
        require(path, text, f"name: {name}")
        values = mapping(path, "stringData:")
        if not values.get(key):
            fail(f"{path}: falta la clave {key}")
        if not PLACEHOLDER.search(values[key]):
            fail(f"{path}: el ejemplo no puede contener un valor real")
    for path, values in ((SECRET, secret), (CLOUDFLARED_SECRET, mapping(CLOUDFLARED_SECRET, "stringData:")), (X509_SECRET, mapping(X509_SECRET, "stringData:"))):
        for key, value in values.items():
            if value and not PLACEHOLDER.search(value):
                fail(f"{path}: el ejemplo contiene un valor no-placeholder en {key}")

    backend_text = BACKEND.read_text(encoding="utf-8")
    if "secretRef:" in backend_text:
        fail(f"{BACKEND}: no se permite inyectar el Secret completo con envFrom")
    for key in ("JWT_SECRET", "MONGODB_URI", "META_TOKEN_ENCRYPTION_KEY", "SMTP_PASS"):
        if f"key: {key}" not in backend_text:
            fail(f"{BACKEND}: falta referencia explícita a {key}")
    if "CLOUDFLARE_TUNNEL_TOKEN" in backend_text:
        fail(f"{BACKEND}: el backend no debe recibir el token del túnel")

    print("OK: contrato de configuración y secretos de producción validado")


if __name__ == "__main__":
    try:
        validate()
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
