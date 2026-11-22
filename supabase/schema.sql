-- =====================================================================
-- AROMAS DE CAMPO — Sistema de reservas (Supabase / Postgres)
-- Se ejecuta UNA sola vez: Supabase → SQL Editor → pegar todo → Run
-- =====================================================================

create extension if not exists btree_gist with schema extensions;

-- ---------------------------------------------------------------------
-- TABLAS
-- ---------------------------------------------------------------------

create table if not exists public.cabanas (
  id            smallint generated always as identity primary key,
  slug          text unique not null,
  nombre        text not null,
  etiqueta      text,                          -- "Ideal parejas", "Más elegida"
  descripcion   text,
  capacidad     smallint not null default 4 check (capacidad between 1 and 20),
  habitaciones  smallint not null default 2,
  precio_base   integer  not null check (precio_base > 0),   -- pesos por noche
  minimo_noches smallint not null default 2 check (minimo_noches between 1 and 30),
  equipamiento  text[]   not null default '{}',
  foto          text,
  orden         smallint not null default 0,
  activa        boolean  not null default true
);

-- Temporadas: un recargo (o descuento) en % sobre el precio base.
-- Ej: "Enero" +40 %, "Temporada baja" -15 %. Si cabana_id es null aplica a todas.
create table if not exists public.temporadas (
  id            bigint generated always as identity primary key,
  nombre        text not null,
  desde         date not null,
  hasta         date not null,                 -- inclusive
  recargo_pct   smallint not null default 0 check (recargo_pct between -90 and 300),
  minimo_noches smallint check (minimo_noches between 1 and 30),
  cabana_id     smallint references public.cabanas(id) on delete cascade,
  check (hasta >= desde)
);

create table if not exists public.reservas (
  id         bigint generated always as identity primary key,
  codigo     text unique not null default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)),
  cabana_id  smallint not null references public.cabanas(id),
  entrada    date not null,
  salida     date not null,
  nombre     text,
  telefono   text,
  email      text,
  personas   smallint,
  mascota    boolean not null default false,
  mensaje    text,
  total      integer,
  sena       integer,
  estado     text not null default 'pendiente'
             check (estado in ('pendiente','confirmada','cancelada','bloqueo')),
  origen     text not null default 'web'
             check (origen in ('web','whatsapp','instagram','booking','airbnb','otro','bloqueo')),
  notas      text,
  creada     timestamptz not null default now(),
  vence      timestamptz,                       -- hasta cuándo una "pendiente" guarda las fechas
  notificada boolean not null default false,
  check (salida > entrada),
  check (salida - entrada <= 60)
);

-- Nunca dos reservas confirmadas (o bloqueos) superpuestas en la misma cabaña
do $$ begin
  alter table public.reservas add constraint reservas_sin_superposicion
    exclude using gist (cabana_id with =, daterange(entrada, salida) with &&)
    where (estado in ('confirmada','bloqueo'));
exception when duplicate_object or duplicate_table then null; end $$;

create index if not exists reservas_cabana_fechas on public.reservas (cabana_id, entrada, salida);
create index if not exists reservas_estado on public.reservas (estado, creada desc);

create table if not exists public.ajustes (
  id                boolean primary key default true check (id),
  whatsapp          text not null default '5491169495055',
  alias             text,
  cbu               text,
  titular           text,
  sena_pct          smallint not null default 30 check (sena_pct between 0 and 100),
  horas_para_senar  smallint not null default 48 check (horas_para_senar between 1 and 240),
  checkin           text not null default '14 hs',
  checkout          text not null default '11 hs',
  recargo_finde_pct smallint not null default 0 check (recargo_finde_pct between 0 and 200),
  aviso             text,                        -- mensaje opcional arriba de la web
  email_avisos      text default 'aranda.ruben@hotmail.com'  -- a dónde llegan los avisos de reservas nuevas
);

create table if not exists public.preguntas (
  id        bigint generated always as identity primary key,
  pregunta  text not null,
  respuesta text not null,
  orden     smallint not null default 0,
  visible   boolean  not null default true
);

create table if not exists public.eventos (
  id      bigint generated always as identity primary key,
  tipo    text not null check (tipo in ('visita','whatsapp','calendario','cotizacion','solicitud','pregunta','video')),
  detalle text,
  fuente  text,                                  -- instagram, facebook, google, directo...
  creado  timestamptz not null default now()
);
create index if not exists eventos_creado on public.eventos (creado desc);

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nombre  text
);

