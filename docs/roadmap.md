# Roadmap – Assistant IA d'entreprise on-premise

Nov 4, 2026 · @Abel

## Résumé et hypothèses

Objectif : un assistant IA 100 % hébergé dans vos locaux, à base de modèles open-weight, accessible uniquement aux employés authentifiés, livré en 4 phases sur environ 9 à 12 mois. Aucune donnée ni requête ne sort du réseau de l'entreprise.

Hypothèses de travail (à valider, voir la dernière section) :

- Taille : 50 à 500 employés, dont 20 à 30 % d'utilisateurs actifs simultanés aux heures de pointe.
- Annuaire existant (Active Directory ou LDAP) servant de source unique des identités.
- Messagerie et agenda interrogeables par API standard (IMAP/SMTP, CalDAV, ou Exchange on-premise via EWS/Graph local).
- Documents internes sur des partages réseau, un SharePoint on-premise, Nextcloud ou une GED.
- Une petite équipe interne (2 à 4 personnes) pour construire et exploiter la plateforme.
- Langue principale : français, avec de l'anglais dans les documents.

Principe directeur : l'IA n'agit jamais avec plus de droits que l'employé qui l'utilise, et toute action ayant un effet (envoi de mail, création de rendez-vous) passe par une validation humaine.

## Architecture cible

&#91;embedded content: architecture cible · 6 couches\]

L'employé passe par le SSO, puis l'interface ou un agent ; les agents n'atteignent les systèmes existants qu'au travers des connecteurs, avec le jeton de l'utilisateur. Le RAG indexe les documents en conservant leurs droits d'accès, et utilise les embeddings du serveur GPU.

## Choix technologiques

Recommandation : une pile 100 % open source, avec un modèle généraliste de taille moyenne sur un seul serveur GPU, et des briques interchangeables derrière une API compatible OpenAI pour pouvoir changer de modèle sans rien réécrire.

| Brique | Choix recommandé | Alternatives | Rôle |
| --- | --- | --- | --- |
| LLM principal | Mistral Small 4 (119B, 6,5B actifs, Apache 2.0) | Qwen3.8-27B, gpt-oss-120b, Mistral Medium 3.5 | Rédaction, résumé, raisonnement, appels d'outils |
| LLM léger | Qwen3.8-27B ou Gemma 4 (Apache 2.0) | Ministral | Tri des mails, classification, tâches rapides |
| Serveur d'inférence | vLLM | SGLang, Ollama (tests uniquement) | Sert les modèles via une API compatible OpenAI |
| Passerelle modèles | LiteLLM (auto-hébergé) | — | Quotas, routage, journalisation, clés par service |
| Interface utilisateur | Open WebUI ou LibreChat | Interface maison | Chat, upload de documents, historique |
| Identité et accès | Keycloak relié à l'AD/LDAP, SSO + MFA | Authentik | Seuls les employés se connectent |
| Extraction de documents | Docling ou Apache Tika, OCR Tesseract | Unstructured | PDF, Word, Excel, scans vers texte |
| Embeddings + reranker | BGE-M3 + bge-reranker (multilingues) | multilingual-e5 | Recherche sémantique en français |
| Base vectorielle | Qdrant | PostgreSQL + pgvector, Weaviate | Index du RAG avec filtres par droits |
| Orchestration d'agents | LangGraph | LlamaIndex, smolagents | Enchaîne les étapes et les outils |
| Connecteurs (outils) | Serveurs MCP internes : mail, agenda, GED, annuaire | API maison | Donne aux agents un accès contrôlé aux systèmes |
| Messagerie / agenda | Exchange on-prem (EWS) ou IMAP/SMTP + CalDAV | Nextcloud, SOGo | Source et cible des actions mail/agenda |
| Génération de rapports | Modèles Word/PDF via python-docx et Pandoc | Carbone | Rapports aux couleurs de l'entreprise |
| Transcription (option) | Whisper large-v3 | faster-whisper | Comptes rendus de réunion |
| Observabilité | Langfuse + Prometheus/Grafana | OpenTelemetry | Traces, coûts GPU, qualité des réponses |
| Déploiement | Docker puis Kubernetes (k3s/RKE2) | Podman | Mise en production reproductible |

Pourquoi Mistral en premier choix : licence Apache 2.0, très bon niveau en français, éditeur européen, ce qui simplifie l'argumentaire RGPD et souveraineté. Les modèles Qwen et DeepSeek sont excellents et utilisables hors ligne ; certaines entreprises les écartent toutefois par politique d'origine, à trancher en interne.

Les modèles géants (Mistral Large 4, Kimi K3, GLM-5.3) exigent environ 8 GPU H200 ; ils ne sont pas nécessaires pour ces cas d'usage.

Fonctionnalités supplémentaires utiles en entreprise :

- Recherche unifiée dans les documents, mails et wikis, avec citations des sources.
- Traduction de documents et de mails.
- Compte rendu automatique de réunion à partir d'un enregistrement.
- Assistant RH et procédures internes (congés, notes de frais, onboarding).
- Aide à la rédaction de réponses aux appels d'offres à partir des anciens dossiers.
- Assistant code pour l'équipe IT (si elle existe).
- Analyse de tableaux Excel et génération de graphiques.

