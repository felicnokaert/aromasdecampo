alter table public.ajustes add column if not exists pendientes_hechos jsonb not null default '[]'::jsonb;  -- guía 'Lo que falta completar' (lista de ids hechos)
