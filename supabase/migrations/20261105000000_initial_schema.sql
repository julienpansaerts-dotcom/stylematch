-- =====================================================================
-- StyleMatch — schéma de la base (Supabase / PostgreSQL)
-- =====================================================================
-- Chaque vêtement est une PIÈCE UNIQUE vendue par une seule boutique.
--
-- Parcours d'achat :
--   1. L'app appelle l'Edge Function `create-payment` ;
--   2. elle RÉSERVE les pièces (reserve_garments, 15 min) et crée un
--      PaymentIntent Stripe pour le montant exact ;
--   3. l'utilisateur paie dans la feuille de paiement Stripe (carte / Apple Pay) ;
--   4. le webhook Stripe appelle finalize_payment : les pièces passent
--      « vendues », disparaissent de TOUS les paniers et la commande est créée.
--   Paiement annulé / échoué / réservation expirée => les pièces redeviennent
--   disponibles.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------
create type gender            as enum ('women', 'men', 'unisex');
create type garment_status    as enum ('available', 'reserved', 'sold', 'withdrawn');
create type delivery_method   as enum ('home', 'relayPoint');
create type order_status      as enum ('confirmed', 'preparing', 'shipped', 'inTransit', 'outForDelivery', 'delivered');
create type swipe_direction   as enum ('left', 'right', 'up');
create type payment_state     as enum ('pending', 'succeeded', 'canceled');

-- Durée de réservation pendant le paiement.
create or replace function reservation_ttl() returns interval
language sql immutable as $$ select interval '15 minutes' $$;