## Sécurité et conformité

La sécurité repose sur quatre règles : rien ne sort du réseau, chaque utilisateur est authentifié, l'IA hérite strictement de ses droits, et chaque action est tracée.

**Réseau et hébergement**

- Serveurs dans un VLAN dédié, sans accès Internet sortant (ou via un proxy limité aux mises à jour).
- Accès uniquement depuis le réseau interne ou le VPN de l'entreprise ; aucune exposition publique.
- TLS partout, y compris entre services internes ; disques chiffrés (LUKS).
- Poids des modèles téléchargés une fois, vérifiés par empreinte (SHA-256), stockés dans un registre interne. Préférer le format safetensors.

**Identité et droits**

- SSO Keycloak relié à l'annuaire, MFA obligatoire, groupes AD repris pour les rôles.
- Le RAG filtre les documents selon les ACL d'origine : un employé ne retrouve jamais un document qu'il ne pourrait pas ouvrir lui-même.
- Les agents mail et agenda agissent avec un jeton délégué de l'utilisateur, jamais avec un compte de service tout-puissant.
- Départ d'un employé : désactivation dans l'AD = perte d'accès immédiate.

**Agents et actions**

- Validation humaine obligatoire avant tout envoi de mail, invitation ou suppression.
- Liste blanche d'outils par rôle ; pas d'exécution de code arbitraire.
- Protection contre l'injection de prompt : le contenu des mails et documents est traité comme donnée, jamais comme instruction ; les mails externes sont marqués comme non fiables.
- Limites de débit et plafonds (nombre de mails envoyés par heure, destinataires externes signalés).

**Traçabilité et conformité**

