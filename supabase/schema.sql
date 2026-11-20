-- Recuerditos: buzón temporal cifrado.
--
-- Ejecuta este archivo completo en Supabase → SQL Editor. Se puede ejecutar
-- varias veces: cada vez deja las reglas al día sin borrar mensajes.
-- El servidor nunca ve el contenido: todo llega cifrado desde el teléfono y
-- se borra en cuanto la otra persona lo descarga.
--
-- Las funciones "security definer" usan search_path vacío y nombres
-- completos (public.tabla) para que nadie pueda suplantar una tabla.

-- Solo las cuentas de Google pueden usar el buzón. Si alguien crea una cuenta
-- con correo usando la llave pública de la app, no podrá subir nada.
-- (Si algún día agregas otro método de inicio de sesión, agrégalo aquí.)
create or replace function public.is_allowed_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and coalesce(
    (auth.jwt() -> 'app_metadata' -> 'providers') ? 'google',
    (auth.jwt() -> 'app_metadata' ->> 'provider') = 'google',
    false
  );
$$;
revoke all on function public.is_allowed_user() from public, anon;
grant execute on function public.is_allowed_user() to authenticated;

-- Quién pertenece a cada buzón. El couple_id es un hash del código secreto,
-- así que solo quien tiene el código puede unirse.
create table if not exists public.couple_members (
  couple_id text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (couple_id, user_id)
);
alter table public.couple_members enable row level security;
create index if not exists couple_members_user
  on public.couple_members (user_id);

drop policy if exists "ver mis buzones" on public.couple_members;
create policy "ver mis buzones" on public.couple_members
  for select to authenticated using (user_id = auth.uid());

create or replace function public.join_couple(p_couple text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_allowed_user() then
    raise exception 'Se requiere iniciar sesión con Google';
  end if;
  if p_couple is null or p_couple !~ '^[0-9a-f]{64}$' then
    raise exception 'Buzón inválido';
  end if;
  if exists (
    select 1 from public.couple_members
    where couple_id = p_couple and user_id = auth.uid()
  ) then
    return;
  end if;
  -- Límites contra abuso: una pareja usa un buzón; dejamos margen para
  -- cambios de teléfono o de cuenta.
  if (select count(*) from public.couple_members
      where user_id = auth.uid()) >= 5 then
    raise exception 'Demasiados buzones para esta cuenta';
  end if;
  if (select count(*) from public.couple_members
      where couple_id = p_couple) >= 4 then
    raise exception 'Este buzón ya está completo';
  end if;
  insert into public.couple_members (couple_id, user_id)
  values (p_couple, auth.uid())
  on conflict do nothing;
end;
$$;
revoke all on function public.join_couple(text) from public, anon;
grant execute on function public.join_couple(text) to authenticated;

create or replace function public.is_couple_member(p_couple text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_allowed_user() and exists (
    select 1 from public.couple_members
    where couple_id = p_couple and user_id = auth.uid()
  );
$$;
revoke all on function public.is_couple_member(text) from public, anon;
grant execute on function public.is_couple_member(text) to authenticated;

-- Los mensajes en espera.
create table if not exists public.mailbox (
  id uuid primary key default gen_random_uuid(),
  couple_id text not null,
  sender uuid not null default auth.uid(),
  kind text not null check (kind in ('record', 'file')),
  payload text not null,
  object_path text,
  created_at timestamptz not null default now()
);
create index if not exists mailbox_couple_created
  on public.mailbox (couple_id, created_at);
alter table public.mailbox enable row level security;

-- Un mensaje cifrado pesa unos pocos KB; los archivos van aparte. El archivo
-- de un mensaje tiene que estar en la carpeta de su propio buzón.
alter table public.mailbox drop constraint if exists mailbox_payload_size;
alter table public.mailbox add constraint mailbox_payload_size
  check (char_length(payload) <= 262144);
alter table public.mailbox drop constraint if exists mailbox_object_in_couple;
alter table public.mailbox add constraint mailbox_object_in_couple
  check (object_path is null or object_path like couple_id || '/%');

drop policy if exists "enviar" on public.mailbox;
create policy "enviar" on public.mailbox
  for insert to authenticated
  with check (sender = auth.uid() and public.is_couple_member(couple_id));

-- Cada quien solo ve y borra lo que le envió la otra persona.
drop policy if exists "recibir" on public.mailbox;
create policy "recibir" on public.mailbox
  for select to authenticated
  using (public.is_couple_member(couple_id) and sender <> auth.uid());

drop policy if exists "confirmar" on public.mailbox;
create policy "confirmar" on public.mailbox
  for delete to authenticated
  using (public.is_couple_member(couple_id) and sender <> auth.uid());

-- Archivos cifrados (fotos y videos), en carpetas por buzón. Privado y con
-- límite de 50 MB por archivo (el máximo del plan gratuito).
insert into storage.buckets (id, name, public, file_size_limit)
values ('mailbox', 'mailbox', false, 52428800)
on conflict (id) do update
  set public = false, file_size_limit = 52428800;

drop policy if exists "mailbox subir" on storage.objects;
create policy "mailbox subir" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'mailbox'
    and public.is_couple_member((storage.foldername(name))[1])
  );

drop policy if exists "mailbox leer" on storage.objects;
create policy "mailbox leer" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'mailbox'
    and public.is_couple_member((storage.foldername(name))[1])
  );

