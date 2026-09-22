begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@moonlit.test', '', now(), now()),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@moonlit.test', '', now(), now()),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c@moonlit.test', '', now(), now()),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'd@moonlit.test', '', now(), now());

insert into public.couples(id, created_by, status) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'active'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003', 'active');
insert into public.couple_members(couple_id, user_id, slot, display_name) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 1, 'A'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 2, 'B'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003', 1, 'C'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000004', 2, 'D');
insert into public.moments(id, couple_id, author_id, storage_path, captured_at, upload_state) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001/10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001.jpg', now(), 'ready'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002/10000000-0000-0000-0000-000000000003/30000000-0000-0000-0000-000000000002.jpg', now(), 'ready');

select ok(has_table_privilege('authenticated', 'public.moments', 'select'), 'authenticated users can select moments through RLS');
select ok(not has_table_privilege('authenticated', 'public.moments', 'insert'), 'clients cannot directly insert moments');
select ok(not has_function_privilege('authenticated', 'public.create_pairing_invitation_internal(uuid,text,text)', 'execute'), 'pairing internals cannot be called by clients');
select ok(has_function_privilege('authenticated', 'public.begin_moment(uuid,text,timestamp with time zone)', 'execute'), 'authenticated users can reserve moments');
select ok(not has_table_privilege('authenticated', 'private.couple_invitations', 'select'), 'clients cannot read invitation digests');
select ok(not has_table_privilege('authenticated', 'private.pairing_attempts', 'select'), 'clients cannot read abuse counters');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select is((select count(*)::integer from public.couples), 1, 'member sees exactly their couple');
select is((select count(*)::integer from public.couple_members), 2, 'member sees exactly the two members');
select is((select count(*)::integer from public.moments), 1, 'member sees exactly their couple moments');
select is((select count(*)::integer from public.moments where id = '30000000-0000-0000-0000-000000000002'), 0, 'cross-couple moment is hidden');
select throws_ok(
  $$insert into public.moments(id, couple_id, author_id, storage_path, captured_at) values (gen_random_uuid(), '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'forged.jpg', now())$$,
  '42501',
  null,
  'direct forged moment insert is denied'
);
reset role;

select throws_ok(
  $$insert into public.couple_members(couple_id, user_id, slot, display_name) values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 2, 'Third')$$,
  '23505',
  null,
  'database constraints prevent a third member'
);

select * from finish();
rollback;
