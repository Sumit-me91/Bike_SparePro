-- BikeSpare Pro schema for Supabase (PostgreSQL)
-- Run this entire file in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_name text not null,
  email text,
  phone text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  shop_id uuid references public.shops(id) on delete set null,
  full_name text not null default '',
  role text not null default 'owner' check (role in ('owner','staff','developer')),
  created_at timestamptz not null default now()
);

create table if not exists public.parts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null,
  sku text,
  category text,
  quantity integer not null default 0 check (quantity >= 0),
  min_stock integer not null default 5 check (min_stock >= 0),
  unit_price numeric(12,2) check (unit_price is null or unit_price >= 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(shop_id, sku)
);
create index if not exists parts_shop_name_idx on public.parts(shop_id, name);
create index if not exists parts_shop_quantity_idx on public.parts(shop_id, quantity);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  part_id uuid not null references public.parts(id) on delete restrict,
  movement_type text not null check (movement_type in ('opening','inward','sale','adjustment')),
  quantity_change integer not null,
  supplier text,
  reference text,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_shop_date_idx on public.stock_movements(shop_id, created_at desc);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  receipt_no text not null,
  customer_name text,
  customer_phone text,
  payment_method text not null default 'Cash',
  subtotal numeric(12,2) not null check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total_amount numeric(12,2) not null check (total_amount >= 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(shop_id, receipt_no)
);
create index if not exists sales_shop_date_idx on public.sales(shop_id, created_at desc);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  part_id uuid references public.parts(id) on delete set null,
  part_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now()
);

create or replace function public.current_shop_id()
returns uuid language sql stable security definer set search_path = public
as $$ select shop_id from public.profiles where id = auth.uid() $$;

create or replace function public.current_user_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() $$;

-- Automatically attach a shop ID to parts inserted by a signed-in owner/staff account.
create or replace function public.set_part_shop()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.shop_id is null then new.shop_id := public.current_shop_id(); end if;
  if new.shop_id is distinct from public.current_shop_id() then raise exception 'You cannot add parts to another shop.'; end if;
  if new.created_by is null then new.created_by := auth.uid(); end if;
  new.updated_at := now();
  return new;
end; $$;
drop trigger if exists parts_set_shop on public.parts;
create trigger parts_set_shop before insert or update on public.parts for each row execute function public.set_part_shop();

