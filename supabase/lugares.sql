-- Lugares para visitar y comer, con cupones de descuento (editable desde el panel)
create table if not exists public.lugares (
  id bigint generated always as identity primary key,
  nombre text not null,
  categoria text not null default 'paseos' check (categoria in ('termas','playas','paseos','historia','naturaleza','comer','compras')),
  localidad text,
  distancia text,
  descripcion text,
  direccion text,
  telefono text,
  maps_url text,
  cupon text,
  destacado boolean not null default false,
  visible boolean not null default true,
  orden integer not null default 0,
  creado timestamptz not null default now()
);
alter table public.lugares enable row level security;
create policy lugares_leer on public.lugares for select using (visible or public.es_admin());
create policy lugares_admin on public.lugares for all to authenticated using (public.es_admin()) with check (public.es_admin());
grant select on public.lugares to anon, authenticated;
grant insert, update, delete on public.lugares to authenticated;
insert into public.lugares (nombre, categoria, localidad, distancia, descripcion, direccion, cupon, destacado, orden)
select * from (values
('Termas de Colón','termas','Colón','5 min','Trece piscinas al aire libre y cubiertas, frente al río Uruguay, con sector de toboganes. Abre todos los días del año.','Cepeda 100, Colón','Descuento en la entrada para huéspedes de Aromas de Campo: pedile el cupón a Rubén.',true,1),
('Termas de San José','termas','San José','5 min','Predio de 36 hectáreas frente al río, con piscinas cubiertas y toboganes. Con la entrada también se puede usar el balneario de San José.','Evequoz e Int. Beltrán Moreira, San José',null,false,2),
('Termas Villa Elisa','termas','Villa Elisa','~30 km','Complejo de 41 hectáreas con más de 10 piscinas de agua salada a 41 °C, spa y un lago. Conviene ir el día entero.','Ruta Nacional 130 km 20, Villa Elisa',null,false,3),
('Balneario Norte','playas','Colón','5 min','La playa más tranquila de Colón, en el extremo norte de la costa. Ideal para ir con chicos.','Colón',null,true,4),
('Playas Piedras Coloradas, Playa Nueva y Playa Honda','playas','Colón','5 min','Las playas con más movimiento: paradores, música, vóley y deportes náuticos.','Costanera de Colón',null,false,5),
('Isla Caridad y Punta Colón','playas','Colón','5 min','Arena clara frente a las islas del río Uruguay. Hay paseos en lancha a las islas.','Colón',null,false,6),
('Balneario San José','playas','San José','5 min','Playa sobre el río Uruguay junto a las termas de San José.','San José',null,false,7),
('Costanera de Colón','paseos','Colón','5 min','El paseo clásico: faroles, palmeras y tapialcitos junto al río. Lindo al atardecer, con vista al puente a Paysandú.','Av. Costanera, Colón',null,true,8),
('Parque Quirós','paseos','Colón','5 min','Parque arbolado sobre la barranca del río, para caminar y tomar mate.','Colón',null,false,9),
('Centro Artesanal La Casona','paseos','Colón','5 min','Artesanías de la zona, frente a la plaza San Martín.','Frente a plaza San Martín, Colón',null,false,10),
('Puente Internacional Gral. Artigas','paseos','Colón',null,'Une Colón con Paysandú (Uruguay). De noche, iluminado, se ve desde la costanera. Para cruzar: documento.','Ruta Nacional 135',null,false,11),
('Molino Forclaz','historia','Colón · San José','~4 km','Molino de 1888 construido por el suizo Juan Bautista Forclaz, Monumento Histórico Nacional. Como no había viento suficiente, molía con mulas.','Camino Colón - San José',null,true,12),
('Museo Histórico Regional de la Colonia San José','historia','San José','10 min','Herramientas, fotos y documentos de las familias que fundaron en 1857 la primera colonia agrícola de Entre Ríos.','Urquiza 1127, San José (frente a la plaza)',null,false,13),
('Museo de Ciencias Naturales Gómez Cadret','historia','San José','10 min','Fósiles de la fauna de la región.','San José',null,false,14),
('Pueblo Liebig','historia','Liebig','~10 km','Pueblo nacido alrededor de un frigorífico inglés que exportaba carne enlatada. Casas de época, el viejo frigorífico y playa.','Pueblo Liebig',null,true,15),
('Palacio San José (Urquiza)','historia','Caseros',null,'La residencia del general Justo José de Urquiza, hoy Museo y Monumento Histórico Nacional. Consultá los horarios antes de ir: suele cerrar lunes y martes.','Ruta Provincial 39 km 128, Caseros',null,true,16),
('Museo Estancia El Porvenir','historia','Villa Elisa','~30 km','Casona del siglo XIX del fundador de Villa Elisa, con la vida de los primeros pobladores.','Villa Elisa',null,false,17),
('Tren Histórico de Villa Elisa','historia','Villa Elisa','~30 km','Tren a vapor entre Villa Elisa y Caseros. Consultá los días de salida.','Estación Villa Elisa',null,false,18),
('Parque Nacional El Palmar','naturaleza','Ubajay','~50 km','Uno de los últimos palmares de yatay, creado en 1966. Senderos, miradores y fauna. Ideal para ir temprano.','Ruta Nacional 14 km 199',null,true,19)
) v where not exists (select 1 from public.lugares);
