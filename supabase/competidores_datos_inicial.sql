insert into public.competidores (booking_id, nombre, es_nuestro, url, distancia, puntaje, opiniones, destacan, servicios) values
 (17734550, 'Aromas de Campo (nosotros)', true, 'https://www.booking.com/hotel/ar/aromas-de-campo-cabanas-de-tronco.html', '—', null, 0, 'Todavía sin opiniones en Booking (en Google: 5,0 con 34)', array['Pileta','Parrilla individual','Aire acondicionado','Wifi','Cocina completa','Estacionamiento']),
 (1958207, 'Cabañas Pulmahue', false, 'https://www.booking.com/hotel/ar/cabanas-pulmahue.html', 'Enfrente (70 m)', 9.3, 76, 'La tranquilidad, la comodidad y la atención', array['Pileta','Pileta todo el año','Parrilla individual','Aire acondicionado','Wifi','Cocina completa','Estacionamiento','Ropa de cama y toallas','Netflix','Cuna gratis']),
 (1962202, 'Aratiri Cabañas', false, 'https://www.booking.com/hotel/ar/aratiri-cabanas-un-lugar-en-el-bosque.html', '1,7 km', 9.7, 54, 'La comodidad y la calidad del servicio', array['Pileta','Pileta todo el año','Aire acondicionado','Wifi','Estacionamiento','Juegos para chicos','Acepta mascotas']),
 (7647427, 'El Sosiego Posada de Campo', false, 'https://www.booking.com/hotel/ar/el-sosiego-posada-de-campo.html', '2 km', 9.4, 53, 'La limpieza', array['Pileta','Aire acondicionado','Wifi','Estacionamiento']),
 (11324893, 'Cabañas Posta Litoral', false, 'https://www.booking.com/hotel/ar/cabanas-posta-litoral.html', '4 km', 9.7, 95, 'La pileta, las vistas y la atención', array['Pileta','Pileta todo el año','Parrilla individual','Aire acondicionado','Wifi','Estacionamiento','Masajes']),
 (4348414, 'Cabañas Rosmar', false, 'https://www.booking.com/hotel/ar/cabanas-rosmar.html', '4 km', 8.6, 33, 'La calle tranquila, la pileta y el equipamiento', array['Pileta','Pileta todo el año','Aire acondicionado','Wifi','Estacionamiento'])
on conflict (booking_id) do update set nombre=excluded.nombre, distancia=excluded.distancia, puntaje=excluded.puntaje, opiniones=excluded.opiniones, destacan=excluded.destacan, servicios=excluded.servicios, actualizado=now();

insert into public.competidor_precios (booking_id, periodo, entrada, salida, personas, disponible, precio_noche) values
 -- Finde largo 8 de diciembre (5 al 7)
 (17734550,'Finde largo 8 de diciembre','2026-12-05','2026-12-07',2,true,173272),
 (1958207,'Finde largo 8 de diciembre','2026-12-05','2026-12-07',2,false,null),
 (1962202,'Finde largo 8 de diciembre','2026-12-05','2026-12-07',2,false,null),
 (7647427,'Finde largo 8 de diciembre','2026-12-05','2026-12-07',2,true,111933),
 (11324893,'Finde largo 8 de diciembre','2026-12-05','2026-12-07',2,false,null),
 (4348414,'Finde largo 8 de diciembre','2026-12-05','2026-12-07',2,false,null),
 -- Finde común (11 al 13 de diciembre)
 (17734550,'Finde común de diciembre','2026-12-11','2026-12-13',2,true,144393),
 (1958207,'Finde común de diciembre','2026-12-11','2026-12-13',2,true,87947),
 (1962202,'Finde común de diciembre','2026-12-11','2026-12-13',2,true,97541),
 (7647427,'Finde común de diciembre','2026-12-11','2026-12-13',2,true,79952),
 (11324893,'Finde común de diciembre','2026-12-11','2026-12-13',2,true,87947),
 (4348414,'Finde común de diciembre','2026-12-11','2026-12-13',2,true,62363),
 (17734550,'Finde común de diciembre','2026-12-11','2026-12-13',4,true,167899),
 (1958207,'Finde común de diciembre','2026-12-11','2026-12-13',4,true,95942),
 (1962202,'Finde común de diciembre','2026-12-11','2026-12-13',4,true,129522),
 (7647427,'Finde común de diciembre','2026-12-11','2026-12-13',4,true,79952),
 (11324893,'Finde común de diciembre','2026-12-11','2026-12-13',4,true,119928),
 (4348414,'Finde común de diciembre','2026-12-11','2026-12-13',4,true,62363),
 -- Navidad (24 al 26)
 (1958207,'Navidad','2026-12-24','2026-12-26',2,false,null),
 (1962202,'Navidad','2026-12-24','2026-12-26',2,false,null),
 (7647427,'Navidad','2026-12-24','2026-12-26',2,false,null),
 (11324893,'Navidad','2026-12-24','2026-12-26',2,false,null),
 (4348414,'Navidad','2026-12-24','2026-12-26',2,false,null),
 -- Año Nuevo (31 al 3)
 (17734550,'Año Nuevo','2026-12-31','2027-01-03',2,true,240655),
 (1958207,'Año Nuevo','2026-12-31','2027-01-03',2,true,130055),
 (1962202,'Año Nuevo','2026-12-31','2027-01-03',2,false,null),
 (7647427,'Año Nuevo','2026-12-31','2027-01-03',2,true,133253),
 (11324893,'Año Nuevo','2026-12-31','2027-01-03',2,false,null),
 (4348414,'Año Nuevo','2026-12-31','2027-01-03',2,false,null),
 -- Enero (10 al 13)
 (17734550,'Enero','2027-01-10','2027-01-13',2,true,144393),
 (1958207,'Enero','2027-01-10','2027-01-13',2,true,124725),
 (1962202,'Enero','2027-01-10','2027-01-13',2,false,null),
 (7647427,'Enero','2027-01-10','2027-01-13',2,true,127923),
 (11324893,'Enero','2027-01-10','2027-01-13',2,false,null),
 (4348414,'Enero','2027-01-10','2027-01-13',2,false,null),
 (17734550,'Enero','2027-01-10','2027-01-13',4,true,167899),
 (1958207,'Enero','2027-01-10','2027-01-13',4,false,null),
 (1962202,'Enero','2027-01-10','2027-01-13',4,false,null),
 (7647427,'Enero','2027-01-10','2027-01-13',4,true,127923),
 (11324893,'Enero','2027-01-10','2027-01-13',4,false,null),
 (4348414,'Enero','2027-01-10','2027-01-13',4,false,null),
 -- Carnaval (6 al 9 de febrero)
 (17734550,'Carnaval','2027-02-06','2027-02-09',2,true,173272),
 (1958207,'Carnaval','2027-02-06','2027-02-09',2,false,null),
 (1962202,'Carnaval','2027-02-06','2027-02-09',2,false,null),
 (7647427,'Carnaval','2027-02-06','2027-02-09',2,false,null),
 (11324893,'Carnaval','2027-02-06','2027-02-09',2,false,null),
 (4348414,'Carnaval','2027-02-06','2027-02-09',2,false,null)
on conflict (booking_id, entrada, salida, personas) do update set disponible=excluded.disponible, precio_noche=excluded.precio_noche, periodo=excluded.periodo, relevado=now();
