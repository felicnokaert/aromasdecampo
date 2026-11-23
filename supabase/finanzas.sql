-- Gastos del complejo y comisiones de cada plataforma, para calcular la ganancia
create table if not exists public.gastos (
  id bigint generated always as identity primary key,
  fecha date not null default current_date,
  categoria text not null default 'otros' check (categoria in ('limpieza','luz','gas','agua','internet','arreglos','impuestos','compras','sueldos','publicidad','otros')),
  monto integer not null check (monto > 0),
  nota text,
  fijo boolean not null default false,      -- se repite todos los meses desde "fecha"
  hasta date,                                -- si es fijo y dejó de pagarse
  creado timestamptz not null default now()
);
alter table public.gastos enable row level security;
create policy gastos_admin on public.gastos for all to authenticated using (public.es_admin()) with check (public.es_admin());
grant select, insert, update, delete on public.gastos to authenticated;
alter table public.ajustes add column if not exists comision_booking_pct numeric(4,1) not null default 15;
alter table public.ajustes add column if not exists comision_airbnb_pct numeric(4,1) not null default 15.5;
