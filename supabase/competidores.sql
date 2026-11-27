-- Competidores: complejos de la zona y sus precios en Booking (los carga una tarea semanal)
create table if not exists public.competidores (
  id          bigint generated always as identity primary key,
  booking_id  bigint unique not null,
  nombre      text not null,
  es_nuestro  boolean not null default false,
  url         text,
  distancia   text,
  puntaje     numeric,          -- puntaje de huéspedes en Booking (0 a 10)
  opiniones   int,
  destacan    text,             -- lo que más elogian los huéspedes
  servicios   text[] not null default '{}',
  activo      boolean not null default true,
  actualizado timestamptz not null default now()
);
create table if not exists public.competidor_precios (
  id          bigint generated always as identity primary key,
  booking_id  bigint not null references public.competidores(booking_id) on delete cascade,
  periodo     text not null,      -- "Finde largo 8 de diciembre", "Enero", etc.
  entrada     date not null,
  salida      date not null,
  personas    int not null,       -- 2 = pareja, 4 = 2 adultos + 2 chicos
  disponible  boolean not null,
  precio_noche numeric,           -- en pesos, por noche, precio final de Booking
  relevado    timestamptz not null default now(),
  unique (booking_id, entrada, salida, personas)
);
alter table public.competidores enable row level security;
alter table public.competidor_precios enable row level security;
drop policy if exists comp_admin on public.competidores;
create policy comp_admin on public.competidores for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists comp_precios_admin on public.competidor_precios;
create policy comp_precios_admin on public.competidor_precios for all to authenticated using (public.es_admin()) with check (public.es_admin());
