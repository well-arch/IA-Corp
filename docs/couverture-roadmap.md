# Couverture de la roadmap

État au 4 novembre 2026.

## Ce que déploie ce dépôt

| Brique de la roadmap | Implémentation | État |
|---|---|---|
| LLM principal | Mistral Small 4, version **NVFP4** | Déployé par le profil `production` |
| LLM léger | Gemma 4 E4B | Idem |
| Inférence | vLLM 0.32 | Déployé |
| Passerelle | LiteLLM, une clé par service, attribution par employé | Déployé |
| Interface | Open WebUI | Déployé |
| Identité | Keycloak, fédération AD en lecture seule, groupes, OTP obligatoire | Déployé |
| Extraction | Docling, avec OCR | Déployé |
| Embeddings et reranker | BGE-M3, bge-reranker-v2-m3 | Déployé |
| Base vectorielle | Qdrant | Déployé |
| Observabilité | Langfuse, Prometheus, Grafana | Déployé |
| Déploiement | Docker Compose par Ansible | Déployé. Kubernetes reste la seconde étape prévue |
| Réseau | Pare-feu nftables, conteneurs sans sortie | Déployé |
| TLS | CA interne ou PKI d'entreprise | Déployé, voir les écarts |
| Disques | Contrôle de LUKS, pas son installation | Déployé |
| Poids | Révision et SHA-256 figés, serveur GPU hors ligne | Déployé |
| Sauvegarde | restic chiffré, chaque nuit | Déployé |
| Journal d'audit | Événements Keycloak, journaux LiteLLM, accès Caddy | Déployé |

## Ce qui n'est pas de l'infrastructure, donc pas encore fait

Ces briques demandent du **code applicatif** et des choix qui dépendent des réponses aux
questions ouvertes de la roadmap (messagerie, sources documentaires).

| Sujet | Phase | Précision |
|---|---|---|
| **RAG filtré par les ACL d'origine** | 2 | Le plus important. Open WebUI ne donne des droits que par collection et par groupe : il ne reprend pas les ACL document par document. **Ne pas indexer de documents sensibles à accès mixte avant ce développement.** |
| Connecteurs vers les sources (partages, SharePoint…) | 2 | Dépend des sources |
| Jeu de 100 questions d'évaluation | 2 | À écrire avec les métiers |
| Agents LangGraph et serveurs MCP mail, agenda, GED | 3 | Validation humaine et jeton délégué à y intégrer |
| Rapports Word/PDF, transcription Whisper | 3 et + | Non déployés |
| Quotas par employé | 2 | LiteLLM reçoit l'identité ; seules les limites par service sont posées |

Et ce qui relève de l'organisation : AIPD, registre, CSE, charte, pentest, comité IA.

## Écarts assumés par rapport à la roadmap

| Roadmap | Réalité | Raison |
|---|---|---|
| « TLS partout, y compris entre services internes » | TLS entre serveurs et vers les clients. Entre conteneurs d'un même serveur : HTTP, sur des réseaux Docker isolés | Coût élevé pour un faible gain sur un même hôte. À réexaminer avec le RSSI |
| « Préférer safetensors » | BGE-M3 reste en `pytorch_model.bin` (pickle) | Seul format publié pour ce modèle. Hash figé, exception explicite (`allow_pickle`) : tout autre fichier pickle fait échouer le déploiement. Une conversion en safetensors sur un poste isolé supprimerait ce risque |
| « Départ : perte d'accès immédiate » | Immédiate pour les nouvelles connexions, au plus 8 h pour une session ouverte | Limite d'Open WebUI, voir `exploitation.md` |
| Registre interne de poids | Fichiers vérifiés sur le serveur GPU | Plus simple à ce stade, sans perte sur l'intégrité |
| Serveur « 2 à 4 GPU » | Profil à 2 GPU | La fiche du modèle indique deux GPU ; la répartition reste à ajuster |

## Choix prudents à faire valider

- **Contenu des conversations non journalisé** (`ia_log_conversation_content: false`) : seules
  les métadonnées sont gardées. La roadmap demande de tracer « qui, quoi, quand » : si le
  « quoi » doit inclure le texte, c'est une décision pour le DPO et le CSE, pas un défaut.
- **Licence d'Open WebUI** : sa clause sur la marque est à relire au-delà de 50 utilisateurs.
- **Modèles Qwen et DeepSeek** : écartés par défaut en attendant la décision interne.

## Ce qui a réellement été testé

Aucun serveur réel n'existant encore, rien n'a tourné sur la cible.

**Exécuté en conditions réelles, dans des conteneurs temporaires :**

- Keycloak 26.8 : import du royaume avec annuaire et ses mappeurs, secrets lus depuis
  l'environnement, flux MFA sur base neuve puis rejoué sans changement.
- Parcours de connexion réel : après le mot de passe, redirection vers `CONFIGURE_TOTP`.
  Mot de passe direct sur un client refusé, console `/admin` bloquée hors réseau d'admin.
- CA interne et certificats, vérifiés par Open WebUI, Grafana et LiteLLM.
- LiteLLM vers le vrai Caddy GPU et un **vLLM simulé** : chat, embeddings, reranking, URL et
  clés correctes, attribution de l'employé, clé de service créée sans doublon.
- Open WebUI et Grafana : redirection vers le SSO, formulaire local désactivé. Open WebUI a
  été testé avec l'image `main`, pas avec la version figée 0.12.5.
- Langfuse 4.73 : démarrage, migrations, connexion par mot de passe refusée, réception des
  traces, **texte remplacé par `redacted-by-litellm`** et employé bien attribué.
- PostgreSQL (bases séparées, `pg_dumpall`), instantané Qdrant, réseau `data` sans sortie.

**Validé statiquement (`make validate`) :** syntaxe et lint Ansible, rendu des 4 combinaisons
de profil et d'annuaire, Compose, `nft -c`, `caddy adapt`, `promtool`.

**Jamais exécuté, donc à surveiller au premier déploiement :**

| Élément | Risque principal |
|---|---|
| vLLM réel, poids réels | Options des modèles, compatibilité de NVFP4 selon le GPU, réglages de mémoire GPU |
| **Mistral NVFP4 sur le GPU acheté** | La fiche ne précise pas les GPU compatibles : à vérifier **avant l'achat** |
| Active Directory réel | Filtre, mappeurs, LDAPS, synchronisation (seul l'import de la configuration est testé) |
| Rôles système sur Ubuntu : `preflight`, `base`, `docker`, `nvidia`, `models`, `backup` | Passés au lint, jamais lancés |
| Pare-feu appliqué | Validé par `nft -c` seulement. **Garder un accès console au premier passage** |
| `make verify` | Écrit, jamais lancé contre une plateforme complète |
| Docling | Image non démarrée, modèles OCR hors ligne à confirmer |
| Procédure de restauration | Jamais déroulée |
| Tenue en charge | À mesurer sur le vrai matériel |
