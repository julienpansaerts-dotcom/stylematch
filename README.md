# StyleMatch 🔥

Application **iPhone native** (SwiftUI) de vente de vêtements de seconde main, où chaque
pièce est **unique**, basée sur un système de swipe à la Tinder.

| Geste | Action |
|---|---|
| ← Swipe à gauche | On passe le vêtement |
| → Swipe à droite | On l'ajoute au panier |
| ↑ Swipe vers le haut | On l'achète directement (achat express) |

## Fonctionnalités

### Découvrir (la pile)
- Carte principale avec **photos**, **taille**, **marque**, **état**, **prix**, **court descriptif**
  et **nombre de personnes qui l'ont dans leur panier**.
- Pièce très demandée ⇒ autocollant **🔥 HOT** + **encadré cel-shading** (contour épais, aplats orange/jaune,
  ombre dure) autour de la carte. Toute l'interface suit ce style « jeu » : boutons qui s'enfoncent, contours d'encre.
- Tap à gauche / à droite de la photo pour faire défiler les photos (comme Tinder).
- Tap sur la carte ⇒ **fiche détaillée** avec toutes les photos, miniatures, description, mesures.
- Une seule boutique vend toutes les pièces : pas de vendeurs particuliers.
- Boutons : ↩︎ retour (annule le dernier swipe), ✕ passer, ⚡️ acheter, 🛍 panier.
- Bouton **⟲ « Revoir les vêtements passés »** : remet dans la pile les pièces passées encore
  disponibles, **sans jamais remontrer celles déjà likées**.

### Filtres
Genre (Homme / Femme / Unisexe), catégories (T-shirts, chemises, pulls, sweats, vestes, manteaux,
jeans, pantalons, shorts, robes, jupes, chaussures, sacs, accessoires), tailles (XS→XXL, W26→W36,
35→46, taille unique), état, couleurs, fourchette de prix, « uniquement les pièces HOT ».

### Panier dynamique
- Achat **pièce par pièce** ou **tout le panier en un seul coup** (une seule livraison).
- Indique combien d'autres personnes veulent la même pièce.
- **Quand quelqu'un d'autre achète une pièce de ton panier, elle disparaît en direct** :
  bandeau « Trop tard… 💔 », vibration, et section « vendues entre-temps ».
- Si une pièce est vendue pendant ton paiement, elle est retirée de la commande et tu n'es pas débité.

### Profil
- Informations personnelles, adresse et mode de livraison (domicile / point relais),
  moyen de paiement (carte, Apple Pay, PayPal).
- **Mes commandes** : vêtements achetés et **suivi de livraison** (confirmée → en préparation →
  expédiée → en transit → en livraison → livrée) avec numéro de suivi.

## Tester sur iPhone avec TestFlight (sans Mac)

Le workflow GitHub Actions **TestFlight** compile l'app sur un Mac dans le cloud et
l'envoie sur TestFlight. Configuration pas à pas (une seule fois) :
[`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md).

## Lancer l'application avec Xcode

**Prérequis :** un Mac avec **Xcode 26 ou plus récent**. L'app cible **iOS 17+**.

1. Cloner le dépôt :
   ```bash
   git clone https://github.com/julienpansaerts-dotcom/stylematch.git
   ```
2. Ouvrir `StyleMatch.xcodeproj` dans Xcode.
3. Choisir un simulateur iPhone (ex. iPhone 16) et appuyer sur **▶︎ Run** (⌘R).

**Sur ton propre iPhone :** dans Xcode, cible *StyleMatch* › *Signing & Capabilities*, choisis ton
*Team* (ton identifiant Apple suffit), puis sélectionne ton iPhone comme destination. Si le
bundle identifier `stylematch` est refusé, remplace-le par un identifiant unique.

## Vrai serveur ou mode démo

- **Avec Supabase et Stripe configurés** (voir [`docs/PRODUCTION.md`](docs/PRODUCTION.md)) : vrais
  comptes (Apple ou code par e-mail), vrai catalogue publié depuis l'onglet **Boutique**, paniers
  partagés en temps réel, paiement par carte / Apple Pay via Stripe, suivi des commandes.
- **Sinon, mode démo** : l'app tourne avec un serveur simulé (`MockMarketplaceService`), un compte
  boutique de démonstration et 32 pièces. Les autres acheteurs sont simulés :
- des pièces sont ajoutées aux paniers en continu (le compteur bouge, des pièces deviennent HOT) ;
- environ toutes les 45 secondes, quelqu'un achète une pièce — parfois une pièce de **ton** panier,
  pour voir le « Trop tard ! » en action ;
- les commandes avancent dans leur suivi de livraison toutes les ~20 secondes.

Astuce paiement démo : carte `4242 4242 4242 4242`, date `12/30`, CVC `123`.

Les photos sont des visuels générés (dégradé de la couleur du vêtement + pictogramme) ;
le modèle supporte déjà les vraies photos (`PhotoSource.remote(URL)`).

## Structure du projet

```
StyleMatch.xcodeproj
StyleMatch/
├── App/            Point d'entrée, barre d'onglets, bandeaux de notification
├── Models/         Garment, FeedFilters, UserProfile, Order, Pricing
├── Config/         AppConfig : URL et clés publiques du backend
├── Services/       Contrat backend, Supabase, Stripe, connexion, service de démo
├── Store/          AppStore : état global et logique métier
├── Views/
│   ├── Discover/   Pile de swipe, carte, fiche détaillée
│   ├── Filters/    Menu des filtres
│   ├── Cart/       Panier dynamique
│   ├── Checkout/   Paiement / achat express
│   ├── Profile/    Profil, formulaires, commandes et suivi
│   ├── Account/    Connexion (Apple, code e-mail)
│   ├── Admin/      Onglet Boutique : publier des pièces, expédier les commandes
│   └── Components/ Style cel-shading, badges, boutons, photos…
└── Resources/      Icône, couleurs, manifeste de confidentialité
supabase/migrations/          Base de données, réservations, droits, temps réel
supabase/functions/           Paiement Stripe, webhook, suppression de compte
supabase/tests/               Tests SQL du parcours d'achat
docs/PRODUCTION.md            Guide de mise en production pas à pas
docs/ARCHITECTURE.md          Fonctionnement détaillé
StyleMatchTests/              Tests unitaires (Swift Testing), lancés par la CI
```

## Tests

- **`iOS build & tests`** compile l'app et lance les tests unitaires sur un simulateur iPhone :
  panier dynamique, achat unique d'une pièce, annulation de swipe, filtres, devis serveur,
  connexion requise, synchronisation des swipes, publication d'une pièce, stockage chiffré.
- **`Backend tests`** applique la migration sur PostgreSQL et rejoue le parcours d'achat (réservations
  concurrentes, webhook rejoué, remboursement, droits de chaque rôle), et vérifie les fonctions Stripe.

## Passer en production

Suis [`docs/PRODUCTION.md`](docs/PRODUCTION.md) : Supabase, Stripe, connexion Apple, puis
`Deploy backend` et `TestFlight` depuis l'onglet Actions. Aucun outil à installer.
