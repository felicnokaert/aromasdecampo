# Sistema de reservas — cómo se conecta

Todo es gratis: Vercel (la web) + Supabase (la base de datos) + Resend (los emails de aviso).

## 1. Base de datos (una sola vez)
1. Supabase → proyecto nuevo (región São Paulo).
2. SQL Editor → pegar todo `schema.sql` → **Run**. Se puede correr de nuevo sin romper nada.
3. Settings → API → copiar **Project URL** y la clave **publishable / anon**.
4. Pegar las dos en `js/aromas.js` (arriba de todo). Son públicas: la seguridad la da la base.
5. Authentication → URL Configuration → Site URL: la dirección de la web. Redirect URLs: `.../admin.html`.

## 2. Administradores
Solo pueden crear cuenta los emails de la tabla `admins_invitados`
(aranda.ruben@hotmail.com, lourdesdaranda16@gmail.com, felipecnokaert@gmail.com).
La primera vez entran a `/admin.html` → **"¿Primera vez? Crear mi contraseña"**.
Para sumar a alguien: `insert into admins_invitados values ('email@nuevo.com');`

## 3. Avisos por email de reservas nuevas
1. Crear cuenta gratis en resend.com **con aranda.ruben@hotmail.com** (sin dominio propio, Resend solo deja mandar al email del dueño de la cuenta).
2. Resend → API Keys → crear → guardarla en Supabase → Edge Functions → Secrets como `RESEND_API_KEY`.
3. Publicar la función `functions/avisar-reserva` (sin verificación JWT: se protege sola).
4. En SQL Editor: `alter database postgres set app.funciones_url = 'https://TU-PROYECTO.supabase.co/functions/v1';`
   y `create extension if not exists pg_net;`
5. Cuando tengan dominio propio: verificarlo en Resend y agregar el secreto `EMAIL_DESDE` = `Aromas de Campo <reservas@su-dominio.com.ar>`.

## Estadísticas por canal
Usar links con `?utm_source=`: en la bio de Instagram `.../?utm_source=instagram`, en los anuncios de Meta `?utm_source=meta`.
