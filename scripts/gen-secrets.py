#!/usr/bin/env python3
"""Génère les secrets d'un environnement dans group_vars/all/vault.yml.

Refuse d'écraser un fichier existant : perdre ces valeurs rend les données
illisibles (clé de chiffrement de Langfuse, sel de LiteLLM…). Le fichier doit
ensuite être chiffré : make vault-encrypt ENV=<env>.
"""
import secrets
import sys
from pathlib import Path

HEX = [
    "postgres_password",
    "pg_keycloak_password",
    "pg_litellm_password",
    "pg_openwebui_password",
    "pg_langfuse_password",
    "keycloak_admin_password",
    "oidc_openwebui_secret",
    "oidc_grafana_secret",
    "oidc_langfuse_secret",
    "webui_secret_key",
    "qdrant_api_key",
    "grafana_admin_password",
    "langfuse_nextauth_secret",
    "langfuse_salt",
    "langfuse_encryption_key",  # 64 caractères hexadécimaux exigés par Langfuse
    "langfuse_init_password",
    "clickhouse_password",
    "redis_password",
    "minio_password",
    "restic_password",
    "litellm_salt_key",
]


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage : {sys.argv[0]} <dossier de l'inventaire>", file=sys.stderr)
        return 2
    target = Path(sys.argv[1]) / "group_vars" / "all" / "vault.yml"
    if not target.parent.is_dir():
        print(f"Inventaire introuvable : {target.parent}", file=sys.stderr)
        return 1
    if target.exists():
        print(f"Refus d'écraser {target}", file=sys.stderr)
        return 1

    values = {f"vault_{name}": secrets.token_hex(32) for name in HEX}
    # LiteLLM impose le préfixe « sk- » pour ses clés.
    values["vault_litellm_master_key"] = "sk-" + secrets.token_hex(32)
    values["vault_litellm_openwebui_key"] = "sk-" + secrets.token_hex(32)
    values["vault_vllm_api_key"] = secrets.token_hex(32)
    values["vault_langfuse_public_key"] = "pk-lf-" + secrets.token_hex(16)
    values["vault_langfuse_secret_key"] = "sk-lf-" + secrets.token_hex(32)
    # Mot de passe du compte de service AD : à fournir par l'administrateur de l'annuaire.
    values["vault_ldap_bind_password"] = "CHANGEME"

    lines = ["---"] + [f'{key}: "{value}"' for key, value in sorted(values.items())]
    target.touch(mode=0o600)
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Secrets écrits dans {target} : renseigner vault_ldap_bind_password, puis chiffrer.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
