-- ================================================================
-- AROMAS DE CAMPO — Schema completo Supabase
-- Ejecutar en: Supabase Dashboard → SQL Editor → Run
-- ================================================================

-- ================================================================
-- TABLAS
-- ================================================================

CREATE TABLE cabanas (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          TEXT UNIQUE NOT NULL,
  nombre        TEXT NOT NULL,
  descripcion   TEXT,
  capacidad_max SMALLINT NOT NULL DEFAULT 4,
  precio_base   NUMERIC(10,2) NOT NULL,
  fotos         TEXT[],
  amenidades    TEXT[],
  activa        BOOLEAN NOT NULL DEFAULT true,
  orden         SMALLINT DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE reservas (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cabana_id        UUID NOT NULL REFERENCES cabanas(id) ON DELETE RESTRICT,
  nombre           TEXT NOT NULL,
  email            TEXT NOT NULL,
  telefono         TEXT NOT NULL,
  personas         SMALLINT NOT NULL CHECK (personas BETWEEN 1 AND 4),
  fecha_checkin    DATE NOT NULL,
  fecha_checkout   DATE NOT NULL,
  noches           SMALLINT GENERATED ALWAYS AS (fecha_checkout - fecha_checkin) STORED,
  precio_total     NUMERIC(10,2) NOT NULL,
  precio_por_noche NUMERIC(10,2) NOT NULL,
  estado           TEXT NOT NULL DEFAULT 'pendiente'
                     CHECK (estado IN ('pendiente','confirmada','cancelada','completada')),
  notas_huesped    TEXT,
  notas_admin      TEXT,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  confirmada_at    TIMESTAMPTZ,
  cancelada_at     TIMESTAMPTZ,
  CONSTRAINT fechas_validas CHECK (fecha_checkout > fecha_checkin),
  CONSTRAINT max_30_noches  CHECK ((fecha_checkout - fecha_checkin) <= 30)
);

CREATE INDEX idx_reservas_cabana_fechas
  ON reservas (cabana_id, fecha_checkin, fecha_checkout)
  WHERE estado != 'cancelada';
CREATE INDEX idx_reservas_estado    ON reservas (estado);
CREATE INDEX idx_reservas_created   ON reservas (created_at DESC);

CREATE TABLE precios_temporada (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cabana_id    UUID REFERENCES cabanas(id) ON DELETE CASCADE,
  nombre       TEXT NOT NULL,
  fecha_desde  DATE NOT NULL,
  fecha_hasta  DATE NOT NULL,
  precio_noche NUMERIC(10,2) NOT NULL,
  prioridad    SMALLINT DEFAULT 0,
  activo       BOOLEAN DEFAULT true,
  created_at   TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT fechas_temporada_validas CHECK (fecha_hasta >= fecha_desde)
);

CREATE INDEX idx_precios_fechas
  ON precios_temporada (fecha_desde, fecha_hasta)
  WHERE activo = true;

CREATE TABLE bloqueos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cabana_id   UUID REFERENCES cabanas(id) ON DELETE CASCADE,
  fecha_desde DATE NOT NULL,
  fecha_hasta DATE NOT NULL,
  motivo      TEXT DEFAULT 'mantenimiento'
                CHECK (motivo IN ('mantenimiento','uso_personal','otro')),
  descripcion TEXT,
  created_at  TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT fechas_bloqueo_validas CHECK (fecha_hasta >= fecha_desde)
);

CREATE INDEX idx_bloqueos_fechas
  ON bloqueos (cabana_id, fecha_desde, fecha_hasta);

