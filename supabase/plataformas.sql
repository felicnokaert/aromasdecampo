-- Precios publicados en Airbnb y Booking (para comparar con la web y avisar)
alter table public.ajustes
  add column if not exists airbnb_usd_2 numeric,        -- lo que paga el huésped por noche, 2 personas
  add column if not exists airbnb_usd_4 numeric,        -- 4 personas
  add column if not exists booking_usd_2 numeric,
  add column if not exists booking_usd_4 numeric,
  add column if not exists booking_mediana_usd numeric, -- mediana de la zona que muestra Booking
  add column if not exists airbnb_sugerido_usd numeric, -- precio sugerido por Airbnb
  add column if not exists cotizacion_usd numeric;      -- dólar a usar si no se puede leer el del día
update public.ajustes set airbnb_usd_2 = coalesce(airbnb_usd_2, 90), airbnb_usd_4 = coalesce(airbnb_usd_4, 105),
  booking_usd_2 = coalesce(booking_usd_2, 90.3), booking_usd_4 = coalesce(booking_usd_4, 105),
  booking_mediana_usd = coalesce(booking_mediana_usd, 26.7), airbnb_sugerido_usd = coalesce(airbnb_sugerido_usd, 53);