drop policy if exists "mailbox borrar" on storage.objects;
create policy "mailbox borrar" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'mailbox'
    and public.is_couple_member((storage.foldername(name))[1])
  );

-- Invitaciones temporales: guardan el secreto de la pareja cifrado con el
-- código corto. Se entregan una sola vez y vencen a los pocos minutos.
-- Nadie puede leer esta tabla directamente; solo a través de las funciones.
create table if not exists public.invites (
  code_hash text primary key,
  payload text not null,
  created_by uuid not null default auth.uid(),
  expires_at timestamptz not null
);
alter table public.invites enable row level security;
create index if not exists invites_created_by
  on public.invites (created_by);

create or replace function public.create_invite(
  p_code_hash text, p_payload text, p_minutes int
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_allowed_user() then
    raise exception 'Se requiere iniciar sesión con Google';
  end if;
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invitación inválida';
  end if;
  -- El secreto cifrado ocupa unos 80 caracteres.
  if p_payload is null or char_length(p_payload) > 200 then
    raise exception 'Invitación inválida';
  end if;
  if p_minutes is null or p_minutes < 1 or p_minutes > 60 then
    raise exception 'Duración inválida';
  end if;
  delete from public.invites where expires_at < now();
  -- Cada cuenta tiene como mucho 3 invitaciones vigentes: al crear otra se
  -- descartan las más viejas.
  delete from public.invites
  where created_by = auth.uid()
    and code_hash in (
      select code_hash from public.invites
      where created_by = auth.uid()
      order by expires_at desc
      offset 2
    );
  insert into public.invites (code_hash, payload, created_by, expires_at)
  values (p_code_hash, p_payload, auth.uid(),
          now() + make_interval(mins => p_minutes));
end;
$$;
revoke all on function public.create_invite(text, text, int) from public, anon;
grant execute on function public.create_invite(text, text, int) to authenticated;

create or replace function public.claim_invite(p_code_hash text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload text;
begin
  if not public.is_allowed_user() then
    raise exception 'Se requiere iniciar sesión con Google';
  end if;
  if p_code_hash is null or p_code_hash !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  delete from public.invites
  where code_hash = p_code_hash
    and expires_at > now()
    and created_by <> auth.uid()
  returning payload into v_payload;
  return v_payload;
end;
$$;
revoke all on function public.claim_invite(text) from public, anon;
grant execute on function public.claim_invite(text) to authenticated;
