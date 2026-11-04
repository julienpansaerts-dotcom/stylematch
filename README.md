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
- Pièce très demandée ⇒ badge **🔥 HOT** + **encadrement de flammes animé** autour de la carte.
- Tap à gauche / à droite de la photo pour faire défiler les photos (comme Tinder).
- Tap sur la carte ⇒ **fiche détaillée** avec toutes les photos, miniatures, description, mesures, vendeur.
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

## Mode démo

L'application tourne pour l'instant avec un **backend simulé** (`MockMarketplaceService`) et
32 pièces de démonstration. Les autres acheteurs sont simulés :
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
├── Services/       MarketplaceService (contrat backend), service de démo, catalogue
├── Store/          AppStore : état global et logique métier
├── Views/
│   ├── Discover/   Pile de swipe, carte, fiche détaillée
│   ├── Filters/    Menu des filtres
│   ├── Cart/       Panier dynamique
│   ├── Checkout/   Paiement / achat express
│   ├── Profile/    Profil, formulaires, commandes et suivi
│   └── Components/ Flammes, badges, boutons, photos…
└── Resources/      Icône et couleurs
backend/supabase/schema.sql   Base de données, achat atomique, temps réel
docs/ARCHITECTURE.md          Fonctionnement détaillé et passage en production
```

## Passer en production

Voir [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) : backend Supabase (PostgreSQL + Realtime),
achat atomique des pièces uniques, paiement Stripe / Apple Pay, puis remplacement du service
simulé par le vrai service — **sans toucher aux écrans**.
