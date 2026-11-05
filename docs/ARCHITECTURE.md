# Architecture de StyleMatch

## Vue d'ensemble

```
┌──────────────────────────── App iOS (SwiftUI) ────────────────────────────┐
│                                                                            │
│  Vues (Views/)  ──lisent──▶  AppStore (@Observable, @MainActor)            │
│      │                          │   • pile de swipe, panier, commandes      │
│      └──actions (swipe, achat)─▶│   • profil + filtres (sauvegardés)        │
│                                 │   • notifications in-app                  │
│                                 ▼                                           │
│                    MarketplaceService (protocole)                           │
│                     │                          │                            │
│        MockMarketplaceService          (à venir) SupabaseMarketplaceService │
│        (démo en mémoire,               (REST + Realtime + Edge Functions)   │
│         simule les autres acheteurs)                                        │
└────────────────────────────────────────────────────────────────────────────┘
```

* **`Models/`** : types purs (`Garment`, `FeedFilters`, `UserProfile`, `Order`, `Pricing`).
* **`Services/`** : le protocole `MarketplaceService` (contrat avec le backend), son
  implémentation de démo et la persistance locale (profil + filtres).
* **`Store/AppStore.swift`** : toute la logique métier côté app. Les vues ne parlent
  jamais directement au service.
* **`Views/`** : un dossier par écran (`Discover`, `Filters`, `Cart`, `Checkout`,
  `Profile`) + des composants réutilisables (`Components`).

## Le swipe

| Geste | Bouton | Action |
|---|---|---|
| ← gauche | ✕ Passer | La pièce est ajoutée aux « passées » |
| → droite | 🛍 Panier | Ajout au panier (optimiste, confirmé par le serveur) |
| ↑ haut | ⚡️ Acheter | Ouvre l'achat express ; si annulé, la carte revient sur la pile |
| — | ↩︎ Retour | Annule le dernier swipe (gauche ou droite) |
| — | ⟲ (en-tête) | **Revoir les vêtements passés**, sans jamais remontrer ceux déjà likés ou achetés |

Sur la carte : tap à gauche / à droite = photo précédente / suivante (comme Tinder),
tap au centre ou sur les infos = fiche détaillée avec toutes les photos.

### Indicateur HOT

`Garment.isHot` est vrai dès que `cartCount >= Garment.hotThreshold` (8 par défaut).
La carte affiche alors l'autocollant 🔥 HOT et un **encadré cel-shading** (`HotFrame` :
contour d'encre, bandes d'aplats orange / jaune, ombre dure rouge). Ce style est statique :
aucune animation continue, donc pas de coût batterie. Le compteur est mis à jour en temps réel.

### Annulation et ordre des requêtes

Les appels panier d'un même vêtement sont **chaînés** (`AppStore.enqueueCartOperation`) :
si l'utilisateur annule un swipe à droite pendant que l'ajout est en route, le retrait
part forcément après l'ajout. Si l'ajout n'est pas encore parti, il est simplement abandonné.

Chaque rechargement de la pile incrémente un numéro de génération : un complément de pile
demandé avec les anciens filtres est ignoré s'il arrive après un changement de filtres.

## Le panier dynamique (pièces uniques)

C'est le cœur du problème : deux personnes peuvent avoir la même pièce unique dans
leur panier, mais une seule peut l'acheter.

1. **Achat atomique côté serveur** — `purchase_garments` (voir
   `supabase/migrations/`) verrouille les lignes avec `SELECT … FOR UPDATE`.
   Si deux acheteurs paient en même temps, le second attend puis voit la pièce
   « vendue ». La contrainte `UNIQUE (garment_id)` sur `order_items` empêche
   physiquement une double vente.
2. **Nettoyage des paniers** — dans la même transaction, la pièce est supprimée de
   `cart_items` pour **tous** les utilisateurs.
3. **Notification en temps réel** — l'app est abonnée aux changements de la table
   `garments`. L'événement `garmentSold` déclenche dans `AppStore.handle(_:)` :
   * retrait de la pièce de la pile (si c'est la carte du dessus, elle reste affichée
     avec un tampon **VENDU** pour ne pas disparaître sous le doigt) ;
   * retrait du panier + section « Trop tard… vendues entre-temps » ;
   * bandeau « Trop tard… 💔 » + vibration.
4. **Achat partiel** — en achetant tout le panier, si une pièce est vendue pendant le
   paiement, la commande est créée pour les autres et l'utilisateur n'est **pas
   débité** pour la pièce perdue (`PurchaseResult.unavailable`).

Dans le mode démo, `MockMarketplaceService` est un `actor` : l'isolation de l'acteur
joue le rôle du verrou de base de données, et une boucle simule les autres
utilisateurs (ajouts au panier toutes les 3‑6 s, un achat par un tiers environ toutes
les 45 s — parfois une pièce de **ton** panier — et l'avancement des livraisons).

## Prix : une seule source de vérité

L'app ne contient **aucune règle de prix**. L'écran de paiement demande un devis au serveur
(`MarketplaceService.quote`, `quote_garments` en SQL) et la commande est facturée avec les
mêmes fonctions (`shipping_cents`, `service_fee_cents`). Le total affiché est donc toujours
celui qui sera facturé. Un test vérifie que devis et commande donnent le même montant.

## Données personnelles

Le profil (nom, e-mail, adresse, 4 derniers chiffres de la carte) est stocké dans le
**trousseau iOS** (`KeychainStore`), chiffré et lié à l'appareil. Les anciennes versions qui
le stockaient en clair dans `UserDefaults` sont migrées automatiquement au lancement.

## Paiement

1. L'app appelle l'Edge Function **`create-payment`** : elle **réserve** les pièces
   15 minutes (`reserve_garments`) et crée un `PaymentIntent` Stripe du montant exact
   calculé par la base (mêmes fonctions que le devis).
2. L'app présente la **feuille de paiement Stripe** (carte ou Apple Pay).
3. Stripe appelle le webhook **`stripe-webhook`** : `finalize_payment` marque les pièces
   vendues, les retire de **tous** les paniers et crée la commande. Si une pièce a échappé
   à l'acheteur (réservation expirée puis rachetée), elle lui est remboursée.
4. L'app attend la commande puis l'affiche. Paiement abandonné : `cancel_my_payment`
   libère les pièces immédiatement (sinon elles se libèrent à l'expiration).

Aucun numéro de carte ne transite par l'app ni par la base.

## Connexion et rôles

* **Connexion** : « Se connecter avec Apple » (jeton + nonce) ou code à 6 chiffres
  reçu par e-mail (Supabase Auth). On peut parcourir la pile sans compte ; le panier
  et l'achat demandent de se connecter.
* **Boutique** : `profiles.is_admin = true` donne l'onglet *Boutique* (publier,
  modifier, retirer des pièces, expédier les commandes). La base l'impose par la RLS :
  un client ne peut ni publier ni se donner ce rôle.
* **Historique des swipes** stocké sur le serveur : une pièce likée ne revient jamais,
  même sur un autre iPhone.

## Mise en production

Voir [`PRODUCTION.md`](PRODUCTION.md).

## Pistes pour la suite

* Notifications push : « une pièce de ton panier devient HOT », « vendue », « expédiée ».
* Carte des points relais (API Mondial Relay) et étiquettes d'expédition automatiques.
* Statistiques de la boutique (pièces les plus likées, taux de conversion).