- Journal d'audit de chaque requête et de chaque action (qui, quoi, quand), conservé selon votre politique.
- RGPD : registre de traitement, analyse d'impact (AIPD), information des salariés, durée de conservation des conversations, droit d'accès et d'effacement.
- Consultation du CSE : un outil pouvant analyser l'activité des salariés relève de son information-consultation.
- AI Act : un assistant de bureautique interne est en général à risque limité ; obligations de transparence et de formation des utilisateurs (maîtrise de l'IA) à prévoir. Usages RH (tri de CV, évaluation) = haut risque, à exclure ou à traiter à part.
- Pentest avant l'ouverture générale, puis revue annuelle ; référentiels utiles : ANSSI (recommandations IA générative) et OWASP Top 10 LLM.

## Roadmap par phases

&#91;embedded content: roadmap · 4 phases, 3 jalons de décision\]

Chaque phase se termine par un jalon go / no-go ; on ne connecte les mails et l'agenda qu'une fois le socle sécurisé et le RAG validé par les testeurs.

Points d'attention par phase :

1. **Cadrage** : choisir 3 cas d'usage à forte valeur (par exemple recherche dans les procédures, résumé de mails, rapport mensuel), recenser les sources de documents et leurs droits, consulter DPO et CSE.
2. **Socle + RAG** : installer l'infrastructure en code (Ansible, Helm), indexer 1 ou 2 sources pilotes, constituer un jeu de 100 questions métier avec réponses attendues pour mesurer la qualité.
3. **Mail et agenda** : commencer en lecture seule (résumé, tri, recherche), puis brouillons que l'employé valide avant envoi ; jamais d'envoi automatique au départ.
4. **Généralisation** : formations par service, second serveur GPU si la charge le justifie, pentest externe, puis revue semestrielle des modèles.

Au-delà du mois 12 : ajout de connecteurs métier (ERP, CRM, ticketing) et, si besoin, affinage (fine-tuning LoRA) d'un modèle sur le vocabulaire de l'entreprise.

## Matériel et budget indicatif

Pour 50 à 500 employés, un serveur GPU de production plus un petit serveur de test suffisent au démarrage ; compter environ 60 à 150 k€ HT de matériel. Les prix ci-dessous sont des ordres de grandeur approximatifs, à confirmer par devis.

| Configuration | Matériel | Modèles possibles | Utilisateurs simultanés (approx.) | Coût matériel approx. (HT) |
| --- | --- | --- | --- | --- |
| Pilote | 1 serveur, 1 GPU 48 à 96 Go (RTX PRO 6000 ou L40S) | Qwen3.8-27B, Gemma 4, gpt-oss-120b | 10 à 30 | 15 à 30 k€ |
| Production PME | 1 serveur, 2 à 4 GPU 80 à 96 Go | Mistral Small 4 + modèle léger + embeddings | 50 à 150 | 60 à 120 k€ |
| Production ETI / haute dispo | 2 serveurs GPU identiques + stockage partagé | Idem, redondé | 150 à 500 | 150 à 300 k€ |

À ajouter dans tous les cas :

- Un serveur CPU pour l'interface, Keycloak, Qdrant, PostgreSQL et la supervision (environ 64 Go de RAM, SSD NVMe 2 To).
- Une sauvegarde chiffrée hors du serveur (index RAG, historiques, configurations).
- Électricité et refroidissement : 1 à 3 kW par serveur GPU en charge, à valider avec la salle serveur.
- Fonctionnement : 2 à 4 personnes à temps partiel ou plein (voir la section suivante), principal poste de coût sur la durée.

Alternative si l'achat bloque : location de serveurs GPU dédiés chez un hébergeur français certifié SecNumCloud. Ce n'est plus strictement on-premise, mais les données restent sous contrôle et sous droit européen.

## Équipe, gouvernance et risques

Une équipe de 3 à 4 profils suffit, avec un sponsor métier qui priorise les cas d'usage.

| Rôle | Charge | Responsabilités |
| --- | --- | --- |
| Chef de projet / product owner | 50 % | Cas d'usage, priorités, adoption, lien avec les métiers |
| Ingénieur IA / backend | 100 % | RAG, agents, connecteurs, évaluation de la qualité |
| Ingénieur infra / DevOps | 50 à 100 % | Serveurs GPU, Kubernetes, supervision, sauvegardes |
| RSSI / référent sécurité | 20 % | Revue d'architecture, pentest, journal d'audit |
| DPO | ponctuel | AIPD, registre RGPD, information des salariés |

Gouvernance : un comité IA mensuel (sponsor, DSI, RSSI, DPO, représentant des utilisateurs) valide chaque nouvelle fonctionnalité et chaque nouvelle source de données indexée. Une charte d'usage est signée par les employés.

| Risque | Impact | Parade |
| --- | --- | --- |
| Réponses fausses (hallucinations) | Décisions erronées | RAG avec citations obligatoires, jeu de tests métier, mention « à vérifier » |
| Fuite de documents entre services | Confidentialité | Filtrage par ACL testé avant chaque nouvelle source |
| Injection de prompt via un mail externe | Action non voulue | Validation humaine, contenu externe marqué non fiable, liste blanche d'outils |
| Saturation GPU aux heures de pointe | Lenteur, rejet | Quotas par utilisateur, modèle léger pour les tâches simples, supervision |
| Faible adoption | Investissement perdu | Ambassadeurs par service, formation, cas d'usage concrets dès le pilote |
| Obsolescence des modèles | Qualité en retard | API compatible OpenAI : changement de modèle sans réécriture, revue semestrielle |
| Dépendance à une personne clé | Arrêt du service | Infrastructure en code (IaC), documentation, binôme sur chaque brique |

## Questions ouvertes pour affiner

Vos réponses changent surtout le dimensionnement du matériel et le choix des connecteurs.

- [ ] Combien d'employés au total, et combien utiliseraient l'assistant chaque jour ?
- [ ] Quelle messagerie et quel agenda : Exchange on-premise, Microsoft 365, Google Workspace, autre ? Si c'est Microsoft 365 ou Google, les mails sont déjà hébergés chez eux : acceptez-vous que l'assistant les lise via leur API ?
- [ ] Où sont stockés les documents (partages réseau, SharePoint, Nextcloud, GED) et quel volume (Go, nombre de fichiers) ?
- [ ] Avez-vous une salle serveur ou un datacenter avec la puissance électrique nécessaire, ou faut-il un hébergeur ?
- [ ] Quel budget d'investissement et quelle échéance visez-vous ?
- [ ] Qui construira la solution : équipe interne (combien de personnes, quelles compétences) ou prestataire ?
- [ ] Secteur d'activité et données sensibles (santé, défense, données bancaires) imposant des contraintes particulières (HDS, SecNumCloud, diffusion restreinte) ?
- [ ] Faut-il un accès depuis l'extérieur (télétravail, mobile) via VPN ?
- [ ] Les modèles d'origine chinoise (Qwen, DeepSeek) sont-ils acceptables selon votre politique interne ?
- [ ] Quels types de rapports en priorité (commercial, technique, financier) et existe-t-il des modèles Word à respecter ?

## Sources

État des modèles open-weight vérifié en novembre 2026 ; à revérifier au moment de l'achat.

- [Best Open-Weight LLMs in 2026 – Sysart](https://sysart.consulting/insights/best-open-weight-llms-2026/)
- [Best Open Source LLMs 2026 – Uvik](https://uvik.net/blog/best-open-source-llms/)
- [Best Open Source LLMs for Coding to Self-Host – Pinggy](https://pinggy.io/blog/best_open_source_self_hosted_llms_for_coding/)
- [7 Best Open Source LLMs in 2026 – Prem AI](https://www.premai.io/blog/best-open-source-llms/)
- [Mistral Small 4 et Forge – Machine Herald](https://machineherald-io.pages.dev/article/2026-03/22-mistral-launches-small-4-and-forge-at-gtc-2026-as-open-weight-models-close-the-gap-with-proprietary-ai)
- [Mistral Medium 3.5 – Doolpa](https://doolpa.com/news/mistral-medium-3-5-128b-dense-open-weight-vibe-remote-agents-april-29-2026)
- [vLLM v0.28.0 – Hermes AI](https://hermes-ai.net/news/vllm-v0-28-0-ships-sparse-attention-and-60-faster-speculative-decoding/)
