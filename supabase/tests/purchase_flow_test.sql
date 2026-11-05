-- Tests du parcours d'achat et des droits, exécutés sur un PostgreSQL local
-- (voir supabase/tests/run.sh). Chaque échec arrête le script.
\set ON_ERROR_STOP 1

create function test_assert(ok boolean, message text) returns void
language plpgsql as $$
begin
    if not coalesce(ok, false) then raise exception 'ÉCHEC : %', message; end if;
    raise notice 'ok - %', message;
end $$;
grant execute on function test_assert(boolean, text) to anon, authenticated, service_role;

-- Utilisateurs : la boutique (admin), Alice et Bob.
insert into auth.users (id, email) values
    ('00000000-0000-0000-0000-00000000000a', 'boutique@stylematch.test'),
    ('00000000-0000-0000-0000-0000000000a1', 'alice@test'),
    ('00000000-0000-0000-0000-0000000000b0', 'bob@test');
select test_assert((select count(*) from profiles) = 3, 'un profil est créé à chaque inscription');
update profiles set is_admin = true where id = '00000000-0000-0000-0000-00000000000a';

-- ---------------------------------------------------------------- Boutique
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
insert into garments (id, title, size, gender, category, condition, color, price_cents) values
    ('10000000-0000-0000-0000-000000000001', 'Veste en jean', 'M', 'unisex', 'jackets', 'veryGood', 'blue', 6500),
    ('10000000-0000-0000-0000-000000000002', 'Air Max 90', '42', 'men', 'shoes', 'veryGood', 'white', 8500),
    ('10000000-0000-0000-0000-000000000003', 'Pièce retirée', 'S', 'women', 'dresses', 'good', 'red', 3000);
update garments set status = 'withdrawn' where id = '10000000-0000-0000-0000-000000000003';
select test_assert(true, 'la boutique ajoute et retire des pièces');

-- ---------------------------------------------------------------- Droits clients
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$ begin
    insert into garments (title, size, gender, category, condition, color, price_cents)
    values ('Pirate', 'M', 'men', 'tshirts', 'good', 'black', 100);
    raise exception 'un client a pu ajouter une pièce';
exception when insufficient_privilege then
    perform test_assert(true, 'un client ne peut pas ajouter de pièce');
end $$;

do $$ begin
    update profiles set is_admin = true where id = auth.uid();
    raise exception 'un client a pu se rendre admin';
exception when insufficient_privilege then
    perform test_assert(true, 'un client ne peut pas se rendre admin');
end $$;

do $$ begin
    update garments set cart_count = 999;
    raise exception 'un client a pu modifier le compteur';
exception when insufficient_privilege then
    perform test_assert(true, 'un client ne peut pas modifier le compteur HOT');
end $$;

do $$ begin
    perform reserve_garments(auth.uid(), array['10000000-0000-0000-0000-000000000001'::uuid]);
    raise exception 'un client a pu réserver directement';
exception when insufficient_privilege then
    perform test_assert(true, 'seul le serveur peut réserver');
end $$;

update profiles set first_name = 'Alice', city = 'Paris' where id = auth.uid();
select test_assert((select first_name from profiles where id = auth.uid()) = 'Alice', 'un client modifie son profil');
select test_assert((select count(*) from profiles) = 1, 'un client ne voit que son profil');

-- ---------------------------------------------------------------- Fil et paniers
select test_assert((select count(*) from feed()) = 2, 'le fil cache les pièces retirées');
insert into cart_items (user_id, garment_id) values (auth.uid(), '10000000-0000-0000-0000-000000000001');
insert into swipes (user_id, garment_id, direction) values (auth.uid(), '10000000-0000-0000-0000-000000000001', 'right');
select test_assert((select count(*) from feed()) = 1, 'le fil exclut les pièces likées');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b0', false);
insert into cart_items (user_id, garment_id) values (auth.uid(), '10000000-0000-0000-0000-000000000001');
select test_assert((select cart_count from garments where id = '10000000-0000-0000-0000-000000000001') = 2,
                   'le compteur de paniers suit les ajouts');
select test_assert((select count(*) from cart_items) = 1, 'chacun ne voit que son panier');

reset role;
set role anon;
select set_config('request.jwt.claim.sub', '', false);
select test_assert((select count(*) from feed()) = 2, 'on peut parcourir le fil sans compte');

-- ---------------------------------------------------------------- Réservation concurrente
reset role;
set role service_role;
select test_assert(
    (reserve_garments('00000000-0000-0000-0000-0000000000a1', array['10000000-0000-0000-0000-000000000001'::uuid])
        -> 'reserved') @> '["10000000-0000-0000-0000-000000000001"]',
    'Alice réserve la veste');
select test_assert(
    (reserve_garments('00000000-0000-0000-0000-0000000000b0', array['10000000-0000-0000-0000-000000000001'::uuid])
        -> 'unavailable') @> '["10000000-0000-0000-0000-000000000001"]',
    'Bob ne peut pas réserver une pièce réservée par Alice');

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b0', false);
select test_assert((quote_garments(array['10000000-0000-0000-0000-000000000001'::uuid]) -> 'unavailable') @> '["10000000-0000-0000-0000-000000000001"]',
                   'le devis de Bob signale la pièce réservée');
do $$ begin
    insert into cart_items (user_id, garment_id) values (auth.uid(), '10000000-0000-0000-0000-000000000002');
    perform test_assert(true, 'Bob peut ajouter une autre pièce');
end $$;