-- ---------------------------------------------------------------------
-- FUNCIONES
-- ---------------------------------------------------------------------

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- Precio de UNA noche (redondeado a $500)
create or replace function public.precio_noche(p_cabana smallint, p_fecha date) returns integer
language plpgsql stable security definer set search_path = '' as $$
declare
  v_base integer; v_finde smallint; v_pct smallint := 0; v_precio numeric;
begin
  select precio_base into v_base from public.cabanas where id = p_cabana;
  if v_base is null then return null; end if;
  select recargo_finde_pct into v_finde from public.ajustes where id;
  -- la temporada más específica (la más corta) gana
  select t.recargo_pct into v_pct from public.temporadas t
   where p_fecha between t.desde and t.hasta
     and (t.cabana_id is null or t.cabana_id = p_cabana)
   order by (t.cabana_id is null), (t.hasta - t.desde), t.id desc
   limit 1;
  v_precio := v_base * (1 + coalesce(v_pct,0) / 100.0);
  if extract(isodow from p_fecha) in (5, 6) then   -- noches de viernes y sábado
    v_precio := v_precio * (1 + coalesce(v_finde,0) / 100.0);
  end if;
  return (round(v_precio / 500.0) * 500)::integer;
end $$;

create or replace function public.minimo_noches(p_cabana smallint, p_fecha date) returns smallint
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select t.minimo_noches from public.temporadas t
      where p_fecha between t.desde and t.hasta
        and (t.cabana_id is null or t.cabana_id = p_cabana)
        and t.minimo_noches is not null
      order by (t.cabana_id is null), (t.hasta - t.desde), t.id desc limit 1),
    (select minimo_noches from public.cabanas where id = p_cabana));
$$;

-- ¿Está libre esa noche? (confirmadas, bloqueos y pendientes no vencidas ocupan)
create or replace function public.noche_ocupada(p_cabana smallint, p_fecha date) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.reservas r
     where r.cabana_id = p_cabana
       and p_fecha >= r.entrada and p_fecha < r.salida
       and (r.estado in ('confirmada','bloqueo')
            or (r.estado = 'pendiente' and (r.vence is null or r.vence > now()))));
$$;

-- Calendario público: precio y disponibilidad por día, SIN datos de huéspedes
create or replace function public.calendario_publico(p_desde date, p_hasta date)
returns table (cabana_id smallint, fecha date, precio integer, libre boolean, nivel text, quedan smallint)
language sql stable security definer set search_path = '' as $$
  with dias as (
    select d::date as fecha
      from generate_series(greatest(p_desde, current_date),
                           least(p_hasta, current_date + 400), interval '1 day') d
  ), base as (
    select c.id as cabana_id, d.fecha, c.precio_base,
           public.precio_noche(c.id, d.fecha) as precio,
           not public.noche_ocupada(c.id, d.fecha) as libre
      from public.cabanas c cross join dias d
     where c.activa
  )
  select b.cabana_id, b.fecha, b.precio, b.libre,
         case when b.precio < b.precio_base * 0.97 then 'bajo'
              when b.precio > b.precio_base * 1.10 then 'alto'
              else 'normal' end,
         (count(*) filter (where b.libre) over (partition by b.fecha))::smallint
    from base b
   order by b.fecha, b.cabana_id;
$$;

