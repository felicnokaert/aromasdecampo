alter table public.calendarios_externos add column if not exists error_desde timestamptz;
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
      -- aviso de reserva nueva que entró por la plataforma (va al panel y por email)
      if not v_bloqueo then
        insert into public.alertas (clave, tipo, mensaje) values ('nueva:' || v_uid, 'aviso',
          format('📅 Nueva reserva de %s en %s: llega el %s y se va el %s (%s noches). Ya quedó bloqueada en la web y en las otras plataformas. Cargá el monto y el nombre en Reservas cuando lo veas en %s.',
                 v_plat, v_nombre_cab, to_char(v_ent,'DD/MM'), to_char(v_sal,'DD/MM'), v_sal - v_ent, v_plat))
        on conflict (clave) do nothing;
      end if;
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
  with c2 as (
    update public.reservas r set estado = 'cancelada', notas = coalesce(r.notas || ' · ', '') || 'Cancelada en ' || v_plat
     where r.cabana_id = c.cabana_id and r.origen = c.plataforma and r.externo_uid is not null
       and r.estado <> 'cancelada' and r.salida >= current_date and not (r.externo_uid = any (v_uids))
    returning r.externo_uid, r.entrada, r.salida, (r.nombre is not null and r.notas not like 'Cerrado en%') as era_reserva
  ), avisos as (
    insert into public.alertas (clave, tipo, mensaje)
    select 'cancel:' || externo_uid, 'aviso',
           format('❌ Se canceló en %s la reserva de %s del %s al %s. Esas fechas ya quedaron libres en la web.',
                  v_plat, v_nombre_cab, to_char(entrada,'DD/MM'), to_char(salida,'DD/MM'))
      from c2 where era_reserva
    on conflict (clave) do nothing
  )
  select count(*) into v_canceladas from c2;

  update public.calendarios_externos set ultima_sync = now(), ultimo_error = null, error_desde = null, eventos = jsonb_array_length(coalesce(p_eventos,'[]'))
   where id = p_cal;
  return jsonb_build_object('ok', true, 'nuevas', v_nuevas, 'canceladas', v_canceladas, 'dobles', v_dobles);
end $$;
revoke execute on function public.sincronizar_eventos(bigint, jsonb) from public, anon, authenticated;
select cron.alter_job((select jobid from cron.job where jobname='aromas-sincronizar'), schedule := '*/15 * * * *');