-- ---------------------------------------------------------------- Paiement réussi
reset role;
set role service_role;
insert into payments (payment_intent, buyer_id, garment_ids, amount_cents, delivery_method, shipping_address, buyer_name)
values ('pi_alice', '00000000-0000-0000-0000-0000000000a1', array['10000000-0000-0000-0000-000000000001'::uuid],
        6500 + shipping_cents('home') + service_fee_cents(6500), 'home', '{"city": "Paris"}', 'Alice');
select finalize_payment('pi_alice');
reset role;

select test_assert((select status from garments where id = '10000000-0000-0000-0000-000000000001') = 'sold', 'la veste est vendue');
select test_assert(not exists (select 1 from cart_items where garment_id = '10000000-0000-0000-0000-000000000001'),
                   'la veste disparaît de TOUS les paniers');
select test_assert((select cart_count from garments where id = '10000000-0000-0000-0000-000000000001') = 0, 'le compteur revient à 0');
select test_assert((select number from orders) = 'SM-000001', 'premier numéro de commande');
select test_assert((select subtotal_cents + shipping_cents + service_fee_cents from orders) = 6500 + 490 + 395,
                   'le total facturé correspond au devis');
select test_assert((select refunded_cents from payments where payment_intent = 'pi_alice') = 0, 'aucun remboursement');
select test_assert((select count(*) from order_events) = 1, 'le suivi démarre à « confirmée »');
select test_assert((finalize_payment('pi_alice') ->> 'already_done')::boolean, 'le webhook peut être rejoué sans doublon');
select test_assert((select count(*) from orders) = 1, 'une seule commande après rejeu');

-- ---------------------------------------------------------------- Expiration et annulation
set role service_role;
select reserve_garments('00000000-0000-0000-0000-0000000000b0', array['10000000-0000-0000-0000-000000000002'::uuid]);
reset role;
update garments set reserved_until = now() - interval '1 minute' where id = '10000000-0000-0000-0000-000000000002';
set role service_role;
select test_assert(
    (reserve_garments('00000000-0000-0000-0000-0000000000a1', array['10000000-0000-0000-0000-000000000002'::uuid])
        -> 'reserved') @> '["10000000-0000-0000-0000-000000000002"]',
    'une réservation expirée libère la pièce');
insert into payments (payment_intent, buyer_id, garment_ids, amount_cents, delivery_method, shipping_address)
values ('pi_cancel', '00000000-0000-0000-0000-0000000000a1', array['10000000-0000-0000-0000-000000000002'::uuid], 9000, 'home', '{}');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b0', false);
select cancel_my_payment('pi_cancel');
reset role;
select test_assert((select status from garments where id = '10000000-0000-0000-0000-000000000002') = 'reserved',
                   'Bob ne peut pas annuler le paiement d''Alice');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select cancel_my_payment('pi_cancel');
reset role;
select test_assert((select status from garments where id = '10000000-0000-0000-0000-000000000002') = 'available',
                   'annuler le paiement libère la pièce');

-- ---------------------------------------------------------------- Pièce perdue pendant le paiement
set role service_role;
select reserve_garments('00000000-0000-0000-0000-0000000000b0', array['10000000-0000-0000-0000-000000000002'::uuid]);
insert into payments (payment_intent, buyer_id, garment_ids, amount_cents, delivery_method, shipping_address)
values ('pi_bob_late', '00000000-0000-0000-0000-0000000000b0', array['10000000-0000-0000-0000-000000000002'::uuid], 9415, 'home', '{}');
reset role;
-- La réservation de Bob expire et Alice achète la pièce avant que le paiement de Bob n'aboutisse.
update garments set reserved_until = now() - interval '1 minute' where id = '10000000-0000-0000-0000-000000000002';
set role service_role;
select reserve_garments('00000000-0000-0000-0000-0000000000a1', array['10000000-0000-0000-0000-000000000002'::uuid]);
insert into payments (payment_intent, buyer_id, garment_ids, amount_cents, delivery_method, shipping_address)
values ('pi_alice2', '00000000-0000-0000-0000-0000000000a1', array['10000000-0000-0000-0000-000000000002'::uuid], 9415, 'home', '{}');
select finalize_payment('pi_alice2');
select test_assert((finalize_payment('pi_bob_late') ->> 'refund_cents')::int = 9415,
                   'Bob est intégralement remboursé si la pièce lui a échappé');
reset role;
select test_assert((select count(*) from orders) = 2, 'pas de commande pour Bob');
select test_assert((select number from orders order by created_at desc, number desc limit 1) = 'SM-000002',
                   'les numéros de commande se suivent');

-- ---------------------------------------------------------------- Suivi de commande
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select test_assert((select count(*) from orders) = 2, 'Alice voit ses commandes');
update orders set status = 'delivered';
select test_assert((select count(*) from orders where status = 'delivered') = 0, 'un client ne peut pas changer le statut');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b0', false);
select test_assert((select count(*) from orders) = 0, 'Bob ne voit pas les commandes d''Alice');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
update orders set status = 'shipped', tracking_number = '8R123FR' where number = 'SM-000001';
reset role;
select test_assert((select count(*) from order_events e join orders o on o.id = e.order_id where o.number = 'SM-000001') = 2,
                   'la boutique expédie et le suivi est historisé');

-- ---------------------------------------------------------------- Suppression de compte
delete from auth.users where id = '00000000-0000-0000-0000-0000000000a1';
select test_assert((select count(*) from orders where buyer_id is null) = 2, 'les commandes sont conservées sans le compte');
select test_assert(not exists (select 1 from profiles where id = '00000000-0000-0000-0000-0000000000a1'),
                   'le profil est supprimé avec le compte');

\echo 'TOUS LES TESTS SQL SONT PASSÉS'
