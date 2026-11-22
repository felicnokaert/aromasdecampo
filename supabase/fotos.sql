-- Fotos de las cabañas y del complejo, cargadas desde el panel.
create table if not exists public.fotos (
  id         bigint generated always as identity primary key,
  cabana_id  smallint references public.cabanas(id) on delete cascade,  -- null = fotos del complejo
  ruta       text not null,          -- archivo grande dentro del bucket "fotos"
  miniatura  text not null,          -- archivo chico para listados
  lugar      text not null default 'exterior' check (lugar in ('exterior','interior','pileta','parque','alrededores')),
  descripcion text,
  ancho      integer, alto integer,
  portada    boolean not null default false,
  orden      integer not null default 0,
  creada     timestamptz not null default now()
);
create index if not exists fotos_cabana on public.fotos (cabana_id, orden);
alter table public.fotos enable row level security;
drop policy if exists fotos_leer on public.fotos;
create policy fotos_leer on public.fotos for select using (true);
drop policy if exists fotos_admin on public.fotos;
create policy fotos_admin on public.fotos for all to authenticated using (public.es_admin()) with check (public.es_admin());
grant select on public.fotos to anon, authenticated;
grant insert, update, delete on public.fotos to authenticated;

-- Las dos cabañas son iguales: mismo texto y equipamiento.
update public.cabanas set
  etiqueta = 'Hasta 4 personas',
  descripcion = 'Cabaña de troncos para hasta 4 personas: dos habitaciones, baño, cocina equipada y parrilla propia, con la pileta y el parque del complejo a unos pasos.',
  equipamiento = array['2 habitaciones','Baño privado','Cocina equipada','Parrilla propia','WiFi','Pileta del complejo']
where slug in ('sofia','olivia','emma');
