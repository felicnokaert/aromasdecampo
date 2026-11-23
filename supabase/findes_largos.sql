-- Fines de semana largos: recargo propio y se reservan completos (sin noches sueltas)
alter table public.ajustes add column if not exists recargo_feriado_pct smallint not null default 0 check (recargo_feriado_pct between 0 and 300);
alter table public.ajustes add column if not exists feriado_completo boolean not null default true;
grant select (recargo_feriado_pct, feriado_completo) on public.ajustes to anon, authenticated;

create or replace function public.precio_noche(p_cabana smallint, p_fecha date, p_personas smallint default 2) returns integer
language plpgsql stable security definer set search_path = '' as $$
declare
  v_base integer; v_finde smallint; v_precio numeric; v_um_pct smallint; v_um_dias smallint; v_fer_pct smallint;
  v_extra integer; t public.temporadas; r public.temporadas;
begin
  select precio_base, extra_persona into v_base, v_extra from public.cabanas where id = p_cabana;
  if v_base is null then return null; end if;
  select recargo_finde_pct, ultimo_minuto_pct, ultimo_minuto_dias, recargo_feriado_pct into v_finde, v_um_pct, v_um_dias, v_fer_pct from public.ajustes where id;
  -- 1) precio de base: la fecha especial más específica que tenga precio (o el precio común)
  select * into t from public.temporadas x
   where p_fecha between x.desde and x.hasta and (x.cabana_id is null or x.cabana_id = p_cabana) and x.precio is not null
   order by (x.cabana_id is null), (x.hasta - x.desde), x.id desc limit 1;
  if t.precio is not null then
    v_precio := t.precio + greatest(coalesce(p_personas,2) - 2, 0) * coalesce(t.extra_persona, v_extra);
  else
    v_precio := v_base + greatest(coalesce(p_personas,2) - 2, 0) * v_extra;
  end if;
  -- 2) recargo: el de la fecha especial más específica sin precio propio; si es finde largo, el recargo general de findes largos
  select * into r from public.temporadas x
   where p_fecha between x.desde and x.hasta and (x.cabana_id is null or x.cabana_id = p_cabana) and x.precio is null
     and (x.recargo_pct <> 0 or x.tipo = 'feriado')
   order by (x.cabana_id is null), (x.hasta - x.desde), x.id desc limit 1;
  if r.id is not null and (t.id is null or (r.hasta - r.desde) <= (t.hasta - t.desde)) then
    v_precio := v_precio * (1 + (case when r.recargo_pct <> 0 then r.recargo_pct when r.tipo = 'feriado' then coalesce(v_fer_pct,0) else 0 end) / 100.0);
  end if;
  if extract(isodow from p_fecha) in (5, 6) then   -- noches de viernes y sábado
    v_precio := v_precio * (1 + coalesce(v_finde,0) / 100.0);
  end if;
  if coalesce(v_um_pct,0) > 0 and p_fecha - current_date < coalesce(v_um_dias,3) then   -- último minuto
    v_precio := v_precio * (1 - v_um_pct / 100.0);
  end if;
  return (round(v_precio / 500.0) * 500)::integer;
end $$;

create or replace function public.cotizar(p_cabana smallint, p_entrada date, p_salida date, p_personas smallint default 2)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_noches int := p_salida - p_entrada; v_total int := 0; v_min smallint := 1;
  v_d date; v_libre boolean := true; v_sena_pct smallint; v_cap smallint; v_completo boolean; f public.temporadas; v_err text;
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
  v_d := p_entrada;
  while v_d < p_salida loop
    v_total := v_total + public.precio_noche(p_cabana, v_d, coalesce(p_personas, 2::smallint));
    if public.noche_ocupada(p_cabana, v_d) then v_libre := false; end if;
    v_min := greatest(v_min, public.minimo_noches(p_cabana, v_d));   -- si toca temporada alta o finde largo, rige su mínimo
    v_d := v_d + 1;
  end loop;
  -- un finde largo no se corta: si la estadía toca una de sus noches, tiene que incluirlas todas
  select feriado_completo into v_completo from public.ajustes where id;
  if coalesce(v_completo, true) and v_noches < 5 then   -- estadías de 5 noches o más pueden tocar una parte
    select * into f from public.temporadas x
     where x.tipo = 'feriado' and (x.cabana_id is null or x.cabana_id = p_cabana)
       and x.desde < p_salida and x.hasta >= p_entrada
       and (p_entrada > greatest(x.desde, current_date) or p_salida <= x.hasta)
     order by x.desde limit 1;
    if f.id is not null then
      v_err := format('%s se alquila completo: noches del %s al %s (salida el %s). Podés sumar noches antes o después.',
        regexp_replace(f.nombre, '^Finde (largo|XL): ', 'El fin de semana largo de '),
        to_char(greatest(f.desde, current_date), 'DD/MM'), to_char(f.hasta, 'DD/MM'), to_char(f.hasta + 1, 'DD/MM'));
    end if;
  end if;
  select sena_pct into v_sena_pct from public.ajustes where id;
  if v_noches >= 7 then
    v_total := (round(v_total * (1 - coalesce((select descuento_semana_pct from public.ajustes where id),0) / 100.0) / 500.0) * 500)::int;
  end if;
  return jsonb_build_object(
    'ok', v_libre and v_noches >= v_min and v_err is null and coalesce(p_personas,2) between 1 and v_cap,
    'error', case when coalesce(p_personas,2) > v_cap then format('Esta cabaña es para hasta %s personas.', v_cap)
                  when not v_libre then 'Alguna de esas noches ya está ocupada. Probá con otras fechas u otra cabaña.'
                  when v_err is not null then v_err
                  when v_noches < v_min then format('Para esas fechas la estadía mínima es de %s noches.', v_min)
             end,
    'noches', v_noches, 'minimo', v_min, 'total', v_total, 'capacidad', v_cap, 'personas', coalesce(p_personas,2),
    'consultas', (select count(*) from public.reservas r where r.cabana_id = p_cabana and r.estado = 'pendiente'
                   and r.entrada < p_salida and r.salida > p_entrada and r.creada > now() - interval '7 days'),
    'sena', (round(v_total * coalesce(v_sena_pct,30) / 100.0 / 100) * 100)::int);
end $$;