-- Cotización de una estadía
create or replace function public.cotizar(p_cabana smallint, p_entrada date, p_salida date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_noches int := p_salida - p_entrada; v_total int := 0; v_min smallint;
  v_d date; v_libre boolean := true; v_sena_pct smallint; v_cap smallint;
begin
  if p_entrada is null or p_salida is null or v_noches <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Elegí la fecha de entrada y de salida.');
  end if;
  if p_entrada < current_date then
    return jsonb_build_object('ok', false, 'error', 'La fecha de entrada ya pasó.');
  end if;
  if v_noches > 30 then
    return jsonb_build_object('ok', false, 'error', 'Para estadías de más de 30 noches escribinos por WhatsApp.');
  end if;
  select capacidad into v_cap from public.cabanas where id = p_cabana and activa;
  if v_cap is null then return jsonb_build_object('ok', false, 'error', 'Cabaña no disponible.'); end if;
  v_min := public.minimo_noches(p_cabana, p_entrada);
  v_d := p_entrada;
  while v_d < p_salida loop
    v_total := v_total + public.precio_noche(p_cabana, v_d);
    if public.noche_ocupada(p_cabana, v_d) then v_libre := false; end if;
    v_d := v_d + 1;
  end loop;
  select sena_pct into v_sena_pct from public.ajustes where id;
  return jsonb_build_object(
    'ok', v_libre and v_noches >= v_min,
    'error', case when not v_libre then 'Alguna de esas noches ya está ocupada. Probá con otras fechas u otra cabaña.'
                  when v_noches < v_min then format('Para esas fechas la estadía mínima es de %s noches.', v_min)
             end,
    'noches', v_noches, 'minimo', v_min, 'total', v_total, 'capacidad', v_cap,
    'sena', (round(v_total * coalesce(v_sena_pct,30) / 100.0 / 100) * 100)::int);
end $$;

-- Solicitud de reserva desde la web (el precio lo calcula el servidor, no el navegador)
create or replace function public.solicitar_reserva(
  p_cabana smallint, p_entrada date, p_salida date,
  p_nombre text, p_telefono text, p_email text,
  p_personas smallint, p_mascota boolean, p_mensaje text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_cot jsonb; v_horas smallint; v_codigo text; v_vence timestamptz;
begin
  if coalesce(length(trim(p_nombre)),0) < 2 or coalesce(length(regexp_replace(p_telefono,'\D','','g')),0) < 8 then
    return jsonb_build_object('ok', false, 'error', 'Completá tu nombre y un teléfono válido.');
  end if;
  if length(p_nombre) > 80 or length(p_telefono) > 30 or length(coalesce(p_email,'')) > 120
     or length(coalesce(p_mensaje,'')) > 800 then
    return jsonb_build_object('ok', false, 'error', 'Algún dato es demasiado largo.');
  end if;
  -- freno anti-spam simple
  if (select count(*) from public.reservas where origen = 'web' and creada > now() - interval '1 hour') > 25 then
    return jsonb_build_object('ok', false, 'error', 'Hay muchas solicitudes en este momento. Escribinos por WhatsApp.');
  end if;

  perform pg_advisory_xact_lock(p_cabana);         -- evita que dos personas tomen la misma fecha a la vez
  v_cot := public.cotizar(p_cabana, p_entrada, p_salida);
  if not (v_cot->>'ok')::boolean then return v_cot; end if;
  if p_personas is null or p_personas < 1 or p_personas > (v_cot->>'capacidad')::int then
    return jsonb_build_object('ok', false, 'error', format('Esta cabaña es para hasta %s personas.', v_cot->>'capacidad'));
  end if;

  select horas_para_senar into v_horas from public.ajustes where id;
  v_vence := now() + make_interval(hours => coalesce(v_horas, 48));

  insert into public.reservas (cabana_id, entrada, salida, nombre, telefono, email, personas,
                               mascota, mensaje, total, sena, estado, origen, vence)
  values (p_cabana, p_entrada, p_salida, trim(p_nombre), trim(p_telefono), nullif(trim(p_email),''),
          p_personas, coalesce(p_mascota,false), nullif(trim(p_mensaje),''),
          (v_cot->>'total')::int, (v_cot->>'sena')::int, 'pendiente', 'web', v_vence)
  returning codigo into v_codigo;

  insert into public.eventos (tipo, detalle) values ('solicitud', v_codigo);

  return v_cot || jsonb_build_object('ok', true, 'codigo', v_codigo, 'vence', v_vence);
end $$;

-- Registro de visitas y clics (para las estadísticas del panel)
create or replace function public.registrar_evento(p_tipo text, p_detalle text default null, p_fuente text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_tipo not in ('visita','whatsapp','calendario','cotizacion','pregunta','video') then return; end if;
  insert into public.eventos (tipo, detalle, fuente)
  values (p_tipo, left(p_detalle, 120), left(p_fuente, 40));
end $$;

-- Estadísticas para el panel (solo administradores)
create or replace function public.estadisticas(p_dias int default 30)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb; v_desde timestamptz := now() - make_interval(days => p_dias);
begin
  if not public.es_admin() then raise exception 'No autorizado'; end if;
  select jsonb_build_object(
    'visitas',      (select count(*) from public.eventos where tipo='visita'     and creado >= v_desde),
    'whatsapp',     (select count(*) from public.eventos where tipo='whatsapp'   and creado >= v_desde),
    'cotizaciones', (select count(*) from public.eventos where tipo='cotizacion' and creado >= v_desde),
    'solicitudes',  (select count(*) from public.reservas where origen='web' and creada >= v_desde),
    'confirmadas',  (select count(*) from public.reservas where estado='confirmada' and creada >= v_desde),
    'ingresos_mes', (select coalesce(sum(total),0) from public.reservas
                      where estado='confirmada' and date_trunc('month', entrada) = date_trunc('month', current_date)),
    'ocupacion_30', (select round(100.0 * count(*) filter (where public.noche_ocupada(c.id, d::date))
                            / greatest(count(*),1))
                       from public.cabanas c cross join generate_series(current_date, current_date + 29, interval '1 day') d
                      where c.activa),
    'fuentes',      (select coalesce(jsonb_object_agg(f, n), '{}') from (
                       select coalesce(nullif(fuente,''),'directo') f, count(*) n from public.eventos
                        where tipo='visita' and creado >= v_desde group by 1 order by 2 desc limit 6) x),
    'preguntas',    (select coalesce(jsonb_agg(jsonb_build_object('pregunta', detalle, 'veces', n)), '[]') from (
                       select detalle, count(*) n from public.eventos
                        where tipo='pregunta' and creado >= v_desde group by 1 order by 2 desc limit 5) x),
    'por_dia',      (select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'visitas', vis, 'whatsapp', wa) order by dia), '[]') from (
                       select creado::date dia, count(*) filter (where tipo='visita') vis,
                              count(*) filter (where tipo='whatsapp') wa
                         from public.eventos where creado >= v_desde group by 1) x)
  ) into v;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- SEGURIDAD (RLS): el público solo lee lo público; los datos de huéspedes
