-- Server-side dashboard read RPC. Session tokens are hashed before lookup.
create or replace function public.get_site_orders(p_session_hash text)
returns table(tracking_code text,service text,quantity integer,amount_toman bigint,discount_toman bigint,status text,created_at timestamptz,customer_note text)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid;
begin
 if p_session_hash !~ '^[a-f0-9]{64}$' then return; end if;
 select user_id into v_user from public.site_sessions where token_hash=p_session_hash and revoked_at is null and expires_at>now();
 if v_user is null then return; end if;
 return query select o.tracking_code,o.service,o.quantity,o.amount_toman,o.discount_toman,o.status,o.created_at,o.customer_note
 from public.orders o where o.user_id=v_user order by o.created_at desc limit 50;
end; $$;
revoke all on function public.get_site_orders(text) from public,anon,authenticated;
grant execute on function public.get_site_orders(text) to service_role;
