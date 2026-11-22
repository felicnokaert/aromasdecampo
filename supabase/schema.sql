-- =====================================================================
-- AROMAS DE CAMPO — Sistema de reservas (Supabase / Postgres)
-- Se ejecuta UNA sola vez: Supabase → SQL Editor → pegar todo → Run
-- =====================================================================

create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_net with schema extensions;

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
  precio_base   integer  not null check (precio_base > 0),   -- pesos por noche para 2 personas
  extra_persona integer  not null default 0 check (extra_persona >= 0), -- adicional por noche por cada persona más (3ra y 4ta)
  minimo_noches smallint not null default 2 check (minimo_noches between 1 and 30),
  equipamiento  text[]   not null default '{}',
  foto          text,
  orden         smallint not null default 0,
  activa        boolean  not null default true,
  ical_token    uuid     not null default gen_random_uuid()   -- para los links de calendario de Booking/Airbnb
);

-- Fechas con precio propio: temporadas, feriados y días especiales (precio fijo o % sobre el normal).
-- Si cabana_id es null aplica a todas las cabañas.
create table if not exists public.temporadas (
  id            bigint generated always as identity primary key,
  nombre        text not null,
  desde         date not null,
  hasta         date not null,                 -- inclusive
  recargo_pct   smallint not null default 0 check (recargo_pct between -90 and 300),
  precio        integer check (precio > 0),           -- precio fijo por noche para 2 personas (si está, manda sobre el %)
  extra_persona integer check (extra_persona >= 0),   -- adicional por persona extra en estas fechas (si no, el de la cabaña)
  minimo_noches smallint check (minimo_noches between 1 and 30),
  tipo          text not null default 'temporada' check (tipo in ('temporada','feriado','especial')),
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
  externo_uid text,                              -- id de la reserva en Booking/Airbnb (si vino de ahí)
  recordatorio_enviado boolean not null default false,
  resena_pedida boolean not null default false,
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
create unique index if not exists reservas_externo_uid on public.reservas (externo_uid) where externo_uid is not null;

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
  email_avisos      text default 'aranda.ruben@hotmail.com', -- a dónde llegan los avisos de reservas nuevas
  ultimo_minuto_pct  smallint not null default 0 check (ultimo_minuto_pct between 0 and 60),  -- descuento automático
  ultimo_minuto_dias smallint not null default 3 check (ultimo_minuto_dias between 1 and 14), -- si faltan menos de N días
  info_llegada      text,                         -- lo que se le manda al huésped antes de llegar (dirección, horarios…)
  resumen_semanal   boolean not null default true,
  web_url           text not null default 'https://aromasdecampo.vercel.app',
  descuento_semana_pct smallint not null default 0 check (descuento_semana_pct between 0 and 60), -- 7 noches o más
  google_puntaje    numeric(2,1) default 5.0,
  google_cantidad   int default 34,
  google_url        text default 'https://maps.google.com/maps?q=Aromas+de+campo,+Col%C3%B3n,+Entre+R%C3%ADos'
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

-- Calendarios de Booking / Airbnb que se importan cada 30 minutos
create table if not exists public.calendarios_externos (
  id           bigint generated always as identity primary key,
  cabana_id    smallint not null references public.cabanas(id) on delete cascade,
  plataforma   text not null check (plataforma in ('booking','airbnb','otro')),
  url          text not null check (url ~* '^https://'),
  ultima_sync  timestamptz,
  ultimo_error text,
  eventos      int,
  unique (cabana_id, plataforma)
);

-- Avisos importantes para el panel (dobles reservas, errores de sincronización)
create table if not exists public.alertas (
  id      bigint generated always as identity primary key,
  clave   text unique,                         -- evita repetir el mismo aviso
  tipo    text not null default 'aviso' check (tipo in ('doble','sync','aviso')),
  mensaje text not null,
  creada  timestamptz not null default now(),
  vista   boolean not null default false,
  enviada boolean not null default false        -- ya se mandó por email
);

-- Reseñas de huéspedes (se publican solo las aprobadas)
create table if not exists public.resenas (
  id         bigint generated always as identity primary key,
  reserva_id bigint unique references public.reservas(id) on delete set null,
  cabana_id  smallint references public.cabanas(id) on delete set null,
  nombre     text not null,
  ciudad     text,
  estrellas  smallint not null check (estrellas between 1 and 5),
  texto      text not null,
  respuesta  text,
  fuente     text not null default 'web' check (fuente in ('web','google','booking','airbnb','whatsapp','otra')),
  aprobada   boolean not null default false,
  creada     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- FUNCIONES
-- ---------------------------------------------------------------------

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- Precio de UNA noche (redondeado a $500)
drop function if exists public.precio_noche(smallint, date);
create or replace function public.precio_noche(p_cabana smallint, p_fecha date, p_personas smallint default 2) returns integer
language plpgsql stable security definer set search_path = '' as $$
declare
  v_base integer; v_finde smallint; v_pct smallint := 0; v_precio numeric; v_um_pct smallint; v_um_dias smallint;
  v_extra integer; t public.temporadas;
begin
  select precio_base, extra_persona into v_base, v_extra from public.cabanas where id = p_cabana;
  if v_base is null then return null; end if;
  select recargo_finde_pct, ultimo_minuto_pct, ultimo_minuto_dias into v_finde, v_um_pct, v_um_dias from public.ajustes where id;
  -- la fecha especial más específica (la más corta, y la de esa cabaña) gana; solo las que cambian el precio
  select * into t from public.temporadas x
   where p_fecha between x.desde and x.hasta
     and (x.cabana_id is null or x.cabana_id = p_cabana)
     and (x.precio is not null or x.recargo_pct <> 0)
   order by (x.cabana_id is null), (x.hasta - x.desde), x.id desc
   limit 1;
  if t.precio is not null then
    v_precio := t.precio + greatest(coalesce(p_personas,2) - 2, 0) * coalesce(t.extra_persona, v_extra);
  else
    v_precio := (v_base + greatest(coalesce(p_personas,2) - 2, 0) * v_extra) * (1 + coalesce(t.recargo_pct,0) / 100.0);
  end if;
  if extract(isodow from p_fecha) in (5, 6) then   -- noches de viernes y sábado
    v_precio := v_precio * (1 + coalesce(v_finde,0) / 100.0);
  end if;
  if coalesce(v_um_pct,0) > 0 and p_fecha - current_date < coalesce(v_um_dias,3) then   -- último minuto
    v_precio := v_precio * (1 - v_um_pct / 100.0);
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
       and r.estado in ('confirmada','bloqueo'));   -- un pedido sin seña no guarda la fecha
$$;

-- Calendario público: precio y disponibilidad por día, SIN datos de huéspedes
drop function if exists public.calendario_publico(date, date);
create or replace function public.calendario_publico(p_desde date, p_hasta date)
returns table (cabana_id smallint, fecha date, precio integer, libre boolean, nivel text, quedan smallint, ultimo_minuto boolean)
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
         (count(*) filter (where b.libre) over (partition by b.fecha))::smallint,
         (b.libre and (select a.ultimo_minuto_pct > 0 and b.fecha - current_date < a.ultimo_minuto_dias from public.ajustes a where a.id))
    from base b
   order by b.fecha, b.cabana_id;
$$;

-- Cotización de una estadía
drop function if exists public.cotizar(smallint, date, date);
create or replace function public.cotizar(p_cabana smallint, p_entrada date, p_salida date, p_personas smallint default 2)
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
    v_total := v_total + public.precio_noche(p_cabana, v_d, coalesce(p_personas, 2::smallint));
    if public.noche_ocupada(p_cabana, v_d) then v_libre := false; end if;
    v_d := v_d + 1;
  end loop;
  select sena_pct into v_sena_pct from public.ajustes where id;
  if v_noches >= 7 then
    v_total := (round(v_total * (1 - coalesce((select descuento_semana_pct from public.ajustes where id),0) / 100.0) / 500.0) * 500)::int;
  end if;
  return jsonb_build_object(
    'ok', v_libre and v_noches >= v_min and coalesce(p_personas,2) between 1 and v_cap,
    'error', case when coalesce(p_personas,2) > v_cap then format('Esta cabaña es para hasta %s personas.', v_cap)
                  when not v_libre then 'Alguna de esas noches ya está ocupada. Probá con otras fechas u otra cabaña.'
                  when v_noches < v_min then format('Para esas fechas la estadía mínima es de %s noches.', v_min)
             end,
    'noches', v_noches, 'minimo', v_min, 'total', v_total, 'capacidad', v_cap, 'personas', coalesce(p_personas,2),
    'consultas', (select count(*) from public.reservas r where r.cabana_id = p_cabana and r.estado = 'pendiente'
                   and r.entrada < p_salida and r.salida > p_entrada and r.creada > now() - interval '7 days'),
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
  if p_personas is null or p_personas < 1 then
    return jsonb_build_object('ok', false, 'error', 'Indicá cuántas personas van.');
  end if;
  v_cot := public.cotizar(p_cabana, p_entrada, p_salida, p_personas);
  if not (v_cot->>'ok')::boolean then return v_cot; end if;

  select horas_para_senar into v_horas from public.ajustes where id;
  v_vence := now() + make_interval(hours => coalesce(v_horas, 48));

  insert into public.reservas (cabana_id, entrada, salida, nombre, telefono, email, personas,
                               mascota, mensaje, total, sena, estado, origen, vence)
  values (p_cabana, p_entrada, p_salida, trim(p_nombre), trim(p_telefono), nullif(trim(p_email),''),
          p_personas, coalesce(p_mascota,false), nullif(trim(p_mensaje),''),
          (v_cot->>'total')::int, (v_cot->>'sena')::int, 'pendiente', 'web', v_vence)
  returning codigo into v_codigo;

  insert into public.eventos (tipo, detalle) values ('solicitud', v_codigo);

  return v_cot || jsonb_build_object('ok', true, 'codigo', v_codigo, 'vence', v_vence)
               || (select jsonb_build_object('alias', alias, 'cbu', cbu, 'titular', titular) from public.ajustes where id);
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

-- Eventos para el link .ics de cada cabaña (solo fechas, nunca datos del huésped).
-- p_excluir evita devolverle a Booking sus propias reservas (y lo mismo con Airbnb).
create or replace function public.ical_eventos(p_token uuid, p_excluir text default null)
returns table (uid text, entrada date, salida date, resumen text)
language sql stable security definer set search_path = '' as $$
  select 'aromas-' || r.id::text, r.entrada, r.salida,
         case when r.estado = 'bloqueo' then 'No disponible' else 'Reservado' end
    from public.reservas r join public.cabanas c on c.id = r.cabana_id
   where c.ical_token = p_token
     and r.salida >= current_date - 1
     and r.estado in ('confirmada','bloqueo')
     and (p_excluir is null or r.origen <> p_excluir);
$$;

-- Recibe los eventos leídos de un calendario de Booking/Airbnb y los vuelca como reservas.
-- La llama solo la función "sincronizar" (con permisos de servidor).
create or replace function public.sincronizar_eventos(p_cal bigint, p_eventos jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  c public.calendarios_externos; e jsonb; v_uid text; v_ent date; v_sal date; v_bloqueo boolean;
  v_nuevas int := 0; v_canceladas int := 0; v_dobles int := 0; v_uids text[] := '{}'; v_choque public.reservas; v_id bigint;
  v_nombre_cab text; v_plat text;
begin
  select * into c from public.calendarios_externos where id = p_cal;
  if c.id is null then return jsonb_build_object('ok', false); end if;
  select nombre into v_nombre_cab from public.cabanas where id = c.cabana_id;
  v_plat := initcap(c.plataforma);

  for e in select * from jsonb_array_elements(coalesce(p_eventos, '[]')) loop
    v_ent := (e->>'entrada')::date; v_sal := (e->>'salida')::date;
    continue when v_ent is null or v_sal is null or v_sal <= v_ent or v_sal < current_date;
    v_uid := c.plataforma || ':' || c.cabana_id || ':' || left(e->>'uid', 200);
    v_uids := v_uids || v_uid;
    -- "Not available"/"CLOSED" = días que cerró el anfitrión (o el eco de nuestras propias fechas)
    v_bloqueo := coalesce(e->>'resumen','') ~* '(not available|closed|blocked|no disponible|bloquead)';

    select id into v_id from public.reservas where externo_uid = v_uid;
    if v_id is not null then
      begin
        update public.reservas set entrada = v_ent, salida = v_sal, estado = case when v_bloqueo then 'bloqueo' else 'confirmada' end
         where id = v_id and (entrada <> v_ent or salida <> v_sal or estado = 'cancelada');
      exception when exclusion_violation then null;
      end;
      continue;
    end if;

    -- eco: la plataforma nos devuelve cerradas las mismas fechas que le mandamos nosotros
    if v_bloqueo and exists (select 1 from public.reservas r where r.cabana_id = c.cabana_id and r.entrada = v_ent and r.salida = v_sal
                               and r.origen <> c.plataforma and r.estado in ('confirmada','bloqueo')) then
      continue;
    end if;

    begin
      insert into public.reservas (cabana_id, entrada, salida, estado, origen, nombre, externo_uid, notas)
      values (c.cabana_id, v_ent, v_sal, case when v_bloqueo then 'bloqueo' else 'confirmada' end,
              c.plataforma, case when v_bloqueo then null else 'Reserva de ' || v_plat end, v_uid,
              case when v_bloqueo then 'Cerrado en ' || v_plat end);
      v_nuevas := v_nuevas + 1;
      -- un pedido de la web (falta seña) sobre las mismas fechas: avisar
      select * into v_choque from public.reservas
       where cabana_id = c.cabana_id and estado = 'pendiente' and creada > now() - interval '14 days'
         and entrada < v_sal and salida > v_ent limit 1;
      if v_choque.id is not null and not v_bloqueo then
        insert into public.alertas (clave, tipo, mensaje) values ('pend:' || v_uid, 'doble',
          format('Entró una reserva de %s en %s (%s al %s) y se pisa con el pedido web de %s (código %s), que todavía no pagó la seña. Avisale a %s que esas fechas ya no están.',
                 v_plat, v_nombre_cab, to_char(v_ent,'DD/MM'), to_char(v_sal,'DD/MM'), v_choque.nombre, v_choque.codigo, v_choque.nombre))
        on conflict (clave) do nothing;
      end if;
    exception when exclusion_violation then
      -- las fechas ya estaban ocupadas acá
      if not v_bloqueo then
        select * into v_choque from public.reservas
         where cabana_id = c.cabana_id and estado in ('confirmada','bloqueo') and entrada < v_sal and salida > v_ent
           and coalesce(externo_uid,'') <> v_uid limit 1;
        -- si es el eco exacto de una reserva nuestra no es problema; si no, es una doble reserva real
        if v_choque.id is not null and not (v_choque.entrada = v_ent and v_choque.salida = v_sal and v_choque.origen not in ('booking','airbnb')) then
          insert into public.alertas (clave, tipo, mensaje) values ('doble:' || v_uid, 'doble',
            format('⚠️ DOBLE RESERVA en %s: %s tiene una reserva del %s al %s, pero esas fechas ya estaban ocupadas por %s. Llamá a la plataforma o al huésped hoy.',
                   v_nombre_cab, v_plat, to_char(v_ent,'DD/MM'), to_char(v_sal,'DD/MM'),
                   coalesce(v_choque.nombre, 'un bloqueo')))
          on conflict (clave) do nothing;
          v_dobles := v_dobles + 1;
        end if;
      end if;
    end;
  end loop;

  -- lo que desapareció del calendario externo (cancelado allá) se libera acá
  update public.reservas set estado = 'cancelada', notas = coalesce(notas || ' · ', '') || 'Cancelada en ' || v_plat
   where cabana_id = c.cabana_id and origen = c.plataforma and externo_uid is not null
     and estado <> 'cancelada' and salida >= current_date and not (externo_uid = any (v_uids));
  get diagnostics v_canceladas = row_count;

  update public.calendarios_externos set ultima_sync = now(), ultimo_error = null, eventos = jsonb_array_length(coalesce(p_eventos,'[]'))
   where id = p_cal;
  return jsonb_build_object('ok', true, 'nuevas', v_nuevas, 'canceladas', v_canceladas, 'dobles', v_dobles);
end $$;

-- Reseñas: el huésped entra con su código de reserva
create or replace function public.datos_resena(p_codigo text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r public.reservas; v_cab text;
begin
  select * into r from public.reservas where codigo = upper(trim(p_codigo)) and estado = 'confirmada';
  if r.id is null or r.entrada > current_date then
    return jsonb_build_object('ok', false, 'error', 'No encontramos una estadía con ese código.');
  end if;
  if exists (select 1 from public.resenas where reserva_id = r.id) then
    return jsonb_build_object('ok', false, 'error', '¡Ya dejaste tu opinión! Muchas gracias 🌿');
  end if;
  select nombre into v_cab from public.cabanas where id = r.cabana_id;
  return jsonb_build_object('ok', true, 'nombre', split_part(coalesce(r.nombre,''), ' ', 1), 'cabana', v_cab,
                            'entrada', r.entrada, 'salida', r.salida);
end $$;

create or replace function public.dejar_resena(p_codigo text, p_estrellas smallint, p_texto text, p_nombre text, p_ciudad text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v jsonb; r public.reservas;
begin
  v := public.datos_resena(p_codigo);
  if not (v->>'ok')::boolean then return v; end if;
  if p_estrellas not between 1 and 5 or length(trim(coalesce(p_texto,''))) < 5 or length(p_texto) > 1500
     or length(trim(coalesce(p_nombre,''))) < 2 or length(p_nombre) > 60 or length(coalesce(p_ciudad,'')) > 60 then
    return jsonb_build_object('ok', false, 'error', 'Completá las estrellas, tu nombre y unas palabras.');
  end if;
  select * into r from public.reservas where codigo = upper(trim(p_codigo));
  insert into public.resenas (reserva_id, cabana_id, nombre, ciudad, estrellas, texto, fuente)
  values (r.id, r.cabana_id, trim(p_nombre), nullif(trim(p_ciudad),''), p_estrellas, trim(p_texto), 'web');
  insert into public.alertas (clave, tipo, mensaje) values ('resena:' || r.id, 'aviso',
    format('⭐ %s dejó una reseña de %s estrellas. Revisala en Más → Reseñas para publicarla.', trim(p_nombre), p_estrellas))
  on conflict (clave) do nothing;
  return jsonb_build_object('ok', true);
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
alter table public.calendarios_externos enable row level security;
alter table public.alertas    enable row level security;
alter table public.resenas    enable row level security;

drop policy if exists calext_admin on public.calendarios_externos;
create policy calext_admin on public.calendarios_externos for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists alertas_admin on public.alertas;
create policy alertas_admin on public.alertas for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists resenas_leer on public.resenas;
create policy resenas_leer on public.resenas for select using (aprobada or public.es_admin());
drop policy if exists resenas_admin on public.resenas;
create policy resenas_admin on public.resenas for all to authenticated using (public.es_admin()) with check (public.es_admin());

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
revoke select on public.ajustes from anon;
grant select (id, whatsapp, sena_pct, horas_para_senar, checkin, checkout, recargo_finde_pct, aviso, ultimo_minuto_pct, ultimo_minuto_dias, web_url,
               descuento_semana_pct, google_puntaje, google_cantidad, google_url)
  on public.ajustes to anon;
revoke execute on all functions in schema public from public, anon;
grant execute on function public.calendario_publico(date, date) to anon, authenticated;
grant execute on function public.cotizar(smallint, date, date, smallint) to anon, authenticated;
grant execute on function public.solicitar_reserva(smallint, date, date, text, text, text, smallint, boolean, text) to anon, authenticated;
grant execute on function public.registrar_evento(text, text, text) to anon, authenticated;
grant execute on function public.ical_eventos(uuid, text) to anon, authenticated;
grant execute on function public.datos_resena(text) to anon, authenticated;
grant execute on function public.dejar_resena(text, smallint, text, text, text) to anon, authenticated;
revoke execute on function public.sincronizar_eventos(bigint, jsonb) from public, anon, authenticated;
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
declare v_url text := 'https://censvpqswmnnvhjorlpk.supabase.co/functions/v1';
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

insert into public.cabanas (slug, nombre, etiqueta, descripcion, capacidad, habitaciones, precio_base, extra_persona, minimo_noches, equipamiento, foto, orden)
select * from (values
  ('sofia',  'Sofía',  'La más amplia',
   'La más amplia del complejo. Deck propio, luz natural y ese silencio de campo que se siente desde que entrás.',
   4::smallint, 2::smallint, 90000, 7500, 2::smallint,
   array['2 habitaciones','Baño privado','Cocina equipada','Parrilla individual','WiFi','Deck propio','Pileta del complejo'],
   'fotos/cabana-1.jpg', 1::smallint),
  ('olivia', 'Olivia', 'Más elegida',
   'La preferida de las familias. Cómoda, práctica y con todo lo que necesitás para que los chicos disfruten al máximo.',
   4::smallint, 2::smallint, 90000, 7500, 2::smallint,
   array['2 habitaciones','Baño privado','Cocina equipada','Parrilla individual','WiFi','Pileta del complejo'],
   'fotos/cabana-2.jpg', 2::smallint),
  ('emma',   'Emma',   'Ideal parejas',
   'Con vista al jardín y rodeada de verde. Ideal para una escapada en pareja con calma, fogón y cielo estrellado.',
   4::smallint, 2::smallint, 90000, 7500, 2::smallint,
   array['2 habitaciones','Baño privado','Cocina equipada','Parrilla individual','WiFi','Vista al jardín','Pileta del complejo'],
   'fotos/cabana-3.jpg', 3::smallint)
) v(slug, nombre, etiqueta, descripcion, capacidad, habitaciones, precio_base, extra_persona, minimo_noches, equipamiento, foto, orden)
where not exists (select 1 from public.cabanas);
update public.cabanas set activa = false where slug = 'emma' and not exists (select 1 from public.reservas);  -- por ahora se alquilan Olivia y Sofía

-- Temporada alta: mínimo 3 noches (fechas a confirmar por Rubén) + fines de semana largos confirmados, sin precio todavía
insert into public.temporadas (nombre, desde, hasta, recargo_pct, minimo_noches, tipo)
select * from (values
  ('Temporada alta (verano)',            date '2026-12-15', date '2027-02-28', 0::smallint, 3::smallint, 'temporada'),
  ('Finde largo: Inmaculada Concepción', date '2026-12-05', date '2026-12-07', 0::smallint, null::smallint, 'feriado'),
  ('Finde largo: Navidad',               date '2026-12-24', date '2026-12-26', 0::smallint, null::smallint, 'feriado'),
  ('Finde largo: Año Nuevo',             date '2026-12-31', date '2027-01-02', 0::smallint, null::smallint, 'feriado'),
  ('Finde largo: Carnaval',              date '2027-02-06', date '2027-02-08', 0::smallint, null::smallint, 'feriado'),
  ('Finde XL: Semana Santa',             date '2027-03-24', date '2027-03-27', 0::smallint, null::smallint, 'feriado'),
  ('Finde largo: Malvinas',              date '2027-04-01', date '2027-04-03', 0::smallint, null::smallint, 'feriado'),
  ('Finde largo: Independencia',         date '2027-07-09', date '2027-07-10', 0::smallint, null::smallint, 'feriado')
) v(nombre, desde, hasta, recargo_pct, minimo_noches, tipo)
where not exists (select 1 from public.temporadas);

insert into public.preguntas (pregunta, respuesta, orden)
select * from (values
  ('¿Cuánto cuesta por noche?', 'Depende de cuántos son y de la fecha. Para 2 personas y para familias de hasta 4 tenemos tarifas distintas. En "Disponibilidad y precios" elegís fechas y personas y ves el total exacto antes de reservar.', 1::smallint),
  ('¿Para cuántas personas es cada cabaña?', 'Cada cabaña es para hasta 4 personas y tiene 2 habitaciones.', 2::smallint),
  ('¿Cuál es la estadía mínima?', 'En temporada alta, 3 noches. El resto del año, 2 noches.', 3::smallint),
  ('¿Qué incluye el precio?', 'Solo el alojamiento: la cabaña equipada, parrilla individual y uso de la pileta del complejo. No incluye ropa de cama ni toallas, desayuno, leña ni carbón: traé lo que necesites.', 3::smallint),
  ('¿Cómo se confirma la reserva?', 'Elegís fechas y cabaña, enviás la solicitud y te mostramos los datos para transferir la seña del 30 %. La reserva queda confirmada cuando recibimos la seña: hasta ese momento las fechas siguen disponibles para otras personas. Sin intermediarios ni comisiones.', 4::smallint),
  ('¿Aceptan mascotas?', 'No, no se aceptan mascotas.', 5::smallint),
  ('¿Cuál es el horario de entrada y salida?', 'La entrada es a partir de las 14 hs y la salida hasta las 11 hs. Si necesitás otro horario, avisanos y vemos si se puede.', 6::smallint),
  ('¿Qué hay cerca?', 'Colón tiene termas frente al río, cinco playas sobre el río Uruguay y el Parque Nacional El Palmar a unos 50 km. Mirá nuestra Guía de Colón en la web para armar tu escapada.', 7::smallint),
  ('¿Puedo cancelar?', 'Escribinos por WhatsApp y te contamos las condiciones según tu fecha.', 8::smallint)
) v(pregunta, respuesta, orden)
where not exists (select 1 from public.preguntas);