-- solo los ven los administradores cargados en la tabla "admins".
-- ---------------------------------------------------------------------
alter table public.cabanas    enable row level security;
alter table public.temporadas enable row level security;
alter table public.reservas   enable row level security;
alter table public.ajustes    enable row level security;
alter table public.preguntas  enable row level security;
alter table public.eventos    enable row level security;
alter table public.admins     enable row level security;

drop policy if exists cabanas_leer on public.cabanas;
create policy cabanas_leer on public.cabanas for select using (activa or public.es_admin());
drop policy if exists cabanas_admin on public.cabanas;
create policy cabanas_admin on public.cabanas for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists temporadas_leer on public.temporadas;
create policy temporadas_leer on public.temporadas for select using (true);
drop policy if exists temporadas_admin on public.temporadas;
create policy temporadas_admin on public.temporadas for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists reservas_admin on public.reservas;
create policy reservas_admin on public.reservas for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists ajustes_leer on public.ajustes;
create policy ajustes_leer on public.ajustes for select using (true);
drop policy if exists ajustes_admin on public.ajustes;
create policy ajustes_admin on public.ajustes for update to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists preguntas_leer on public.preguntas;
create policy preguntas_leer on public.preguntas for select using (visible or public.es_admin());
drop policy if exists preguntas_admin on public.preguntas;
create policy preguntas_admin on public.preguntas for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists eventos_admin on public.eventos;
create policy eventos_admin on public.eventos for select to authenticated using (public.es_admin());

drop policy if exists admins_propio on public.admins;
create policy admins_propio on public.admins for select to authenticated using (user_id = auth.uid());

-- Funciones: las internas no se exponen; las públicas sí
revoke execute on all functions in schema public from public, anon;
grant execute on function public.calendario_publico(date, date) to anon, authenticated;
grant execute on function public.cotizar(smallint, date, date) to anon, authenticated;
grant execute on function public.solicitar_reserva(smallint, date, date, text, text, text, smallint, boolean, text) to anon, authenticated;
grant execute on function public.registrar_evento(text, text, text) to anon, authenticated;
grant execute on function public.estadisticas(int) to authenticated;
grant execute on function public.es_admin() to authenticated;
-- las políticas RLS necesitan poder evaluar es_admin() también para anon
grant execute on function public.es_admin() to anon;

-- ---------------------------------------------------------------------
-- ADMINISTRADORES: solo estos emails pueden crearse una cuenta.
-- La primera vez cada uno elige su contraseña desde admin.html.
-- ---------------------------------------------------------------------
create table if not exists public.admins_invitados (email text primary key);
alter table public.admins_invitados enable row level security;   -- sin políticas: nadie la lee desde la web

create or replace function public.solo_invitados() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.admins_invitados where email = lower(new.email)) then
    raise exception 'Este email no está habilitado para el panel de Aromas de Campo';
  end if;
  return new;
end $$;

create or replace function public.alta_admin() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.admins (user_id, nombre) values (new.id, split_part(new.email, '@', 1))
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists aromas_solo_invitados on auth.users;
create trigger aromas_solo_invitados before insert on auth.users for each row execute function public.solo_invitados();
drop trigger if exists aromas_alta_admin on auth.users;
create trigger aromas_alta_admin after insert on auth.users for each row execute function public.alta_admin();

insert into public.admins_invitados (email) values
  ('aranda.ruben@hotmail.com'), ('lourdesdaranda16@gmail.com'), ('felipecnokaert@gmail.com')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- AVISO POR EMAIL de cada reserva nueva de la web (función "avisar-reserva").
