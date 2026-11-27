-- Vérifie qu'une base Supabase contient TOUT le schéma de la migration initiale
-- (utile si le SQL a été collé à la main dans le SQL Editor).
-- Généré à partir de supabase/migrations/20261105000000_initial_schema.sql.
-- Résultat : une ligne avec le nombre d'objets présents / manquants.
with expected(kind, name) as (values
    ('type', 'gender'),
    ('type', 'garment_status'),
    ('type', 'delivery_method'),
    ('type', 'order_status'),
    ('type', 'swipe_direction'),
    ('type', 'payment_state'),
    ('table', 'profiles'),
    ('table', 'garments'),
    ('table', 'cart_items'),
    ('table', 'swipes'),
    ('table', 'orders'),
    ('table', 'order_items'),
    ('table', 'order_events'),
    ('table', 'payments'),
    ('function', 'reservation_ttl'),
    ('function', 'handle_new_user'),
    ('function', 'is_admin'),
    ('function', 'is_purchasable'),
    ('function', 'log_order_status'),
    ('function', 'sync_cart_count'),
    ('function', 'shipping_cents'),
    ('function', 'service_fee_cents'),
    ('function', 'carrier_for'),
    ('function', 'quote_garments'),
    ('function', 'feed'),
    ('function', 'reserve_garments'),
    ('function', 'release_garments'),
    ('function', 'finalize_payment'),
    ('function', 'cancel_payment'),
    ('function', 'cancel_my_payment'),
    ('trigger', 'on_auth_user_created'),
    ('trigger', 'orders_status_log'),
    ('trigger', 'cart_items_count'),
    ('sequence', 'order_number_seq'),
    ('policy', 'profil : lecture'),
    ('policy', 'profil : modification'),
    ('policy', 'vêtements : lecture'),
    ('policy', 'vêtements : ajout (boutique)'),
    ('policy', 'vêtements : modification (boutique)'),
    ('policy', 'vêtements : suppression (boutique)'),
    ('policy', 'panier : lecture'),
    ('policy', 'panier : ajout d''une pièce en vente'),
    ('policy', 'panier : retrait'),
    ('policy', 'swipes : les siens'),
    ('policy', 'commandes : les siennes ou boutique'),
    ('policy', 'commandes : suivi (boutique)'),
    ('policy', 'articles : lecture'),
    ('policy', 'suivi : lecture'),
    ('policy', 'photos : ajout (boutique)'),
    ('policy', 'photos : modification (boutique)'),
    ('policy', 'photos : suppression (boutique)'),
    ('rls', 'profiles'),
    ('rls', 'garments'),
    ('rls', 'cart_items'),
    ('rls', 'swipes'),
    ('rls', 'orders'),
    ('rls', 'order_items'),
    ('rls', 'order_events'),
    ('rls', 'payments'),
    ('bucket', 'garment-photos'),
    ('realtime', 'garments'),
    ('realtime', 'orders')
), present(kind, name) as (
    select 'type', t.typname from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public'
    union all
    select 'table', c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
    union all
    select 'rls', c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
    union all
    select 'function', p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
    union all
    select 'trigger', tgname from pg_trigger where not tgisinternal
    union all
    select 'sequence', c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'S'
    union all
    select 'policy', policyname from pg_policies where schemaname in ('public', 'storage')
    union all
    select 'bucket', id from storage.buckets
    union all
    select 'realtime', tablename from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'
)
select
    count(*) filter (where p_ok) as present_count,
    count(*) filter (where not p_ok) as missing_count,
    coalesce(string_agg(kind || ':' || name, ', ') filter (where not p_ok), '') as missing
from (
    select e.kind, e.name, exists (select 1 from present p where p.kind = e.kind and p.name = e.name) as p_ok
    from expected e
) checks;
