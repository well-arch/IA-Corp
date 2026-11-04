# Déploiement

## 1. Serveurs à préparer

Ansible ne réinstalle pas le système : ces points se règlent à l'installation.

| | Central | GPU |
|---|---|---|
| Système | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| Mémoire et disque | 64 Go de RAM, NVMe 2 To | NVMe : 400 Go minimum pour les poids et les images |
| GPU | aucun | Profil `production` : 2 GPU de 80 à 96 Go. Profil `pilot` : 1 GPU de 96 Go |
| Chiffrement | `/srv/ia` sur LUKS | `/srv/ia` sur LUKS |

Sur les deux : un compte `ansible` avec clé SSH et `sudo` sans mot de passe, l'empreinte
SSH du serveur dans `known_hosts` du poste d'administration, et une IP fixe.

Le contrôle `make check` refuse un `/srv/ia` non chiffré. Attention au déverrouillage au
démarrage : prévoir un mécanisme (Clevis/Tang, TPM ou console distante), sinon le serveur
attend une phrase de passe après chaque redémarrage, y compris celui du pilote NVIDIA.

## 2. Valeurs à obtenir

| Qui | Quoi | Variable |
|---|---|---|
| Réseau | Sous-réseaux des postes et des administrateurs | `ia_user_cidrs`, `ia_admin_cidrs` |
| Réseau | DNS, NTP, proxy limité aux mises à jour | `ia_dns_servers`, `ia_ntp_servers`, `ia_http_proxy`, `ia_host_egress_allow` |
| Réseau | Noms DNS internes vers le serveur central : `assistant`, `sso`, `llm`, `grafana`, `langfuse` | `ia_domain` |
| AD | URL LDAPS et IP d'un contrôleur de domaine, CA de son certificat | `ia_ldap_url`, `ia_ldap_ip`, `ia_ldap_ca_file` |
| AD | Compte de service en **lecture seule** et son mot de passe | `ia_ldap_bind_dn`, `vault_ldap_bind_password` |
| AD | OU des comptes et des groupes | `ia_ldap_users_dn`, `ia_ldap_groups_dn` |
| AD | Deux groupes à créer : utilisateurs et administrateurs de l'assistant | `ia_group_users`, `ia_group_admins`, `ia_ldap_user_filter` |
| Sauvegarde | Dépôt restic hors du serveur, et les identifiants associés | `ia_backup_repository`, `ia_backup_env` |
| PKI | Facultatif : certificats de l'entreprise | `ia_tls_mode: provided` |

Sans AD pour l'instant : `ia_ldap_enabled: false`. Le royaume est alors créé sans annuaire,
et les comptes de test se créent à la main dans la console Keycloak.

Le serveur GPU doit pouvoir joindre `ia_fqdn` du serveur central et inversement : l'entrée
DNS de chaque hôte est à créer aussi.

## 3. Sorties réseau pendant l'installation

Le pare-feu interdit toute sortie de l'hôte, hors `ia_host_egress_allow`. Les paquets et les
images passent donc par l'une de ces deux voies, à déclarer dans cette liste :

- **Proxy** limité à `archive.ubuntu.com`, `download.docker.com`, `nvidia.github.io` et aux
  registres des images (`docker.io`, `quay.io`, `ghcr.io`, `cgr.dev`).
- **Miroirs internes** : `make mirror-images REGISTRY=reg.local/miroir/`, puis
  `ia_image_mirror`, `ia_docker_apt_url`, `ia_nvidia_apt_url`, etc.

Si la cible de sauvegarde est sur un autre réseau, y ajouter aussi son adresse et son port.

## 4. Poids des modèles

Le serveur GPU ne contacte jamais Hugging Face. Depuis un poste relié à Internet :

```bash
make models-download DIR=/disque/poids                     # tout le catalogue
make models-download DIR=/disque/poids MODELS="mistral_small_4 gemma_4_e4b bge_m3 bge_reranker"
make models-push DIR=/disque/poids HOST=ansible@10.60.0.20
```

Prévoir 95 Go pour le profil `production` et 60 Go pour `pilot`. Les révisions et les
empreintes sont figées dans `ansible/models/manifests/` ; le déploiement échoue si un fichier
diffère. Le contrôle ne couvre que les poids, pas les petits fichiers de configuration.

## 5. Déploiement

```bash
make check ENV=prod
make deploy ENV=prod
make verify ENV=prod
```

`make deploy` est rejouable. Le premier passage redémarre le serveur GPU pour charger le
pilote NVIDIA, et le chargement des modèles peut prendre plusieurs dizaines de minutes.

## 6. Après le premier déploiement

1. Distribuer la CA interne (`ansible/inventories/prod/pki/ca.crt`) aux postes par GPO, ou
   passer en `ia_tls_mode: provided`. **Sauvegarder `pki/ca.key` et le mot de passe du vault
   hors du dépôt.**
2. Se connecter à `https://assistant.<domaine>` avec un compte du groupe administrateur et
   enrôler l'OTP. Sur Open WebUI, les droits suivent les groupes AD à chaque connexion.
3. Dans Langfuse, se connecter avec le compte `ia_admin_email` : il est relié au compte
   d'initialisation. Les autres comptes n'ont aucun accès tant qu'ils ne sont pas invités.
4. Lancer une sauvegarde : `sudo systemctl start ia-backup`, puis tester une restauration.
