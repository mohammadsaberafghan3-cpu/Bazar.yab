create extension if not exists pgcrypto;
create type public.app_role as enum ('customer','seller','admin');
create type public.seller_state as enum ('pending','approved','rejected','suspended');
create type public.product_state as enum ('draft','active','archived');
create type public.order_state as enum ('pending','confirmed','processing','shipped','delivered','cancelled');
create type public.payment_state as enum ('unpaid','pending','paid','refunded');
create type public.payment_method as enum ('cod');
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,full_name text not null default '',phone text,role public.app_role not null default 'customer',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.seller_applications(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,store_name text not null,owner_name text not null,phone text not null,province text not null,description text,status public.seller_state not null default 'pending',reviewed_by uuid references public.profiles(id),reviewed_at timestamptz,created_at timestamptz not null default now());
create table public.stores(id uuid primary key default gen_random_uuid(),owner_id uuid not null unique references public.profiles(id),name text not null,slug text not null unique,description text,province text,is_active boolean not null default false,created_at timestamptz not null default now());
create table public.categories(id uuid primary key default gen_random_uuid(),name_fa text not null,name_ps text,slug text not null unique,parent_id uuid references public.categories(id),is_active boolean not null default true);
create table public.products(id uuid primary key default gen_random_uuid(),store_id uuid not null references public.stores(id),category_id uuid references public.categories(id),sku text,name text not null,description text,price_afn numeric(14,2) not null check(price_afn>0),stock integer not null default 0 check(stock>=0),status public.product_state not null default 'draft',created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(store_id,sku));
create table public.product_images(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,storage_path text not null,sort_order integer not null default 0);
create table public.customer_addresses(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,recipient text not null,phone text not null,province text not null,district text not null,address text not null,is_default boolean not null default false,created_at timestamptz not null default now());
create table public.orders(id uuid primary key default gen_random_uuid(),order_number bigint generated always as identity unique,customer_id uuid not null references public.profiles(id),address_snapshot jsonb not null,subtotal_afn numeric(14,2) not null check(subtotal_afn>=0),shipping_afn numeric(14,2) not null default 0 check(shipping_afn>=0),total_afn numeric(14,2) not null check(total_afn>=0),payment_method public.payment_method not null default 'cod',payment_status public.payment_state not null default 'unpaid',status public.order_state not null default 'pending',created_at timestamptz not null default now());
create table public.order_items(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,product_id uuid references public.products(id) on delete set null,store_id uuid not null references public.stores(id),product_name text not null,sku text,quantity integer not null check(quantity>0),unit_price_afn numeric(14,2) not null check(unit_price_afn>0),line_total_afn numeric(14,2) not null check(line_total_afn>=0));
create table public.order_status_history(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,changed_by uuid references public.profiles(id),old_status public.order_state,new_status public.order_state not null,note text,created_at timestamptz not null default now());
create table public.reviews(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,customer_id uuid not null references public.profiles(id),rating integer not null check(rating between 1 and 5),body text,created_at timestamptz not null default now(),unique(product_id,customer_id));
create table public.audit_logs(id bigint generated always as identity primary key,actor_id uuid references public.profiles(id),action text not null,entity_type text not null,entity_id uuid,details jsonb not null default '{}'::jsonb,created_at timestamptz not null default now());
create or replace function public.current_app_role() returns public.app_role language sql stable security definer set search_path=public as $$ select role from public.profiles where id=auth.uid() $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(public.current_app_role()='admin',false) $$;
create or replace function public.owns_store(target_store uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.stores where id=target_store and owner_id=auth.uid()) $$;
alter table public.profiles enable row level security;alter table public.seller_applications enable row level security;alter table public.stores enable row level security;alter table public.categories enable row level security;alter table public.products enable row level security;alter table public.product_images enable row level security;alter table public.customer_addresses enable row level security;alter table public.orders enable row level security;alter table public.order_items enable row level security;alter table public.order_status_history enable row level security;alter table public.reviews enable row level security;alter table public.audit_logs enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy seller_app_insert on public.seller_applications for insert to authenticated with check(user_id=auth.uid());
create policy seller_app_read on public.seller_applications for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy seller_app_admin_update on public.seller_applications for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy stores_read on public.stores for select using(is_active or owner_id=auth.uid() or public.is_admin());
create policy stores_owner_update on public.stores for update to authenticated using(owner_id=auth.uid() or public.is_admin()) with check(owner_id=auth.uid() or public.is_admin());
create policy categories_read on public.categories for select using(is_active or public.is_admin());
create policy categories_admin on public.categories for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy products_read on public.products for select using(status='active' or public.owns_store(store_id) or public.is_admin());
create policy products_insert on public.products for insert to authenticated with check(public.owns_store(store_id) and public.current_app_role() in ('seller','admin'));
create policy products_update on public.products for update to authenticated using(public.owns_store(store_id) or public.is_admin()) with check(public.owns_store(store_id) or public.is_admin());
create policy products_delete on public.products for delete to authenticated using(public.owns_store(store_id) or public.is_admin());
create policy images_read on public.product_images for select using(exists(select 1 from public.products p where p.id=product_id and (p.status='active' or public.owns_store(p.store_id) or public.is_admin())));
create policy images_manage on public.product_images for all to authenticated using(exists(select 1 from public.products p where p.id=product_id and (public.owns_store(p.store_id) or public.is_admin()))) with check(exists(select 1 from public.products p where p.id=product_id and (public.owns_store(p.store_id) or public.is_admin())));
create policy addresses_owner on public.customer_addresses for all to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
create policy orders_read on public.orders for select to authenticated using(customer_id=auth.uid() or public.is_admin());
create policy orders_create on public.orders for insert to authenticated with check(customer_id=auth.uid());
create policy orders_admin_update on public.orders for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy items_read on public.order_items for select to authenticated using(public.is_admin() or exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()) or public.owns_store(store_id));
create policy items_create on public.order_items for insert to authenticated with check(exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()));
create policy history_read on public.order_status_history for select to authenticated using(public.is_admin() or exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()) or exists(select 1 from public.order_items i where i.order_id=order_id and public.owns_store(i.store_id)));
create policy history_admin_insert on public.order_status_history for insert to authenticated with check(public.is_admin());
create policy reviews_read on public.reviews for select using(true);
create policy reviews_create on public.reviews for insert to authenticated with check(customer_id=auth.uid() and exists(select 1 from public.orders o join public.order_items i on i.order_id=o.id where o.customer_id=auth.uid() and i.product_id=product_id and o.status='delivered'));
create policy reviews_delete on public.reviews for delete to authenticated using(customer_id=auth.uid() or public.is_admin());
create policy audit_read on public.audit_logs for select to authenticated using(public.is_admin());
create policy audit_insert on public.audit_logs for insert to authenticated with check(public.is_admin());
-- Provision the first admin only via trusted SQL after verifying the auth.users UUID.
-- Never let browser clients self-assign privileged roles; never expose service_role keys.

