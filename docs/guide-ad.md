# Guide AD : raccorder l'assistant IA à Active Directory

Pour l'administrateur de l'annuaire. Keycloak lit l'AD en **lecture seule** via LDAPS : il
n'y écrit jamais, et aucun schéma ni GPO n'est à modifier.

> **État :** cette intégration n'a **jamais été testée contre un vrai AD** ; seul l'import de
> sa configuration l'a été. Les comportements marqués *(à confirmer)* sont à contrôler sur un
> compte de test avant l'ouverture.

Les noms ci-dessous sont des exemples : `exemple.local`, `OU=IA`, `ia.exemple.local`.

## 1. Préparer l'annuaire

### Groupes

Placez-les dans une **OU dédiée**. Keycloak importe tous les groupes situés sous
`ia_ldap_groups_dn`, puis Open WebUI les recrée : pointer vers une OU générale y ferait
apparaître tous les groupes de l'entreprise.

| Groupe | Effet |
|---|---|
| `GG_IA_Utilisateurs` | Accès à l'assistant |
| `GG_IA_Admins` | Administrateur d'Open WebUI et accès à Grafana |

**Un administrateur doit aussi être couvert par le filtre d'import.** D'où l'imbrication
ci-dessous : les membres de `GG_IA_Admins` deviennent membres de `GG_IA_Utilisateurs`.

```powershell
New-ADOrganizationalUnit -Name "IA" -Path "DC=exemple,DC=local"
New-ADOrganizationalUnit -Name "Groupes" -Path "OU=IA,DC=exemple,DC=local"
$ou = "OU=Groupes,OU=IA,DC=exemple,DC=local"
New-ADGroup -Name "GG_IA_Utilisateurs" -GroupScope Global -GroupCategory Security -Path $ou
New-ADGroup -Name "GG_IA_Admins" -GroupScope Global -GroupCategory Security -Path $ou
Add-ADGroupMember -Identity "GG_IA_Utilisateurs" -Members "GG_IA_Admins"
```

Le rôle d'administrateur de l'assistant donne des droits étendus, dont la lecture
des conversations dans la configuration actuelle : limitez ce groupe au strict nécessaire.

### Compte de service

Un compte standard, sans aucun droit supplémentaire : la lecture accordée par défaut aux
utilisateurs du domaine suffit, sauf si vos ACL la restreignent. Dans ce cas, accordez-lui
la lecture sur les OU des comptes et des groupes.

```powershell
New-ADUser -Name "svc-ia-ldap" -SamAccountName "svc-ia-ldap" `
  -Path "OU=Comptes de service,DC=exemple,DC=local" `
  -AccountPassword (Read-Host -AsSecureString "Mot de passe") `
  -Enabled $true -CannotChangePassword $true -PasswordNeverExpires $true
```

- **Mot de passe :** long, **lettres et chiffres uniquement**. Le fichier `.env` n'échappe pas
  les caractères comme `$`, `#`, les espaces ou les guillemets.
- **Durcissement :** interdisez-lui l'ouverture de session interactive, et notez sa rotation
  au calendrier, car il n'expire pas.

### Comptes employés

- Ils doivent se trouver sous `ia_ldap_users_dn`, sous-OU comprises.
- **`mail` doit être renseigné et unique** : Open WebUI et Langfuse identifient les personnes
  par cette adresse.
- `givenName` et `sn` sont repris pour l'affichage.
- Vérifiez les comptes sans adresse :

```powershell
Get-ADGroupMember "GG_IA_Utilisateurs" -Recursive | Get-ADUser -Properties mail |
  Where-Object { -not $_.mail } | Select-Object SamAccountName
```

## 2. LDAPS et réseau

- **Flux :** serveur central vers le contrôleur de domaine, en TCP/636. Le LDAP en clair est
  refusé par le contrôle `make check`.
- **Certificat :** le nom de `ia_ldap_url` doit figurer dans le certificat du contrôleur.
- **CA :** fournissez à l'équipe projet la CA qui a signé ce certificat, au format PEM. Le
  fichier va dans `ansible/inventories/<env>/files/ad-ca.crt`.

```powershell
certutil -ca.cert ad-ca.der
certutil -encode ad-ca.der ad-ca.crt
```

**Limite actuelle : un seul contrôleur de domaine.** Le pare-feu et la résolution de nom sont
figés sur `ia_ldap_ip`. Si ce contrôleur tombe, plus personne ne peut se connecter, et une
session ouverte continue jusqu'à son expiration. Le support de plusieurs contrôleurs reste à
ajouter.

### Vérifier avant le déploiement

Depuis le serveur central, ou une machine du même réseau :

```bash
openssl s_client -connect dc01.exemple.local:636 -CAfile ad-ca.crt -verify_return_error </dev/null

LDAPTLS_CACERT=ad-ca.crt ldapsearch -H ldaps://dc01.exemple.local:636 \
  -D "CN=svc-ia-ldap,OU=Comptes de service,DC=exemple,DC=local" -W \
  -b "OU=Employes,DC=exemple,DC=local" -s sub \
  "(memberOf:1.2.840.113556.1.4.1941:=CN=GG_IA_Utilisateurs,OU=Groupes,OU=IA,DC=exemple,DC=local)" \
  sAMAccountName mail
```

La recherche doit lister les membres du groupe, y compris ceux des groupes imbriqués.

## 3. Valeurs à transmettre

