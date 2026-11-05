# Mettre StyleMatch en production

Ce guide branche l'app sur le vrai serveur (**Supabase**) et les vrais paiements
(**Stripe**). Tout se fait dans le navigateur : les workflows GitHub déploient le
serveur et l'app à ta place.

> Ordre conseillé : étapes 1 à 7 en **mode test Stripe** (aucun vrai débit),
> tu testes sur TestFlight avec la carte `4242 4242 4242 4242`, puis l'étape 9 pour
> passer en paiements réels.

Tant que la configuration n'est pas faite, l'app reste en **mode démo**.

---

## 1. Supabase : récupérer les informations du projet

Dans ton projet sur <https://supabase.com/dashboard> :

| Information | Où la trouver |
|---|---|
| **Project ref** | *Project Settings › General › Project ID* (ex. `abcdwxyz…`) |
| **Project URL** | *Project Settings › Data API* (ex. `https://abcdwxyz.supabase.co`) |
| **Clé publique** | *Project Settings › API Keys* : la clé **publishable** (`sb_publishable_…`) ou, à défaut, la clé **anon** |
| **Mot de passe de la base** | celui choisi à la création (*Project Settings › Database › Reset password* si oublié) |
| **Access token** | <https://supabase.com/dashboard/account/tokens> › *Generate new token* |

⚠️ La clé **service_role** / **secret** ne doit jamais être mise dans l'app ni dans
GitHub : elle n'est utilisée que par le serveur, qui la connaît déjà.

## 2. Stripe (mode test)

Sur <https://dashboard.stripe.com>, active **Mode test** (en haut à droite), puis
*Développeurs › Clés API* :

- **Clé publiable** : `pk_test_…`
- **Clé secrète** : `sk_test_…`

## 3. GitHub : secrets et variables

Dans le dépôt : **Settings › Secrets and variables › Actions**.

**Onglet « Secrets »** (confidentiels) :

| Nom | Valeur |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | l'access token (étape 1) |
| `SUPABASE_DB_PASSWORD` | le mot de passe de la base |
| `SUPABASE_PROJECT_REF` | le project ref |
| `STRIPE_SECRET_KEY` | `sk_test_…` |
| `STRIPE_WEBHOOK_SECRET` | à l'étape 5 |

**Onglet « Variables »** (publiques, intégrées dans l'app) :

| Nom | Valeur |
|---|---|
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | la clé publishable / anon |
| `STRIPE_PUBLISHABLE_KEY` | `pk_test_…` |
| `APPLE_PAY_MERCHANT_ID` | facultatif, voir étape 8 |

## 4. Déployer le serveur

Onglet **Actions › Deploy backend › Run workflow** (branche `main`).

Le workflow crée les tables, les règles de sécurité, le stockage des photos et
déploie les fonctions de paiement. Le résumé du run affiche l'**URL du webhook**
Stripe (`https://<project-ref>.supabase.co/functions/v1/stripe-webhook`).

Il se relance tout seul à chaque modification du dossier `supabase/` sur `main`.

## 5. Stripe : webhook

*Développeurs › Webhooks › Ajouter une destination* :

- **URL** : l'URL du webhook ci-dessus
- **Événements** : `payment_intent.succeeded` et `payment_intent.canceled`

Copie le **secret de signature** (`whsec_…`) dans le secret GitHub
`STRIPE_WEBHOOK_SECRET`, puis relance **Deploy backend**.

## 6. Connexion des clients

### Code par e-mail

Supabase › *Authentication › Emails › Templates* › **Magic Link** : remplace le
contenu par un message qui contient le code, par exemple :

```html
<h2>Ton code StyleMatch</h2>
<p>Saisis ce code dans l'app : <strong>{{ .Token }}</strong></p>
<p>Il expire dans 1 heure.</p>
```

Fais de même pour le modèle **Confirm signup** (premier achat d'un nouvel e-mail).

Le service d'e-mail intégré à Supabase est limité à quelques envois par heure :
avant l'ouverture au public, configure un **SMTP** (*Authentication › Emails ›
SMTP Settings*, par exemple Brevo ou Resend, gratuits pour démarrer).

### Se connecter avec Apple

1. <https://developer.apple.com/account/resources/identifiers/list> › identifiant
   **stylematch** › coche **Sign In with Apple** › *Save*.
2. Supabase › *Authentication › Sign In / Providers › Apple* › active-le et mets
   `stylematch` dans **Client IDs**. Rien d'autre n'est nécessaire pour une app iOS.

## 7. Devenir la boutique, puis tester sur TestFlight

1. **Actions › TestFlight › Run workflow**.
2. Installe la nouvelle version via TestFlight et connecte-toi (Apple ou e-mail).
3. Supabase › *SQL Editor*, exécute (avec ton e-mail) :

   ```sql
   update profiles set is_admin = true where email = 'ton-email@exemple.com';
   ```

   Si tu t'es connecté avec Apple en masquant ton e-mail, utilise l'adresse
   `…@privaterelay.appleid.com` affichée dans le Profil de l'app.
4. Relance l'app : l'onglet **Boutique** apparaît. Publie tes premières pièces
   (photos depuis l'iPhone).
5. Achète une pièce avec la carte de test `4242 4242 4242 4242`, date future,
   CVC quelconque. La commande apparaît dans *Profil › Mes commandes* et dans
   *Boutique › Commandes*.

## 8. Apple Pay (facultatif)

1. <https://developer.apple.com/account/resources/identifiers/list/merchant> ›
   **+** › *Merchant IDs* › `merchant.stylematch`.
2. Stripe › *Paramètres › Moyens de paiement › Apple Pay* › **Ajouter un nouveau
   certificat** : télécharge le fichier CSR, envoie-le sur la page du Merchant ID
   (*Apple Pay Payment Processing Certificate › Create Certificate*), puis renvoie
   le certificat obtenu à Stripe.
3. Sur l'identifiant **stylematch**, coche **Apple Pay Payment Processing** et
   sélectionne `merchant.stylematch`.
4. Variable GitHub `APPLE_PAY_MERCHANT_ID` = `merchant.stylematch`, puis relance
   **TestFlight**. Le bouton Apple Pay apparaît dans la feuille de paiement.

## 9. Passer en paiements réels

1. Termine l'activation du compte Stripe (identité, activité, IBAN).
2. Désactive le **Mode test** et refais les étapes 2, 3 et 5 avec les clés
   `pk_live_…` / `sk_live_…` et un nouveau webhook en mode live.
3. Relance **Deploy backend** puis **TestFlight**.

## 10. Avant de publier sur l'App Store

Liste à vérifier (ce n'est pas un conseil juridique : fais-toi accompagner si besoin) :

- **Mentions légales, CGV et politique de confidentialité** accessibles en ligne :
  l'URL de la politique est obligatoire dans App Store Connect.
- **Droit de rétractation** de 14 jours pour la vente à distance par un professionnel,
  et conditions de retour.
- **Confidentialité de l'app** dans App Store Connect : données collectées =
  nom, e-mail, adresse postale, historique d'achats (liées à l'identité, non
  utilisées pour le suivi publicitaire).
- **Suppression du compte** : déjà disponible dans *Profil › Supprimer mon compte*.
- **Notes pour la revue Apple** : indique que la connexion se fait avec Apple
  (aucun compte de test nécessaire), et que les achats sont des biens physiques
  payés via Stripe (règle 3.1.3(e) : pas d'achat intégré).
- **Comptabilité / TVA** : les commandes et paiements sont dans Stripe
  (*Paiements*, exports CSV) et dans la table `orders` de Supabase.