-- Add a delivery to stock in one transaction and log the movement.
create or replace function public.receive_stock(p_part_id uuid,p_quantity integer,p_supplier text default null,p_reference text default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare v_shop uuid; v_qty integer;
begin
  v_shop := public.current_shop_id();
  if v_shop is null then raise exception 'Your login is not linked to a shop.'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero.'; end if;
  update public.parts set quantity=quantity+p_quantity,updated_at=now() where id=p_part_id and shop_id=v_shop returning quantity into v_qty;
  if not found then raise exception 'Spare part not found in your shop.'; end if;
  insert into public.stock_movements(shop_id,part_id,movement_type,quantity_change,supplier,reference,note,created_by)
  values(v_shop,p_part_id,'inward',p_quantity,p_supplier,p_reference,p_note,auth.uid());
  return jsonb_build_object('new_quantity',v_qty);
end; $$;

-- Atomic checkout: validates all stock, writes receipt/items, and deducts inventory together.
create or replace function public.checkout_sale(p_customer_name text default null,p_customer_phone text default null,p_payment_method text default 'Cash',p_discount numeric default 0,p_items jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_shop uuid; v_sale_id uuid; v_receipt text; v_subtotal numeric(12,2):=0; v_total numeric(12,2); v_item jsonb; v_part public.parts%rowtype; v_qty integer; v_price numeric(12,2); v_line numeric(12,2); v_count integer:=0;
begin
  v_shop := public.current_shop_id();
  if v_shop is null then raise exception 'Your login is not linked to a shop.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'Add at least one item to the bill.'; end if;
  if coalesce(p_discount,0)<0 then raise exception 'Discount cannot be negative.'; end if;
  -- Validate and calculate before creating a receipt.
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_count:=v_count+1;
    v_qty:= (v_item->>'quantity')::integer;
    v_price:= (v_item->>'unit_price')::numeric;
    if v_qty is null or v_qty<=0 or v_price is null or v_price<0 then raise exception 'Invalid quantity or selling price.'; end if;
    select * into v_part from public.parts where id=(v_item->>'part_id')::uuid and shop_id=v_shop for update;
    if not found then raise exception 'A spare part does not belong to this shop.'; end if;
    if v_part.quantity < v_qty then raise exception 'Not enough stock for %. Available: %, requested: %.',v_part.name,v_part.quantity,v_qty; end if;
    v_subtotal:=v_subtotal+(v_qty*v_price);
  end loop;
  if coalesce(p_discount,0)>v_subtotal then raise exception 'Discount cannot exceed subtotal.'; end if;
  v_total:=v_subtotal-coalesce(p_discount,0);
  v_receipt:='BSP-'||to_char(now(),'YYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.sales(shop_id,receipt_no,customer_name,customer_phone,payment_method,subtotal,discount,total_amount,created_by)
  values(v_shop,v_receipt,nullif(trim(p_customer_name),''),nullif(trim(p_customer_phone),''),coalesce(nullif(trim(p_payment_method),''),'Cash'),v_subtotal,coalesce(p_discount,0),v_total,auth.uid()) returning id into v_sale_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::integer; v_price:=(v_item->>'unit_price')::numeric;
    select * into v_part from public.parts where id=(v_item->>'part_id')::uuid and shop_id=v_shop for update;
    v_line:=v_qty*v_price;
    insert into public.sale_items(sale_id,shop_id,part_id,part_name,quantity,unit_price,line_total)
    values(v_sale_id,v_shop,v_part.id,v_part.name,v_qty,v_price,v_line);
    update public.parts set quantity=quantity-v_qty,updated_at=now() where id=v_part.id;
    insert into public.stock_movements(shop_id,part_id,movement_type,quantity_change,reference,note,created_by)
    values(v_shop,v_part.id,'sale',-v_qty,v_receipt,'Sold on receipt '||v_receipt,auth.uid());
  end loop;
  return v_sale_id;
end; $$;

-- Enable row-level security for all shop data.
alter table public.shops enable row level security;
alter table public.profiles enable row level security;
alter table public.parts enable row level security;
alter table public.stock_movements enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;

drop policy if exists profiles_read_self on public.profiles;
create policy profiles_read_self on public.profiles for select to authenticated using (id=auth.uid());
-- Profile role/shop assignment is managed by the trusted developer service role only.
-- No browser-side UPDATE policy is intentionally granted on profiles.

drop policy if exists shops_read_own on public.shops;
create policy shops_read_own on public.shops for select to authenticated using (id=public.current_shop_id() or created_by=auth.uid() or public.current_user_role()='developer');

drop policy if exists parts_read_shop on public.parts;
create policy parts_read_shop on public.parts for select to authenticated using (shop_id=public.current_shop_id());
drop policy if exists parts_insert_shop on public.parts;
create policy parts_insert_shop on public.parts for insert to authenticated with check (shop_id=public.current_shop_id());
drop policy if exists parts_update_shop on public.parts;
create policy parts_update_shop on public.parts for update to authenticated using (shop_id=public.current_shop_id()) with check (shop_id=public.current_shop_id());
drop policy if exists parts_delete_shop on public.parts;
create policy parts_delete_shop on public.parts for delete to authenticated using (shop_id=public.current_shop_id());

drop policy if exists movements_read_shop on public.stock_movements;
create policy movements_read_shop on public.stock_movements for select to authenticated using (shop_id=public.current_shop_id());
drop policy if exists sales_read_shop on public.sales;
create policy sales_read_shop on public.sales for select to authenticated using (shop_id=public.current_shop_id());
drop policy if exists sale_items_read_shop on public.sale_items;
create policy sale_items_read_shop on public.sale_items for select to authenticated using (shop_id=public.current_shop_id());

-- Only callable by signed-in users; functions enforce the user's own shop and stock constraints.
revoke all on function public.receive_stock(uuid,integer,text,text,text) from public, anon;
grant execute on function public.receive_stock(uuid,integer,text,text,text) to authenticated;
revoke all on function public.checkout_sale(text,text,text,numeric,jsonb) from public, anon;
grant execute on function public.checkout_sale(text,text,text,numeric,jsonb) to authenticated;

-- IMPORTANT: after creating your developer user in Supabase Auth, run this once,
-- replacing the email below with the exact developer login email.
-- insert into public.profiles(id,shop_id,full_name,role)
-- select id,null,'Sumit Kaware','developer' from auth.users where lower(email)=lower('you@example.com')
-- on conflict (id) do update set role='developer',shop_id=null,full_name='Sumit Kaware';
