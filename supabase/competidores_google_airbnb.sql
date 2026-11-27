alter table public.competidores
  add column if not exists google_place_id text,
  add column if not exists google_puntaje numeric,
  add column if not exists google_opiniones int,
  add column if not exists google_elogian text,
  add column if not exists google_quejas text,
  add column if not exists airbnb_url text,
  add column if not exists airbnb_puntaje numeric,
  add column if not exists airbnb_opiniones int;
alter table public.competidor_precios add column if not exists fuente text not null default 'booking';
alter table public.competidor_precios drop constraint if exists competidor_precios_booking_id_entrada_salida_personas_key;
create unique index if not exists competidor_precios_unico on public.competidor_precios (booking_id, entrada, salida, personas, fuente);
