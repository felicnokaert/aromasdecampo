-- Textos de la página de inicio editables desde el panel
create table if not exists public.textos (
  clave text primary key,
  valor text not null,
  etiqueta text not null,
  grupo text not null,
  orden smallint not null default 0,
  editado timestamptz not null default now()
);
alter table public.textos enable row level security;
create policy textos_leer on public.textos for select using (true);
create policy textos_admin on public.textos for all to authenticated using (public.es_admin()) with check (public.es_admin());
grant select on public.textos to anon, authenticated;
grant insert, update on public.textos to authenticated;
insert into public.textos (clave, valor, etiqueta, grupo, orden) values
('portada_lugar','Colón, Entre Ríos','Lugar (arriba del título)','Portada',1),
('portada_titulo','Cabañas de tronco, *sin apuro.*','Título grande','Portada',2),
('portada_bajada','Pileta, parque y parrilla individual a unos kilómetros del río Uruguay. Mirá los precios en pesos y las fechas libres, y reservá directo con nosotros.','Texto debajo del título','Portada',3),
('cabanas_titulo','Tres cabañas *de tronco.*','Título','Cabañas',4),
('cabanas_intro','Olivia, Sofía y Emma, rodeadas de parque y a unos pasos de la pileta. Hoy se alquilan Olivia y Sofía; Emma abre más adelante.','Texto','Cabañas',5),
('cabanas_aviso','alquilamos solo el alojamiento, así que traé ropa de cama y toallas. No se aceptan mascotas.','"Para tener en cuenta"','Cabañas',6),
('estadia_titulo','Colón no se conoce *en un fin de semana.*','Título','Estadías',7),
('estadia_intro','El mínimo es de 2 noches (3 en temporada alta), pero lo que recomendamos es de 4 noches a dos semanas. Mové la barra y mirá lo que entra.','Texto','Estadías',8),
('fotos_titulo','Así se ve *de cerca.*','Título','Fotos',9),
('fotos_intro','Fotos de las cabañas, la pileta y el parque, sin filtros de catálogo. Tocá cualquiera para verla grande.','Texto','Fotos',10),
('opiniones_titulo','Lo cuentan *los que vinieron.*','Título','Opiniones',11),
('ubicacion_titulo','En Colón, *Entre Ríos.*','Título','Cómo llegar',12),
('preguntas_titulo','Antes de *reservar.*','Título','Preguntas',13),
('preguntas_intro','Si te queda una duda, escribinos por WhatsApp y te contesta Rubén.','Texto','Preguntas',14),
('cierre_titulo','¿Cuántas noches *te quedás?*','Título','Cierre (franja naranja)',15),
('cierre_texto','Elegí las fechas y mirá el precio total al instante. La reserva queda firme con la seña.','Texto','Cierre (franja naranja)',16)
on conflict (clave) do nothing;
