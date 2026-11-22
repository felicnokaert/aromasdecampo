# Sistema de reservas — Aromas de Campo

Todo gratis: Vercel (la web) + Supabase (base de datos y funciones) + Resend (emails).

## Páginas
- `/` inicio · `/reservas.html` calendario, precios y reserva · `/guia.html` guía de Colón
- `/opinar.html?c=CODIGO` reseña del huésped · `/admin.html` panel
- `/cal/booking/<token>.ics` y `/cal/airbnb/<token>.ics` calendarios para las plataformas (se copian desde el panel)

## Base de datos (Supabase, cuenta "Aromas de Campo", proyecto aromas-de-campo)
- Estructura completa en `schema.sql` (ya cargada).
- Reglas: la reserva se confirma con la seña; un pedido sin seña no ocupa la fecha.
- Precios: común (2 y 4 personas), especiales por día/rango/temporada/feriado, recargo finde, descuento semanal, último minuto.
- Administradores: solo los emails de `admins_invitados`. Sumar uno:
  `insert into admins_invitados values ('email@nuevo.com');`

## Funciones automáticas (Supabase Edge Functions)
- `avisar-reserva`: email a Rubén por cada pedido nuevo de la web.
- `sincronizar`: lee Booking/Airbnb cada 30 min (pg_cron), avisa dobles reservas.
- `diario`: 10 hs — recordatorios y pedidos de reseña (con dominio propio) y resumen semanal los lunes.

## Pendiente para activar los emails
1. Cuenta gratis en resend.com con el email que recibe los avisos.
2. API key → Supabase → Edge Functions → Secrets → `RESEND_API_KEY`.
3. Con dominio propio: verificarlo en Resend y agregar el secreto `EMAIL_DESDE`.