-- ---------------------------------------------------------------------
-- Profils (créés automatiquement à l'inscription)
-- ---------------------------------------------------------------------
create table profiles (
    id               uuid primary key references auth.users on delete cascade,
    first_name       text not null default '',
    last_name        text not null default '',
    email            text not null default '',
    phone            text not null default '',
    address_line1    text not null default '',
    address_line2    text not null default '',
    postal_code      text not null default '',
    city             text not null default '',
    country          text not null default 'France',
    delivery_method  delivery_method not null default 'home',
    relay_point      text not null default '',
    -- Réservé à la boutique : passe à true à la main dans Supabase.
    is_admin         boolean not null default false,
    created_at       timestamptz not null default now()
);

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into profiles (id, email) values (new.id, coalesce(new.email, ''))
    on conflict (id) do nothing;
    return new;
end $$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function handle_new_user();

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
    select coalesce((select p.is_admin from profiles p where p.id = auth.uid()), false);
$$;

-- ---------------------------------------------------------------------
-- Vêtements (pièces uniques, publiées par la boutique)
-- ---------------------------------------------------------------------
create table garments (
    id             uuid primary key default gen_random_uuid(),
    title          text not null check (length(title) between 1 and 120),
    brand          text not null default '',
    summary        text not null default '',  -- court descriptif de la carte
    details        text not null default '',  -- description complète
    measurements   text,
    size           text not null,
    gender         gender not null,
    category       text not null,             -- tshirts, shirts, knitwear, …
    condition      text not null,             -- newWithTags, veryGood, …
    color          text not null,
    price_cents    integer not null check (price_cents > 0),
    photos         text[] not null default '{}', -- chemins dans le bucket garment-photos
    status         garment_status not null default 'available',
    reserved_by    uuid references auth.users on delete set null,
    reserved_until timestamptz,
    cart_count     integer not null default 0, -- alimente l'indicateur HOT
    created_at     timestamptz not null default now(),
    sold_at        timestamptz
);

create index garments_feed_idx on garments (status, category, gender, size);

-- Une pièce réservée dont la réservation a expiré est de nouveau en vente.
create or replace function is_purchasable(g garments, p_buyer uuid) returns boolean
language sql stable as $$
    select g.status = 'available'
        or (g.status = 'reserved' and (g.reserved_until < now() or g.reserved_by = p_buyer));
$$;

-- ---------------------------------------------------------------------
-- Paniers et historique des swipes
-- ---------------------------------------------------------------------
create table cart_items (
    user_id    uuid not null references auth.users on delete cascade,
    garment_id uuid not null references garments on delete cascade,
    added_at   timestamptz not null default now(),
    primary key (user_id, garment_id)
);
create index cart_items_garment_idx on cart_items (garment_id);

-- Les pièces likées ne reviennent jamais ; les pièces passées peuvent être
-- « revues » (la ligne est alors supprimée).
create table swipes (
    user_id    uuid not null references auth.users on delete cascade,
    garment_id uuid not null references garments on delete cascade,
    direction  swipe_direction not null,
    created_at timestamptz not null default now(),
    primary key (user_id, garment_id)
);

-- ---------------------------------------------------------------------
-- Commandes et paiements
-- ---------------------------------------------------------------------
-- Compteur qui augmente de 1 à chaque commande : deux commandes ne peuvent
-- jamais recevoir le même numéro.
create sequence order_number_seq;

create table orders (
    id                    uuid primary key default gen_random_uuid(),
    number                text unique not null default ('SM-' || lpad(nextval('order_number_seq')::text, 6, '0')),
    -- « set null » : la commande est conservée (comptabilité) si le client supprime son compte.
    buyer_id              uuid references auth.users on delete set null,
    buyer_name            text not null default '',
    subtotal_cents        integer not null,
    shipping_cents        integer not null,
    service_fee_cents     integer not null,
    delivery_method       delivery_method not null,
    shipping_address      jsonb not null,
    relay_point           text not null default '',
    carrier               text not null,
    tracking_number       text,
    status                order_status not null default 'confirmed',
    payment_summary       text not null default '',
    stripe_payment_intent text unique,
    created_at            timestamptz not null default now()
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

-- Paiement Stripe en cours (créé par create-payment, soldé par le webhook).
create table payments (
    payment_intent   text primary key,
    buyer_id         uuid references auth.users on delete set null,
    garment_ids      uuid[] not null,
    amount_cents     integer not null,
    delivery_method  delivery_method not null,
    shipping_address jsonb not null,
    relay_point      text not null default '',
    buyer_name       text not null default '',
    state            payment_state not null default 'pending',
    refunded_cents   integer not null default 0,
    order_id         uuid references orders on delete set null,
    created_at       timestamptz not null default now()
);

-- Chaque changement de statut d'une commande est historisé (suivi de livraison).
create or replace function log_order_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if tg_op = 'INSERT' or new.status is distinct from old.status then
        insert into order_events (order_id, status) values (new.id, new.status);
    end if;
    return new;
end $$;

create trigger orders_status_log
after insert or update of status on orders
for each row execute function log_order_status();

-- ---------------------------------------------------------------------
-- Compteur « nombre de paniers » (indicateur HOT)
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
-- PRIX : seule source de vérité (l'app affiche le devis, rien n'est codé côté iOS)
-- ---------------------------------------------------------------------
create or replace function shipping_cents(p_method delivery_method) returns integer
language sql immutable as $$
    select case p_method when 'home' then 490 else 290 end;
$$;

-- Protection acheteur : 0,70 € + 5 % du sous-total.
create or replace function service_fee_cents(p_subtotal integer) returns integer
language sql immutable as $$
    select case when p_subtotal = 0 then 0 else 70 + p_subtotal * 5 / 100 end;
$$;

create or replace function carrier_for(p_method delivery_method) returns text
language sql immutable as $$
    select case p_method when 'home' then 'Colissimo' else 'Mondial Relay' end;
$$;

create or replace function quote_garments(p_garment_ids uuid[]) returns jsonb
language sql stable security definer set search_path = public as $$
    with available as (
        select g.id, g.price_cents from garments g
         where g.id = any(p_garment_ids) and is_purchasable(g, auth.uid())
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
-- Fil de swipe : pièces en vente jamais swipées par l'utilisateur
-- ---------------------------------------------------------------------
create or replace function feed(
    p_limit      integer default 20,
    p_exclude    uuid[] default '{}',
    p_genders    text[] default '{}',
    p_categories text[] default '{}',
    p_sizes      text[] default '{}',
    p_conditions text[] default '{}',
    p_colors     text[] default '{}',
    p_min_cents  integer default 0,
    p_max_cents  integer default null,
    p_hot_only   boolean default false,
    p_hot_threshold integer default 8
) returns setof garments
language sql stable security invoker set search_path = public as $$
    select g.*
      from garments g
     where is_purchasable(g, auth.uid())
       and not (g.id = any(p_exclude))
       and not exists (select 1 from swipes s where s.user_id = auth.uid() and s.garment_id = g.id)
       and not exists (select 1 from cart_items c where c.user_id = auth.uid() and c.garment_id = g.id)
       and (cardinality(p_genders) = 0    or g.gender::text = any(p_genders))
       and (cardinality(p_categories) = 0 or g.category = any(p_categories))
       and (cardinality(p_sizes) = 0      or g.size = any(p_sizes))
       and (cardinality(p_conditions) = 0 or g.condition = any(p_conditions))
       and (cardinality(p_colors) = 0     or g.color = any(p_colors))
       and g.price_cents >= p_min_cents
       and (p_max_cents is null or g.price_cents <= p_max_cents)
       and (not p_hot_only or g.cart_count >= p_hot_threshold)
     order by g.created_at desc
     limit p_limit;
$$;

-- ---------------------------------------------------------------------
-- RÉSERVATION puis FINALISATION (appelées par les Edge Functions, service_role)
-- ---------------------------------------------------------------------
create or replace function reserve_garments(p_buyer uuid, p_garment_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
    v_reserved    uuid[];
    v_unavailable uuid[];
    v_subtotal    integer;
begin
    -- Verrouille les lignes (ordre déterministe => pas d'interblocage).
    -- Deux acheteurs simultanés : le second attend, puis voit la pièce réservée.
    perform 1 from garments where id = any(p_garment_ids) order by id for update;

    select coalesce(array_agg(g.id), '{}') into v_reserved
      from garments g
     where g.id = any(p_garment_ids) and is_purchasable(g, p_buyer);

    select coalesce(array_agg(x), '{}') into v_unavailable
      from unnest(p_garment_ids) as x
     where not (x = any(v_reserved));

    update garments
       set status = 'reserved', reserved_by = p_buyer, reserved_until = now() + reservation_ttl()
     where id = any(v_reserved);

    select coalesce(sum(price_cents), 0)::integer into v_subtotal from garments where id = any(v_reserved);

    return jsonb_build_object(
        'reserved',          v_reserved,
        'unavailable',       v_unavailable,
        'subtotal_cents',    v_subtotal,
        'service_fee_cents', service_fee_cents(v_subtotal)
    );
end $$;

create or replace function release_garments(p_buyer uuid, p_garment_ids uuid[]) returns void
language sql security definer set search_path = public as $$
    update garments
       set status = 'available', reserved_by = null, reserved_until = null
     where id = any(p_garment_ids) and status = 'reserved' and reserved_by = p_buyer;
$$;

-- Appelée par le webhook Stripe quand le paiement a réussi. Idempotente.
-- Retourne la commande créée et le montant à rembourser si une pièce a été
-- vendue entre-temps (réservation expirée puis rachetée : cas rarissime).
create or replace function finalize_payment(p_payment_intent text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
    v_payment   payments%rowtype;
    v_bought    uuid[];
    v_missing   uuid[];
    v_subtotal  integer;
    v_shipping  integer;
    v_fee       integer;
    v_order_id  uuid;
    v_refund    integer := 0;
begin
    select * into v_payment from payments where payment_intent = p_payment_intent for update;
    if not found then
        raise exception 'paiement inconnu: %', p_payment_intent;
    end if;
    if v_payment.state = 'succeeded' then
        return jsonb_build_object('order_id', v_payment.order_id, 'refund_cents', v_payment.refunded_cents, 'already_done', true);
    end if;

    perform 1 from garments where id = any(v_payment.garment_ids) order by id for update;

    select coalesce(array_agg(g.id), '{}') into v_bought
      from garments g
     where g.id = any(v_payment.garment_ids) and is_purchasable(g, v_payment.buyer_id);

    select coalesce(array_agg(x), '{}') into v_missing
      from unnest(v_payment.garment_ids) as x
     where not (x = any(v_bought));

    if cardinality(v_bought) = 0 then
        update payments set state = 'succeeded', refunded_cents = amount_cents where payment_intent = p_payment_intent;
        return jsonb_build_object('order_id', null, 'refund_cents', v_payment.amount_cents, 'missing', v_missing);
    end if;

    update garments
       set status = 'sold', sold_at = now(), reserved_by = null, reserved_until = null
     where id = any(v_bought);

    -- Retire ces pièces du panier de TOUS les utilisateurs (« Trop tard ! »).
    delete from cart_items where garment_id = any(v_bought);

    select sum(price_cents)::integer into v_subtotal from garments where id = any(v_bought);
    v_shipping := shipping_cents(v_payment.delivery_method);
    v_fee      := service_fee_cents(v_subtotal);
    v_refund   := greatest(v_payment.amount_cents - (v_subtotal + v_shipping + v_fee), 0);

    insert into orders (buyer_id, buyer_name, subtotal_cents, shipping_cents, service_fee_cents,
                        delivery_method, shipping_address, relay_point, carrier,
                        payment_summary, stripe_payment_intent)
    values (v_payment.buyer_id, v_payment.buyer_name, v_subtotal, v_shipping, v_fee,
            v_payment.delivery_method, v_payment.shipping_address, v_payment.relay_point,
            carrier_for(v_payment.delivery_method), 'Carte bancaire (Stripe)', p_payment_intent)
    returning id into v_order_id;

    insert into order_items (order_id, garment_id, price_cents)
    select v_order_id, id, price_cents from garments where id = any(v_bought);

    update payments
       set state = 'succeeded', order_id = v_order_id, refunded_cents = v_refund
     where payment_intent = p_payment_intent;

    return jsonb_build_object('order_id', v_order_id, 'refund_cents', v_refund, 'missing', v_missing);
end $$;

-- Paiement abandonné ou refusé : libère les pièces.
create or replace function cancel_payment(p_payment_intent text) returns void
language plpgsql security definer set search_path = public as $$
declare
    v_payment payments%rowtype;
begin
    select * into v_payment from payments where payment_intent = p_payment_intent for update;
    if not found or v_payment.state <> 'pending' then
        return;
    end if;
    perform release_garments(v_payment.buyer_id, v_payment.garment_ids);
    update payments set state = 'canceled' where payment_intent = p_payment_intent;
end $$;

-- L'app peut annuler son propre paiement en cours (feuille de paiement fermée).
create or replace function cancel_my_payment(p_payment_intent text) returns void
language plpgsql security definer set search_path = public as $$
begin
    if exists (select 1 from payments where payment_intent = p_payment_intent and buyer_id = auth.uid()) then
        perform cancel_payment(p_payment_intent);
    end if;
end $$;

-- Seul le backend (service_role, via les Edge Functions) réserve et finalise.
revoke all on function reserve_garments(uuid, uuid[]) from public, anon, authenticated;
revoke all on function release_garments(uuid, uuid[]) from public, anon, authenticated;
revoke all on function finalize_payment(text) from public, anon, authenticated;
revoke all on function cancel_payment(text) from public, anon, authenticated;
grant execute on function reserve_garments(uuid, uuid[]) to service_role;
grant execute on function release_garments(uuid, uuid[]) to service_role;
grant execute on function finalize_payment(text) to service_role;
grant execute on function cancel_payment(text) to service_role;
revoke all on function cancel_my_payment(text) from public, anon;
grant execute on function cancel_my_payment(text) to authenticated;

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
alter table payments     enable row level security; -- aucun accès client : service_role uniquement

-- Profils : chacun lit et modifie le sien ; is_admin n'est pas modifiable par l'app.
create policy "profil : lecture" on profiles for select using (id = auth.uid() or is_admin());
create policy "profil : modification" on profiles for update using (id = auth.uid()) with check (id = auth.uid());
revoke update on profiles from authenticated;
grant update (first_name, last_name, phone, address_line1, address_line2, postal_code, city,
              country, delivery_method, relay_point) on profiles to authenticated;

-- Vêtements : tout le monde voit les pièces publiées (navigation sans compte),
-- seule la boutique (admin) voit les pièces retirées et modifie le catalogue.
create policy "vêtements : lecture" on garments for select
    using (status <> 'withdrawn' or is_admin());
create policy "vêtements : ajout (boutique)" on garments for insert to authenticated with check (is_admin());
create policy "vêtements : modification (boutique)" on garments for update to authenticated
    using (is_admin()) with check (is_admin());
create policy "vêtements : suppression (boutique)" on garments for delete to authenticated using (is_admin());

-- Les clients ne modifient que les champs descriptifs ; status / cart_count / réservations
-- passent par les fonctions ci-dessus (security definer).
revoke insert, update on garments from authenticated;
grant insert (id, title, brand, summary, details, measurements, size, gender, category, condition, color,
              price_cents, photos) on garments to authenticated;
grant update (title, brand, summary, details, measurements, size, gender, category, condition, color,
              price_cents, photos, status) on garments to authenticated;

create policy "panier : lecture" on cart_items for select using (user_id = auth.uid());
create policy "panier : ajout d'une pièce en vente" on cart_items for insert with check (
    user_id = auth.uid()
    and exists (select 1 from garments g where g.id = garment_id and is_purchasable(g, auth.uid()))
);
create policy "panier : retrait" on cart_items for delete using (user_id = auth.uid());

create policy "swipes : les siens" on swipes for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "commandes : les siennes ou boutique" on orders for select using (buyer_id = auth.uid() or is_admin());
create policy "commandes : suivi (boutique)" on orders for update to authenticated using (is_admin()) with check (is_admin());
revoke update on orders from authenticated;
grant update (status, tracking_number) on orders to authenticated;

create policy "articles : lecture" on order_items for select using (
    is_admin() or exists (select 1 from orders o where o.id = order_id and o.buyer_id = auth.uid())
);
create policy "suivi : lecture" on order_events for select using (
    is_admin() or exists (select 1 from orders o where o.id = order_id and o.buyer_id = auth.uid())
);

-- ---------------------------------------------------------------------
-- Photos : bucket public en lecture, écriture réservée à la boutique
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('garment-photos', 'garment-photos', true)
on conflict (id) do nothing;

create policy "photos : ajout (boutique)" on storage.objects for insert to authenticated
    with check (bucket_id = 'garment-photos' and is_admin());
create policy "photos : modification (boutique)" on storage.objects for update to authenticated
    using (bucket_id = 'garment-photos' and is_admin());
create policy "photos : suppression (boutique)" on storage.objects for delete to authenticated
    using (bucket_id = 'garment-photos' and is_admin());

-- ---------------------------------------------------------------------
-- Temps réel
-- ---------------------------------------------------------------------
-- L'app s'abonne :
--   • garments UPDATE : vendue (« Trop tard ! ») et nombre de paniers (HOT)
--   • orders   UPDATE : suivi de livraison (RLS : uniquement ses commandes)
alter publication supabase_realtime add table garments, orders;
