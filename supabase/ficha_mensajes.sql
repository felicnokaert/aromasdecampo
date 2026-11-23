-- Ficha de llegada: el huésped confirmado ve cómo llegar y carga su hora de llegada
alter table public.reservas add column if not exists llegada_hora text;
alter table public.reservas add column if not exists llegada_nota text;
alter table public.reservas add column if not exists llegada_cargada timestamptz;

create or replace function public.datos_llegada(p_codigo text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r public.reservas; v_cab text; a public.ajustes;
begin
  select * into r from public.reservas where codigo = upper(trim(coalesce(p_codigo,''))) and estado = 'confirmada' and salida >= current_date;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'No encontramos una reserva confirmada con ese código.'); end if;
  select nombre into v_cab from public.cabanas where id = r.cabana_id;
  select * into a from public.ajustes where id;
  return jsonb_build_object('ok', true, 'nombre', split_part(coalesce(r.nombre,''), ' ', 1), 'cabana', v_cab,
    'entrada', r.entrada, 'salida', r.salida, 'personas', r.personas, 'checkin', a.checkin, 'checkout', a.checkout,
    'info', a.info_llegada, 'whatsapp', a.whatsapp, 'hora', r.llegada_hora, 'nota', r.llegada_nota);
end $$;

create or replace function public.guardar_llegada(p_codigo text, p_hora text, p_personas smallint, p_nota text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v jsonb;
begin
  v := public.datos_llegada(p_codigo);
  if not (v->>'ok')::boolean then return v; end if;
  if length(coalesce(p_hora,'')) > 40 or length(coalesce(p_nota,'')) > 500 or coalesce(p_personas, 1) not between 1 and 6 then
    return jsonb_build_object('ok', false, 'error', 'Revisá los datos.');
  end if;
  update public.reservas set llegada_hora = nullif(trim(p_hora),''), llegada_nota = nullif(trim(p_nota),''),
    personas = coalesce(p_personas, personas), llegada_cargada = now()
  where codigo = upper(trim(p_codigo));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.datos_llegada(text) from public;
revoke all on function public.guardar_llegada(text, text, smallint, text) from public;
grant execute on function public.datos_llegada(text) to anon, authenticated;
grant execute on function public.guardar_llegada(text, text, smallint, text) to anon, authenticated;

-- Mensajes de WhatsApp editables desde el panel
create table if not exists public.mensajes (
  id bigint generated always as identity primary key,
  clave text unique,          -- los que usa el panel automáticamente: pedido, sena, llegada, opinion
  titulo text not null,
  texto text not null,
  orden integer not null default 0
);
alter table public.mensajes enable row level security;
create policy mensajes_admin on public.mensajes for all to authenticated using (public.es_admin()) with check (public.es_admin());
grant select, insert, update, delete on public.mensajes to authenticated;
insert into public.mensajes (clave, titulo, texto, orden) values
('pedido', 'Pedido recibido: pasar el alias', 'Hola {nombre}! Te escribo de Aromas de Campo por tu pedido {codigo} en la cabaña {cabana}, del {entrada} al {salida} ({noches} noches), total {total}.

Para reservar, transferí la seña de {sena} a:
Alias: {alias}
CBU: {cbu}
Titular: {titular}

Cuando la hagas, mandame el comprobante por acá y te confirmo. Hasta que no llegue el comprobante las fechas siguen disponibles. ¡Gracias!', 1),
('sena', 'Seña recibida: reserva confirmada', 'Hola {nombre}! Recibimos tu seña. Tu reserva {codigo} en la cabaña {cabana} del {entrada} al {salida} está CONFIRMADA ✅

En este link tenés cómo llegar, horarios y qué traer, y nos podés decir a qué hora llegan: {ficha}

¡Te esperamos! Aromas de Campo', 2),
('llegada', 'Recordatorio antes de llegar', 'Hola {nombre}! Te esperamos el {entrada} en la cabaña {cabana} 🌿 La entrada es desde las {checkin} y la salida el {salida} hasta las {checkout}.

Acordate de traer sábanas, fundas y toallas. Cómo llegar y lugares para visitar con descuentos: {ficha}

¡Buen viaje!', 3),
('opinion', 'Después de la estadía: pedir opinión', 'Hola {nombre}! Gracias por elegir Aromas de Campo 🌿 ¿Nos dejás tu opinión en Google? Es un minuto y nos ayuda muchísimo a que otras familias nos encuentren: {google}', 4),
(null, 'Fechas ocupadas', 'Hola {nombre}! Gracias por escribirnos. Las fechas del {entrada} al {salida} ya están reservadas en la cabaña {cabana}. Si querés, fijate otras fechas libres acá: {web}/reservas.html', 5)
on conflict (clave) do nothing;
