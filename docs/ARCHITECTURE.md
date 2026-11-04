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
La carte affiche alors le badge 🔥 HOT, un **encadrement de flammes animé**
(`FlameBorder`) et un halo orange. Le compteur est mis à jour en temps réel.

## Le panier dynamique (pièces uniques)

C'est le cœur du problème : deux personnes peuvent avoir la même pièce unique dans
leur panier, mais une seule peut l'acheter.

1. **Achat atomique côté serveur** — `purchase_garments` (voir
   `backend/supabase/schema.sql`) verrouille les lignes avec `SELECT … FOR UPDATE`.
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

## Paiement (production)

1. L'app demande à une **Edge Function** `create-payment` un `PaymentIntent` Stripe
   (capture manuelle) pour le total. Apple Pay passe par le même flux.
2. Après autorisation, l'Edge Function appelle `purchase_garments(...)` avec la clé
   `service_role`.
3. Elle **capture** uniquement le montant des pièces obtenues (ou annule
   l'autorisation si tout a été vendu).

Aucun numéro de carte ne transite par l'app ni par la base : le formulaire de démo ne
conserve que la marque et les 4 derniers chiffres.

## Brancher le vrai backend

1. Créer un projet Supabase et exécuter `backend/supabase/schema.sql`.
2. Ajouter le package Swift `supabase-swift` dans Xcode.
3. Écrire `SupabaseMarketplaceService: MarketplaceService` :
   * `feed` → `rpc("feed")` + filtres ;
   * `addToCart` / `removeFromCart` → insert / delete sur `cart_items` (+ `swipes`) ;
   * `purchase` → appel de l'Edge Function de paiement ;
   * `events` → canal Realtime sur `garments` et `orders`, converti en
     `AsyncStream<MarketplaceEvent>`.
4. Dans `StyleMatchApp.swift`, remplacer `MockMarketplaceService()` par le nouveau
   service. Aucune vue n'a besoin d'être modifiée.

## Pistes pour la suite

* Authentification (Sign in with Apple) et profils synchronisés.
* Notifications push : « une pièce de ton panier devient HOT », « vendue ».
* Réservation de 10 min pendant le paiement (`status = 'reserved'`).
* Côté vendeur : mise en ligne d'une pièce avec photos.
* Tests unitaires sur `AppStore` avec un service simulé déterministe.