```yaml
ia_ldap_enabled: true
ia_ldap_url: ldaps://dc01.exemple.local:636
ia_ldap_ip: 10.20.0.10
ia_ldap_bind_dn: CN=svc-ia-ldap,OU=Comptes de service,DC=exemple,DC=local
ia_ldap_users_dn: OU=Employes,DC=exemple,DC=local
ia_ldap_groups_dn: OU=Groupes,OU=IA,DC=exemple,DC=local
ia_ldap_ca_file: "{{ inventory_dir }}/files/ad-ca.crt"
ia_ldap_user_filter: (memberOf:1.2.840.113556.1.4.1941:=CN=GG_IA_Utilisateurs,OU=Groupes,OU=IA,DC=exemple,DC=local)
ia_group_users: GG_IA_Utilisateurs
ia_group_admins: GG_IA_Admins
```

- Le mot de passe se transmet par un canal sûr et va dans le vault
  (`vault_ldap_bind_password`) : `make vault-edit ENV=prod`.
- Évitez les antislashs et les guillemets dans ces valeurs : elles sont écrites sans
  échappement dans la configuration de Keycloak.
- **Tout doit être juste au premier déploiement.** Le royaume n'est créé qu'une fois : ensuite,
  ces réglages se changent dans la console Keycloak (Fédération d'utilisateurs > annuaire),
  et l'inventaire doit être mis à jour en parallèle.

## 4. Contrôler le raccordement

1. `make verify ENV=prod` : lance une synchronisation complète et affiche son résultat.
2. Sur `https://sso.<domaine>/admin` (réseaux d'administration), royaume `ia` : vérifiez
   **Utilisateurs** et **Groupes**. Seuls les membres et les groupes attendus doivent y figurer.
3. Déroulez ce test avec deux comptes, l'un utilisateur, l'autre administrateur :

| Test | Résultat attendu |
|---|---|
| Première connexion | Enrôlement OTP imposé |
| Compte administrateur | Rôle administrateur dans Open WebUI, accès à Grafana |
| Compte utilisateur | Rôle utilisateur, Grafana refusé |
| Compte hors du groupe | Connexion refusée |
| Compte AD désactivé | Connexion refusée *(à confirmer)* |
| Retrait du groupe | Connexion refusée à la tentative suivante *(à confirmer)* |
| Mot de passe AD changé | L'ancien est refusé, le nouveau accepté *(à confirmer)* |
| « Doit changer le mot de passe » | Annuaire en lecture seule : changement à faire d'abord sous Windows *(à confirmer)* |

## 5. Gestes courants

| Besoin | Geste | Délai |
|---|---|---|
| Donner l'accès | Ajouter au groupe `GG_IA_Utilisateurs` | Dès la connexion, au plus 5 min pour apparaître dans la synchronisation |
| Donner le rôle d'admin | Ajouter à `GG_IA_Admins` | À la connexion suivante de la personne |
| Retirer l'accès | Retirer du groupe | Nouvelles connexions ; voir ci-dessous pour les sessions |
| Départ | Désactiver le compte AD | Nouvelles connexions ; voir ci-dessous pour les sessions |
| Téléphone perdu | Keycloak, royaume `ia` > Utilisateurs > la personne > Identifiants : supprimer l'OTP | Nouvel enrôlement à la connexion suivante |
| Compte Keycloak bloqué | Se débloque seul, en 15 minutes au plus | Effacement possible dans la fiche de l'utilisateur |

**Les sessions ouvertes ne sont pas coupées par l'AD.** Une session Open WebUI reste valable
jusqu'à 8 h (`ia_session_lifetime`). Pour un départ sensible : désactivez le compte, fermez
ses sessions dans Keycloak et supprimez le compte dans Open WebUI (voir `exploitation.md`).

**Verrouillage :** chaque mauvais mot de passe saisi dans l'assistant est transmis à l'AD et
compte pour sa politique de verrouillage. Keycloak applique aussi la sienne : temporisation
après 5 échecs.

## 6. Changer le mot de passe du compte de service

Modifier le vault ne suffit pas : Keycloak a enregistré le mot de passe en base à la création
du royaume. Pour limiter la coupure, enchaînez :

1. Changer le mot de passe dans l'AD. Les connexions échouent à partir de cet instant.
2. Le reporter dans la console Keycloak : Fédération d'utilisateurs > annuaire > mot de passe
   de liaison, puis tester l'authentification.
3. Le reporter dans le vault : `make vault-edit ENV=prod`.

## 7. Compte de secours

Le compte local `admin` de Keycloak ne dépend pas de l'AD et reste utilisable si l'annuaire
est en panne. Il n'est **pas soumis à la MFA** : la console n'est joignable que depuis
`ia_admin_cidrs`, et son mot de passe doit rester dans le vault.

## 8. Dépannage

| Symptôme | Piste |
|---|---|
| Synchronisation en échec | `docker compose -p core logs keycloak` sur le serveur central, dans `/srv/ia/core` |
| Erreur de certificat | Nom absent du certificat, ou mauvaise CA dans `ad-ca.crt` |
| Délai dépassé | Flux 636 fermé, ou `ia_ldap_ip` erroné : `sudo nft list table inet ia_guard` |
| Erreur `49` / identifiants invalides | DN ou mot de passe du compte de service |
| Aucun utilisateur importé | `ia_ldap_users_dn` ou filtre : rejouer le `ldapsearch` ci-dessus |
| Connexion sans groupe ni rôle | Groupe hors de `ia_ldap_groups_dn`, ou nom différent de `ia_group_users` et `ia_group_admins` |
| Compte sans adresse | Renseigner `mail`, puis synchroniser |