CREATE TABLE resenas (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reserva_id UUID REFERENCES reservas(id) ON DELETE SET NULL,
  cabana_id  UUID REFERENCES cabanas(id) ON DELETE SET NULL,
  nombre     TEXT NOT NULL,
  rating     SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  texto      TEXT,
  aprobada   BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE actividades_cercanas (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre        TEXT NOT NULL,
  categoria     TEXT NOT NULL
                  CHECK (categoria IN ('gastronomia','naturaleza','cultura','deporte','playa','compras')),
  descripcion   TEXT,
  distancia_km  NUMERIC(5,1),
  url_maps      TEXT,
  foto          TEXT,
  activa        BOOLEAN DEFAULT true,
  orden         SMALLINT DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- ================================================================
-- TRIGGER: updated_at automático en reservas
-- ================================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER reservas_updated_at
  BEFORE UPDATE ON reservas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ================================================================
-- FUNCIÓN: check_disponibilidad
-- ================================================================

CREATE OR REPLACE FUNCTION check_disponibilidad(
  p_cabana_id UUID,
  p_checkin   DATE,
  p_checkout  DATE
) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    NOT EXISTS (
      SELECT 1 FROM reservas r
      WHERE r.cabana_id = p_cabana_id
        AND r.estado NOT IN ('cancelada')
        AND r.fecha_checkin < p_checkout
        AND r.fecha_checkout > p_checkin
    )
    AND NOT EXISTS (
      SELECT 1 FROM bloqueos b
      WHERE (b.cabana_id = p_cabana_id OR b.cabana_id IS NULL)
        AND b.fecha_desde < p_checkout
        AND b.fecha_hasta > p_checkin
    );
$$;

-- ================================================================
-- FUNCIÓN: calcular_precio_reserva
-- ================================================================

CREATE OR REPLACE FUNCTION calcular_precio_reserva(
  p_cabana_id UUID,
  p_checkin   DATE,
  p_checkout  DATE
)
RETURNS TABLE (precio_total NUMERIC, precio_por_noche NUMERIC, detalle JSONB)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_fecha      DATE;
  v_precio_dia NUMERIC;
  v_total      NUMERIC := 0;
  v_detalle    JSONB := '[]'::jsonb;
  v_base       NUMERIC;
  v_noches     INTEGER;
BEGIN
  SELECT precio_base INTO v_base FROM cabanas WHERE id = p_cabana_id;
  v_noches := p_checkout - p_checkin;

  v_fecha := p_checkin;
  WHILE v_fecha < p_checkout LOOP
    SELECT COALESCE(
      (SELECT pt.precio_noche
       FROM precios_temporada pt
       WHERE (pt.cabana_id = p_cabana_id OR pt.cabana_id IS NULL)
         AND pt.activo = true
         AND v_fecha BETWEEN pt.fecha_desde AND pt.fecha_hasta
       ORDER BY pt.prioridad DESC, pt.cabana_id NULLS LAST
       LIMIT 1),
      v_base
    ) INTO v_precio_dia;

    v_total   := v_total + v_precio_dia;
    v_detalle := v_detalle || jsonb_build_object(
      'fecha',  to_char(v_fecha, 'YYYY-MM-DD'),
      'precio', v_precio_dia
    );
    v_fecha := v_fecha + 1;
  END LOOP;

  RETURN QUERY SELECT v_total, ROUND(v_total / v_noches, 2), v_detalle;
END;
$$;

-- ================================================================
-- VIEW: dias_ocupados_por_cabana (para el calendario público)
-- Expone estado de cada día sin datos sensibles de huéspedes
-- ================================================================

CREATE OR REPLACE VIEW dias_ocupados_por_cabana AS
SELECT
  c.id   AS cabana_id,
  c.slug,
  c.nombre,
  d.fecha::DATE AS fecha,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM bloqueos b
      WHERE (b.cabana_id = c.id OR b.cabana_id IS NULL)
        AND d.fecha::DATE >= b.fecha_desde
        AND d.fecha::DATE <  b.fecha_hasta
    ) THEN 'bloqueado'
    WHEN EXISTS (
      SELECT 1 FROM reservas r
      WHERE r.cabana_id = c.id
        AND r.estado NOT IN ('cancelada')
        AND d.fecha::DATE >= r.fecha_checkin
        AND d.fecha::DATE <  r.fecha_checkout
    ) THEN 'ocupado'
    ELSE 'libre'
  END AS estado
FROM cabanas c
CROSS JOIN generate_series(
  CURRENT_DATE,
  CURRENT_DATE + INTERVAL '365 days',
  '1 day'::interval
) AS d(fecha)
WHERE c.activa = true;

-- ================================================================
-- RLS (Row Level Security)
-- ================================================================

ALTER TABLE cabanas              ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservas             ENABLE ROW LEVEL SECURITY;
ALTER TABLE precios_temporada    ENABLE ROW LEVEL SECURITY;
ALTER TABLE bloqueos             ENABLE ROW LEVEL SECURITY;
ALTER TABLE resenas              ENABLE ROW LEVEL SECURITY;
ALTER TABLE actividades_cercanas ENABLE ROW LEVEL SECURITY;

-- CABANAS
CREATE POLICY "cabanas_select_public" ON cabanas
  FOR SELECT USING (activa = true);
CREATE POLICY "cabanas_all_admin" ON cabanas
  FOR ALL USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- RESERVAS: público puede insertar pendientes, solo admin puede leer/editar
CREATE POLICY "reservas_insert_public" ON reservas
  FOR INSERT WITH CHECK (estado = 'pendiente');
CREATE POLICY "reservas_select_admin" ON reservas
  FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "reservas_update_admin" ON reservas
  FOR UPDATE USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "reservas_delete_admin" ON reservas
  FOR DELETE USING (auth.role() = 'authenticated');

-- PRECIOS
CREATE POLICY "precios_select_public" ON precios_temporada
  FOR SELECT USING (activo = true);
CREATE POLICY "precios_all_admin" ON precios_temporada
  FOR ALL USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- BLOQUEOS
CREATE POLICY "bloqueos_select_public" ON bloqueos
  FOR SELECT USING (true);
CREATE POLICY "bloqueos_all_admin" ON bloqueos
  FOR ALL USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- RESEÑAS
CREATE POLICY "resenas_select_public" ON resenas
  FOR SELECT USING (aprobada = true);
CREATE POLICY "resenas_insert_public" ON resenas
  FOR INSERT WITH CHECK (true);
CREATE POLICY "resenas_all_admin" ON resenas
  FOR ALL USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ACTIVIDADES
CREATE POLICY "actividades_select_public" ON actividades_cercanas
  FOR SELECT USING (activa = true);
CREATE POLICY "actividades_all_admin" ON actividades_cercanas
  FOR ALL USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- Permisos para anon (funciones y vistas públicas)
GRANT SELECT ON dias_ocupados_por_cabana TO anon;
GRANT EXECUTE ON FUNCTION check_disponibilidad TO anon;
GRANT EXECUTE ON FUNCTION calcular_precio_reserva TO anon;

-- ================================================================
-- DATOS INICIALES
-- ================================================================

INSERT INTO cabanas (slug, nombre, descripcion, capacidad_max, precio_base, fotos, amenidades, orden) VALUES
(
  'el-tronco', 'El Tronco',
  'La más acogedora, perfecta para parejas o familias. Vista directa al jardín y parrilla propia.',
  4, 35000.00,
  ARRAY['fotos/cabana-1.jpg'],
  ARRAY['WiFi','Parrilla','Ropa de cama','Toallas','Aire acondicionado','TV'],
  1
),
(
  'el-sauce', 'El Sauce',
  'Rodeada de sauces añosos a metros de la pileta. Luminosa y fresca en verano.',
  4, 33000.00,
  ARRAY['fotos/cabana-2.jpg'],
  ARRAY['WiFi','Parrilla','Pileta','Ropa de cama','Ventilador de techo','TV'],
  2
),
(
  'el-ceibo', 'El Ceibo',
  'Vista panorámica al campo. La más tranquila, ideal para descansar de verdad.',
  4, 33000.00,
  ARRAY['fotos/cabana-3.jpg'],
  ARRAY['WiFi','Parrilla','Ropa de cama','Toallas','Smart TV','Jardín privado'],
  3
);

INSERT INTO actividades_cercanas (nombre, categoria, descripcion, distancia_km, orden) VALUES
('Termas de Colón',      'deporte',    'Las termas más completas de Entre Ríos. Piscinas termales al aire libre.',          2.5,  1),
('Playa del río Uruguay','playa',      'Playas de arena fina sobre el río Uruguay. Ideal para refrescarse en verano.',       4.0,  2),
('Palacio San José',     'cultura',    'Residencia histórica del General Urquiza, hoy museo nacional.',                     30.0, 3),
('Parque El Palmar',     'naturaleza', 'Reserva natural con palmeras yatay, ciervos y aves autóctonas.',                    60.0, 4),
('Centro de Colón',      'compras',    'Paseo de compras, artesanías y gastronomía a metros del río.',                      3.0,  5),
('Río Uruguay en lancha','deporte',    'Paseos en lancha, pesca deportiva y avistamiento de fauna ribereña.',                5.0,  6);
