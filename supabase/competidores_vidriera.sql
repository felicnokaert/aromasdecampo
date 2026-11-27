alter table public.competidores add column if not exists fotos text[] not null default '{}', add column if not exists descripcion text, add column if not exists para_copiar text;
