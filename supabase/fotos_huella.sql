-- Huella visual de cada foto (para detectar repetidas aunque tengan otro nombre)
alter table public.fotos add column if not exists huella text;