-- Si el aviso falla, la reserva se guarda igual.
-- ---------------------------------------------------------------------
create or replace function public.avisar_reserva_nueva() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_url text := current_setting('app.funciones_url', true);
begin
  if new.origen = 'web' then
    begin
      perform net.http_post(
        url := coalesce(nullif(v_url,''), 'https://SIN-CONFIGURAR') || '/avisar-reserva',
        body := jsonb_build_object('id', new.id),
        headers := '{"Content-Type":"application/json"}'::jsonb);
    exception when others then null;   -- sin pg_net o sin conexión: no frena la reserva
    end;
  end if;
  return new;
end $$;
drop trigger if exists aromas_avisar on public.reservas;
create trigger aromas_avisar after insert on public.reservas for each row execute function public.avisar_reserva_nueva();
revoke execute on function public.solo_invitados(), public.alta_admin(), public.avisar_reserva_nueva() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- DATOS INICIALES (se editan después desde el panel)
-- ---------------------------------------------------------------------
insert into public.ajustes (id) values (true) on conflict do nothing;

insert into public.cabanas (slug, nombre, etiqueta, descripcion, capacidad, habitaciones, precio_base, minimo_noches, equipamiento, foto, orden)
select * from (values
  ('sofia',  'Sofía',  'La más amplia',
   'La más amplia del complejo. Deck propio, luz natural y ese silencio de campo que se siente desde que entrás.',
   4::smallint, 2::smallint, 35000, 2::smallint,
   array['2 habitaciones','Baño privado','Cocina equipada','Parrilla propia','WiFi','Ropa de cama y toallas','Deck propio','Pileta del complejo'],
   'fotos/cabana-1.jpg', 1::smallint),
  ('olivia', 'Olivia', 'Más elegida',
   'La preferida de las familias. Cómoda, práctica y con todo lo que necesitás para que los chicos disfruten al máximo.',
   4::smallint, 2::smallint, 33000, 2::smallint,
   array['2 habitaciones','Baño privado','Cocina equipada','Parrilla propia','WiFi','Ropa de cama y toallas','Pileta del complejo'],
   'fotos/cabana-2.jpg', 2::smallint),
  ('emma',   'Emma',   'Ideal parejas',
   'Con vista al jardín y rodeada de verde. Ideal para una escapada en pareja con calma, fogón y cielo estrellado.',
   4::smallint, 2::smallint, 33000, 2::smallint,
   array['2 habitaciones','Baño privado','Cocina equipada','Parrilla propia','WiFi','Ropa de cama y toallas','Vista al jardín','Pileta del complejo'],
   'fotos/cabana-3.jpg', 3::smallint)
) v(slug, nombre, etiqueta, descripcion, capacidad, habitaciones, precio_base, minimo_noches, equipamiento, foto, orden)
where not exists (select 1 from public.cabanas);

insert into public.preguntas (pregunta, respuesta, orden)
select * from (values
  ('¿Cuánto cuesta por noche?', 'Depende de la cabaña y de la fecha. En la sección "Disponibilidad y precios" ves el precio exacto de cada noche y el total de tu estadía antes de reservar.', 1::smallint),
  ('¿Para cuántas personas es cada cabaña?', 'Cada cabaña es para hasta 4 personas y tiene 2 habitaciones.', 2::smallint),
  ('¿Qué incluye el precio?', 'Ropa de cama, toallas, WiFi, cocina equipada, parrilla propia y uso de la pileta del complejo. No incluye leña ni carbón, ni desayuno.', 3::smallint),
  ('¿Cómo se confirma la reserva?', 'Elegís fechas y cabaña, enviás la solicitud y te mostramos los datos para transferir la seña. Cuando recibimos la seña, te confirmamos por WhatsApp. Sin intermediarios ni comisiones.', 4::smallint),
  ('¿Aceptan mascotas?', 'Sí, con aviso previo. Marcalo en el formulario de reserva y lo coordinamos.', 5::smallint),
  ('¿Cuál es el horario de entrada y salida?', 'La entrada es a partir de las 14 hs y la salida hasta las 11 hs. Si necesitás otro horario, avisanos y vemos si se puede.', 6::smallint),
  ('¿Qué hay cerca?', 'Las termas de Colón a 5 minutos, el río Uruguay y las playas a 10 minutos, y el Parque Nacional El Palmar a unos 50 km.', 7::smallint),
  ('¿Puedo cancelar?', 'Si cancelás con más de 15 días de anticipación te devolvemos la seña. Con menos tiempo la seña no se devuelve, pero podés usarla para otra fecha dentro de los 6 meses.', 8::smallint)
) v(pregunta, respuesta, orden)
where not exists (select 1 from public.preguntas);
