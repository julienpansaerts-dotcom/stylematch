-- =====================================================================
-- StyleMatch — schéma backend (Supabase / PostgreSQL)
-- =====================================================================
-- Ce fichier décrit le backend « réel » qui remplacera le service simulé
-- (MockMarketplaceService) de l'application iOS.
--
-- Point clé : chaque vêtement est une PIÈCE UNIQUE. L'achat doit donc être
-- atomique (une seule personne peut l'acheter) et, dès qu'il est vendu,
-- il doit disparaître du panier de tous les autres utilisateurs en temps réel.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------
create type gender          as enum ('women', 'men', 'unisex');
create type garment_status  as enum ('available', 'reserved', 'sold');
create type delivery_method as enum ('home', 'relayPoint');
create type order_status    as enum ('confirmed', 'preparing', 'shipped', 'inTransit', 'outForDelivery', 'delivered');
create type swipe_direction as enum ('left', 'right', 'up');

-- ---------------------------------------------------------------------
-- Profils (1 ligne par utilisateur authentifié)
-- ---------------------------------------------------------------------
create table profiles (
    id                 uuid primary key references auth.users on delete cascade,
    first_name         text,
    last_name          text,
    phone              text,
    address_line1      text,
    address_line2      text,
    postal_code        text,
    city               text,
    country            text default 'France',
    delivery_method    delivery_method default 'home',
    relay_point        text,
    -- Le paiement est délégué à Stripe : on ne stocke qu'un identifiant client.
    stripe_customer_id text,
    created_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Vêtements (pièces uniques)
-- Un seul vendeur : la boutique StyleMatch. Les pièces sont mises en ligne
-- par l'administrateur (clé service_role), jamais par les utilisateurs.
-- ---------------------------------------------------------------------
create table garments (
    id             uuid primary key default gen_random_uuid(),
    title          text not null,
    brand          text,
    summary        text,          -- court descriptif affiché sur la carte
    details        text,          -- description complète
    measurements   text,
    size           text not null,
    gender         gender not null,
    category       text not null, -- tshirts, shirts, knitwear, …
    condition      text not null, -- newWithTags, veryGood, …
    color          text,
    price_cents    integer not null check (price_cents > 0),
    photos         text[] not null default '{}', -- URLs Supabase Storage
    status         garment_status not null default 'available',
    reserved_by    uuid references auth.users,
    reserved_until timestamptz,
    cart_count     integer not null default 0,   -- alimente l'indicateur HOT
    created_at     timestamptz not null default now(),
    sold_at        timestamptz
);

create index garments_feed_idx on garments (status, category, gender, size);

-- ---------------------------------------------------------------------
-- Paniers
-- ---------------------------------------------------------------------
create table cart_items (
    user_id    uuid not null references auth.users on delete cascade,
    garment_id uuid not null references garments on delete cascade,
    added_at   timestamptz not null default now(),
    primary key (user_id, garment_id)
);

create index cart_items_garment_idx on cart_items (garment_id);

-- ---------------------------------------------------------------------
-- Historique des swipes (pour ne jamais remontrer un vêtement liké,
-- et pour pouvoir « revoir les vêtements passés »)
-- ---------------------------------------------------------------------
create table swipes (
    user_id    uuid not null references auth.users on delete cascade,
    garment_id uuid not null references garments on delete cascade,
    direction  swipe_direction not null,
    created_at timestamptz not null default now(),
    primary key (user_id, garment_id)
);

-- ---------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------
-- Compteur qui augmente de 1 à chaque commande : deux commandes ne peuvent
-- jamais recevoir le même numéro (contrairement à un tirage aléatoire).
create sequence order_number_seq;

create table orders (
    id                 uuid primary key default gen_random_uuid(),
    number             text unique not null default ('SM-' || lpad(nextval('order_number_seq')::text, 6, '0')),
    buyer_id           uuid not null references auth.users,
    subtotal_cents     integer not null,
    shipping_cents     integer not null,
    service_fee_cents  integer not null,
    delivery_method    delivery_method not null,
    shipping_address   jsonb not null,
    relay_point        text,
    carrier            text,
    tracking_number    text,
    status             order_status not null default 'confirmed',
    stripe_payment_intent text,
    created_at         timestamptz not null default now()
);

create table order_items (
    order_id    uuid not null references orders on delete cascade,
    garment_id  uuid not null unique references garments, -- UNIQUE : une pièce = une seule commande
    price_cents integer not null,
    primary key (order_id, garment_id)
);

create table order_events (
    id         bigserial primary key,
    order_id   uuid not null references orders on delete cascade,
    status     order_status not null,
    created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Compteur « nombre de paniers » (indicateur HOT) maintenu par trigger
-- ---------------------------------------------------------------------
create or replace function sync_cart_count() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if tg_op = 'INSERT' then
        update garments set cart_count = cart_count + 1 where id = new.garment_id;
    elsif tg_op = 'DELETE' then
        update garments set cart_count = greatest(cart_count - 1, 0) where id = old.garment_id;
    end if;
    return null;
end $$;

create trigger cart_items_count
after insert or delete on cart_items
for each row execute function sync_cart_count();

-- ---------------------------------------------------------------------
-- PRIX : seule source de vérité
-- ---------------------------------------------------------------------
-- L'app n'a aucune règle de prix codée en dur : elle affiche le devis renvoyé
-- par quote_garments(), calculé avec les mêmes fonctions que l'achat.
create or replace function shipping_cents(p_method delivery_method) returns integer
language sql immutable as $$
    select case p_method when 'home' then 490 else 290 end;
$$;

-- Protection acheteur : 0,70 € + 5 % du sous-total.
create or replace function service_fee_cents(p_subtotal integer) returns integer
language sql immutable as $$
    select case when p_subtotal = 0 then 0 else 70 + p_subtotal * 5 / 100 end;
$$;

create or replace function quote_garments(p_garment_ids uuid[]) returns jsonb
language sql stable security invoker set search_path = public as $$
    with available as (
        select id, price_cents from garments
         where id = any(p_garment_ids) and status = 'available'
    ), totals as (
        select coalesce(sum(price_cents), 0)::integer as subtotal from available
    )
    select jsonb_build_object(
        'subtotal_cents',    t.subtotal,
        'shipping_cents',    jsonb_build_object('home', shipping_cents('home'), 'relayPoint', shipping_cents('relayPoint')),
        'service_fee_cents', service_fee_cents(t.subtotal),
        'unavailable',       coalesce((select jsonb_agg(g) from unnest(p_garment_ids) g
                                       where g not in (select id from available)), '[]'::jsonb)
    )
    from totals t;
$$;

-- ---------------------------------------------------------------------
-- ACHAT ATOMIQUE
-- ---------------------------------------------------------------------
-- Appelée par l'Edge Function de paiement APRÈS l'autorisation Stripe
-- (PaymentIntent en capture manuelle). Si une pièce n'est plus disponible,
-- elle est exclue et le montant capturé est ajusté : l'acheteur n'est
-- jamais débité pour une pièce qu'il n'a pas obtenue.
-- ---------------------------------------------------------------------
create or replace function purchase_garments(
    p_buyer           uuid,
    p_garment_ids     uuid[],
    p_delivery_method delivery_method,
    p_address         jsonb,
    p_relay_point     text,
    p_payment_intent  text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
    v_bought      uuid[];
    v_unavailable uuid[];
    v_subtotal    integer;
    v_shipping    integer;
    v_fee         integer;
    v_order_id    uuid;
begin
    -- 1. Verrouille les lignes (ordre déterministe => pas d'interblocage).
    --    Deux acheteurs simultanés : le second attend que le premier ait fini,
    --    puis voit la pièce « sold ».
    perform 1 from garments where id = any(p_garment_ids) order by id for update;

    -- 2. Sépare les pièces encore disponibles des autres.
    select coalesce(array_agg(id), '{}') into v_bought
    from garments
    where id = any(p_garment_ids)
      and (status = 'available' or (status = 'reserved' and reserved_by = p_buyer));

    select coalesce(array_agg(g), '{}') into v_unavailable
    from unnest(p_garment_ids) as g
    where not (g = any(v_bought));

    if cardinality(v_bought) = 0 then
        return jsonb_build_object('order_id', null, 'unavailable', v_unavailable);
    end if;

    -- 3. Marque comme vendues.
    update garments
       set status = 'sold', sold_at = now(), reserved_by = null, reserved_until = null
     where id = any(v_bought);

    -- 4. Retire ces pièces du panier de TOUS les utilisateurs.
    --    Les clients abonnés au canal Realtime « garments » reçoivent l'UPDATE
    --    (status = sold) et affichent « Trop tard ! ».
    delete from cart_items where garment_id = any(v_bought);

    -- 5. Crée la commande.
    select sum(price_cents) into v_subtotal from garments where id = any(v_bought);
    v_shipping := shipping_cents(p_delivery_method);
    v_fee      := service_fee_cents(v_subtotal);

    insert into orders (buyer_id, subtotal_cents, shipping_cents, service_fee_cents,
                        delivery_method, shipping_address, relay_point, carrier, stripe_payment_intent)
    values (p_buyer, v_subtotal, v_shipping, v_fee, p_delivery_method, p_address, p_relay_point,
            case when p_delivery_method = 'home' then 'Colissimo' else 'Mondial Relay' end,
            p_payment_intent)
    returning id into v_order_id;

    insert into order_items (order_id, garment_id, price_cents)
    select v_order_id, id, price_cents from garments where id = any(v_bought);

    insert into order_events (order_id, status) values (v_order_id, 'confirmed');

    return jsonb_build_object(
        'order_id', v_order_id,
        'bought', v_bought,
        'unavailable', v_unavailable,
        'total_cents', v_subtotal + v_shipping + v_fee
    );
end $$;

-- Seul le backend (service_role, via l'Edge Function de paiement) peut acheter.
revoke all on function purchase_garments(uuid, uuid[], delivery_method, jsonb, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Fil de swipe : pièces disponibles jamais swipées par l'utilisateur
-- ---------------------------------------------------------------------
create or replace function feed(p_limit integer default 20)
returns setof garments
language sql stable security invoker set search_path = public as $$
    select g.*
      from garments g
     where g.status = 'available'
       and not exists (select 1 from swipes s where s.user_id = auth.uid() and s.garment_id = g.id)
       and not exists (select 1 from cart_items c where c.user_id = auth.uid() and c.garment_id = g.id)
     order by g.created_at desc
     limit p_limit;
$$;

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table profiles     enable row level security;
alter table garments     enable row level security;
alter table cart_items   enable row level security;
alter table swipes       enable row level security;
alter table orders       enable row level security;
alter table order_items  enable row level security;
alter table order_events enable row level security;

create policy "profil : lecture/écriture par son propriétaire"
    on profiles for all using (id = auth.uid()) with check (id = auth.uid());

create policy "vêtements : lecture pour tous les utilisateurs connectés"
    on garments for select to authenticated using (true);

create policy "panier : lecture de son panier"
    on cart_items for select using (user_id = auth.uid());

create policy "panier : ajout d'une pièce disponible uniquement"
    on cart_items for insert with check (
        user_id = auth.uid()
        and exists (select 1 from garments g where g.id = garment_id and g.status = 'available')
    );

create policy "panier : retrait de ses pièces"
    on cart_items for delete using (user_id = auth.uid());

create policy "swipes : gestion de ses swipes"
    on swipes for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "commandes : lecture de ses commandes"
    on orders for select using (buyer_id = auth.uid());

create policy "articles de commande : lecture de ses commandes"
    on order_items for select using (
        exists (select 1 from orders o where o.id = order_id and o.buyer_id = auth.uid())
    );

create policy "suivi : lecture de ses commandes"
    on order_events for select using (
        exists (select 1 from orders o where o.id = order_id and o.buyer_id = auth.uid())
    );

-- ---------------------------------------------------------------------
-- Temps réel
-- ---------------------------------------------------------------------
-- L'app s'abonne :
--   • garments  UPDATE → status = 'sold'  : retirer de la pile / du panier
--   • garments  UPDATE → cart_count       : mettre à jour l'indicateur HOT
--   • orders    UPDATE (buyer_id = moi)   : suivi de livraison
alter publication supabase_realtime add table garments, orders, order_events;
