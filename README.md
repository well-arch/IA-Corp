# IA-Corp : infrastructure de l'assistant IA on-premise

Infrastructure as code du socle décrit dans [`docs/roadmap.md`](docs/roadmap.md) : un
assistant hébergé dans l'entreprise, réservé aux employés authentifiés, sans aucun flux
vers Internet. Tout est déployé par Ansible sur deux types de serveurs, en Docker Compose.

| Serveur | Services |
|---|---|
| **Central** (`ai_core`) | Caddy (TLS), Keycloak, Open WebUI, LiteLLM, Qdrant, Docling, PostgreSQL, Langfuse, Prometheus, Grafana, sauvegarde restic |
| **GPU** (`ai_gpu`) | vLLM (assistant, modèle léger, embeddings, reranker), Caddy (TLS), métriques GPU |

```text
Employé ─TLS→ Caddy ─→ Open WebUI ─→ LiteLLM ─TLS + clé→ Caddy GPU ─→ vLLM
                 │          │            │
                 └→ Keycloak ←→ Active Directory (LDAPS)
                            │            └→ Langfuse (métadonnées, sans contenu)
                            └→ Qdrant, Docling
```

## Démarrage

Prérequis côté serveurs et valeurs à obtenir : [`docs/deploiement.md`](docs/deploiement.md).

```bash
make bootstrap              # outillage local dans .venv
make init ENV=prod          # crée ansible/inventories/prod et génère les secrets
# renseigner hosts.yml, group_vars/all/main.yml et le mot de passe du compte AD
make vault-encrypt ENV=prod
make models-download DIR=/chemin/poids   # depuis un poste relié à Internet
make models-push DIR=/chemin/poids HOST=user@ip-serveur-gpu
make check ENV=prod         # contrôle les prérequis, sans rien modifier
make deploy ENV=prod
make verify ENV=prod        # teste la plateforme de bout en bout
```

`make help` liste toutes les commandes. Avant toute modification du dépôt : `make validate`.

## Documentation

- [`docs/deploiement.md`](docs/deploiement.md) : prérequis, valeurs à fournir, procédure
- [`docs/exploitation.md`](docs/exploitation.md) : mises à jour, sauvegardes, rotation, incidents
- [`docs/guide-ad.md`](docs/guide-ad.md) : raccordement à Active Directory, gestes courants
- [`docs/guide-employes.md`](docs/guide-employes.md) : première connexion et bon usage, à
  compléter et à faire valider avant diffusion
- [`docs/couverture-roadmap.md`](docs/couverture-roadmap.md) : ce qui est couvert, ce qui
  reste à faire et ce qui a réellement été testé
- [`docs/roadmap.md`](docs/roadmap.md) : la feuille de route d'origine
