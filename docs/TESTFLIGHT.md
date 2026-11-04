# Tester StyleMatch sur iPhone avec TestFlight (sans Xcode)

L'app est compilée, signée et envoyée sur TestFlight **par GitHub Actions** sur un Mac
dans le cloud (workflow `.github/workflows/testflight.yml`). Tu n'as besoin que d'un
navigateur et de ton iPhone.

> Toutes les étapes 1 à 6 sont à faire **une seule fois**.

## 1. Compte Apple Developer (obligatoire)

TestFlight nécessite l'**Apple Developer Program** (99 €/an) :
<https://developer.apple.com/programs/enroll/>
L'inscription peut prendre de quelques heures à 48 h.

## 2. Récupérer ton Team ID

<https://developer.apple.com/account> › **Membership details** › **Team ID**
(10 caractères, ex. `AB12CD34EF`).

## 3. Enregistrer l'identifiant de l'app

<https://developer.apple.com/account/resources/identifiers/list> › **+** ›
**App IDs** › **App** :

- Description : `StyleMatch`
- Bundle ID : **Explicit** › `com.pansaerts.stylematch`
- Aucune capability à cocher › **Register**

## 4. Créer l'app dans App Store Connect

<https://appstoreconnect.apple.com/apps> › **+** › **Nouvelle app** :

- Plateforme : **iOS**
- Nom : `StyleMatch` (le nom doit être unique sur l'App Store ; s'il est pris,
  essaie par ex. `StyleMatch – Seconde main`, ça ne change rien au code)
- Langue principale : **Français**
- Identifiant de lot (Bundle ID) : `com.pansaerts.stylematch`
- SKU : `stylematch`
- Accès utilisateur : **Accès complet**

## 5. Créer une clé API App Store Connect

<https://appstoreconnect.apple.com/access/integrations/api> › **Clés d'équipe** ›
**Générer une clé API** (ou **+**) :

- Nom : `GitHub Actions`
- Accès : **Admin** (nécessaire pour que Apple gère les certificats de signature
  dans le cloud)

Puis :

- Note l'**Issuer ID** (en haut de la page) et le **Key ID** de la clé.
- **Télécharge** le fichier `AuthKey_XXXXXXXXXX.p8`. ⚠️ Apple ne le laisse
  télécharger **qu'une seule fois** : garde-le en lieu sûr.

## 6. Ajouter les secrets dans GitHub

Dans le dépôt GitHub › **Settings** › **Secrets and variables** › **Actions** ›
**New repository secret**, crée ces 4 secrets :

| Nom du secret | Valeur |
|---|---|
| `APPLE_TEAM_ID` | Ton Team ID (étape 2) |
| `ASC_KEY_ID` | Le Key ID (étape 5) |
| `ASC_ISSUER_ID` | L'Issuer ID (étape 5) |
| `ASC_KEY_P8` | Le **contenu complet** du fichier `.p8` : ouvre-le avec un éditeur de texte et copie tout, y compris les lignes `-----BEGIN PRIVATE KEY-----` et `-----END PRIVATE KEY-----` |

Ces secrets sont chiffrés par GitHub et ne sont jamais affichés dans les logs.

## 7. Lancer un envoi sur TestFlight

Dans le dépôt GitHub › onglet **Actions** › **TestFlight** › **Run workflow** ›
branche `main` › **Run workflow**.
(Ça marche aussi depuis l'app mobile GitHub.)

Le workflow n'apparaît dans l'onglet Actions qu'une fois **fusionné sur `main`**.

Durée : ~10 min de compilation, puis 10 à 30 min de traitement chez Apple.
Tu reçois un e-mail d'Apple quand le build est prêt.

## 8. Installer l'app sur ton iPhone

1. App Store Connect › ton app › **TestFlight** › **Tests internes** › **+** :
   crée un groupe (ex. `Moi`) et ajoute-toi comme testeur.
2. Installe l'app **TestFlight** depuis l'App Store sur ton iPhone.
3. Ouvre l'invitation reçue par e-mail (ou directement TestFlight) › **Installer**.

Les testeurs internes (jusqu'à 100 membres de ton équipe App Store Connect) n'ont
pas besoin de validation Apple. Pour inviter des amis par e-mail ou par lien public
(testeurs externes), Apple fait d'abord une courte vérification du build.

## Coût GitHub Actions

Le dépôt étant **privé**, chaque minute sur un Mac compte **×10** dans le quota
gratuit de GitHub (2 000 min/mois pour un compte gratuit). Un envoi TestFlight
consomme environ 100 à 150 minutes de quota. Le workflow ne se lance que quand tu
cliques sur **Run workflow**.

## En cas d'erreur

Ouvre le run en échec dans l'onglet **Actions** : le nom de l'étape rouge indique
où ça bloque.

- **Vérifier les secrets** : un des 4 secrets manque ou est mal nommé.
- **Exporter et envoyer** avec `No profiles` / `not authorized` : vérifie que la clé
  API a bien le rôle **Admin** et que l'app (étape 4) existe avec le bon Bundle ID.
- **Exporter et envoyer** avec `bundle version must be higher` : relance simplement
  le workflow (le numéro de build est basé sur l'heure).