-- Create a customer profile automatically for new Auth users.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id,full_name,phone,role)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),new.phone,'customer')
  on conflict(id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Orders and their item snapshots must be created atomically on the server.
-- Client-supplied prices are deliberately ignored.
drop policy if exists orders_create on public.orders;
drop policy if exists items_create on public.order_items;
create or replace function public.place_order(p_items jsonb,p_address jsonb,p_shipping numeric default 0)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_order uuid;
  v_item record;
  v_product public.products%rowtype;
  v_subtotal numeric(14,2):=0;
  v_total numeric(14,2);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'Cart is empty'; end if;
  if p_address is null or jsonb_typeof(p_address) <> 'object' then raise exception 'A delivery address is required'; end if;
  if p_shipping < 0 then raise exception 'Invalid shipping fee'; end if;
  for v_item in
    select (value->>'product_id')::uuid as product_id,
           sum((value->>'quantity')::integer)::integer as quantity
    from jsonb_array_elements(p_items)
    group by (value->>'product_id')::uuid
  loop
    if v_item.quantity is null or v_item.quantity < 1 then raise exception 'Invalid quantity'; end if;
    select p.* into v_product
    from public.products p join public.stores s on s.id=p.store_id
    where p.id=v_item.product_id and p.status='active' and s.is_active=true
    for update of p;
    if not found then raise exception 'Product unavailable: %',v_item.product_id; end if;
    if v_product.stock < v_item.quantity then raise exception 'Insufficient stock for %',v_product.name; end if;
    v_subtotal:=v_subtotal+(v_product.price_afn*v_item.quantity);
  end loop;
  v_total:=v_subtotal+p_shipping;
  insert into public.orders(customer_id,address_snapshot,subtotal_afn,shipping_afn,total_afn,payment_method,payment_status,status)
  values(auth.uid(),p_address,v_subtotal,p_shipping,v_total,'cod','unpaid','pending')
  returning id into v_order;
  for v_item in
    select (value->>'product_id')::uuid as product_id,
           sum((value->>'quantity')::integer)::integer as quantity
    from jsonb_array_elements(p_items)
    group by (value->>'product_id')::uuid
  loop
    select p.* into v_product from public.products p where p.id=v_item.product_id for update;
    insert into public.order_items(order_id,product_id,store_id,product_name,sku,quantity,unit_price_afn,line_total_afn)
    values(v_order,v_product.id,v_product.store_id,v_product.name,v_product.sku,v_item.quantity,v_product.price_afn,v_product.price_afn*v_item.quantity);
    update public.products set stock=stock-v_item.quantity,updated_at=now() where id=v_product.id;
  end loop;
  insert into public.order_status_history(order_id,changed_by,new_status,note)
  values(v_order,auth.uid(),'pending','Order created with cash on delivery');
  return v_order;
end;
$$;
revoke all on function public.place_order(jsonb,jsonb,numeric) from public;
grant execute on function public.place_order(jsonb,jsonb,numeric) to authenticated;

-- Profile role is intentionally not writable by the client. Set seller/admin roles
-- only from a trusted administrative process after identity and application review.
