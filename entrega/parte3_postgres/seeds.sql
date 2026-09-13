-- Parte 3 — Datos de prueba
--
-- Un material por escenario. Es la forma barata de que los casos de test.sql
-- sean independientes: cada uno consume lotes que nadie más toca, así que se
-- pueden ejecutar en cualquier orden y ninguno depende de lo que hizo el
-- anterior. La alternativa —recargar el esquema entre casos— es más lenta y
-- esconde los errores de aislamiento en vez de evitarlos.
--
-- Almacenes: 1 principal, 2 secundario. El 99 no aparece en ningún lote y por
-- eso es «desconocido» para la función (ver NOTAS.md, supuesto S2).

BEGIN;

TRUNCATE stock_movements, reservation_requests, stock_lots, materials
  RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------------
-- Materiales
-- ---------------------------------------------------------------------------
INSERT INTO materials (id, code, unit) VALUES
  ( 1, 'ALU-CABE',     'kg'),   -- cabe en un solo lote
  ( 2, 'ALU-VARIOS',   'kg'),   -- necesita varios lotes
  ( 3, 'ALU-JUSTO',    'kg'),   -- agota el inventario exactamente
  ( 4, 'ALU-EXCEDE-P', 'kg'),   -- excede el inventario, con allow_partial
  ( 5, 'ALU-EXCEDE-N', 'kg'),   -- excede el inventario, sin allow_partial
  ( 6, 'ALU-SINLOTES', 'kg'),   -- material sin ningún lote
  ( 7, 'ALU-CERO',     'kg'),   -- lotes con cantidad cero intercalados
  ( 8, 'ALU-IDEM',     'kg'),   -- idempotencia sobre una solicitud parcial
  ( 9, 'ALU-FIFO',     'kg'),   -- empate en received_at, desempata id
  (10, 'ALU-OTROALM',  'kg'),   -- lotes en otro almacén que no se deben tocar
  (11, 'ALU-CONC',     'kg'),   -- prueba de concurrencia
  (12, 'ALU-ERROR',    'kg');   -- errores identificables

-- ---------------------------------------------------------------------------
-- Lotes
-- ---------------------------------------------------------------------------
INSERT INTO stock_lots (id, material_id, warehouse_id, quantity, received_at) VALUES
  -- M1 · un lote de sobra
  ( 1,  1, 1, 100.0000, '2026-01-10 08:00:00+00'),

  -- M2 · tres lotes pequeños: 30 + 30 + 15 para cubrir 75
  ( 2,  2, 1,  30.0000, '2026-01-05 08:00:00+00'),
  ( 3,  2, 1,  30.0000, '2026-01-06 08:00:00+00'),
  ( 4,  2, 1,  30.0000, '2026-01-07 08:00:00+00'),

  -- M3 · 20 + 30 = 50, justo lo que se pide
  ( 5,  3, 1,  20.0000, '2026-01-05 08:00:00+00'),
  ( 6,  3, 1,  30.0000, '2026-01-06 08:00:00+00'),

  -- M4 · 15 en total frente a 40 pedidos
  ( 7,  4, 1,  10.0000, '2026-01-05 08:00:00+00'),
  ( 8,  4, 1,   5.0000, '2026-01-06 08:00:00+00'),

  -- M5 · mismo inventario que M4, pero se pedirá sin admitir parcial
  ( 9,  5, 1,  10.0000, '2026-01-05 08:00:00+00'),
  (10,  5, 1,   5.0000, '2026-01-06 08:00:00+00'),

  -- M6 · sin lotes. No aparece aquí a propósito.

  -- M7 · dos lotes agotados rodeando al único con existencias
  (11,  7, 1,   0.0000, '2026-01-01 08:00:00+00'),
  (12,  7, 1,  25.0000, '2026-01-02 08:00:00+00'),
  (13,  7, 1,   0.0000, '2026-01-03 08:00:00+00'),

  -- M8 · 30 frente a 50 pedidos: quedará en partial
  (14,  8, 1,  30.0000, '2026-01-05 08:00:00+00'),

  -- M9 · el lote 16 es el más antiguo; 17 y 18 empatan en received_at y
  --      tienen que consumirse por id ascendente (17 antes que 18).
  (16,  9, 1,  10.0000, '2026-01-04 08:00:00+00'),
  (17,  9, 1,  10.0000, '2026-01-05 08:00:00+00'),
  (18,  9, 1,  10.0000, '2026-01-05 08:00:00+00'),

  -- M10 · poco en el almacén 1 y mucho en el 2; el 2 no se puede tocar
  (19, 10, 1,  10.0000, '2026-01-05 08:00:00+00'),
  (20, 10, 2, 500.0000, '2026-01-01 08:00:00+00'),

  -- M11 · un único lote de 100 para dos solicitudes de 60 en paralelo
  (21, 11, 1, 100.0000, '2026-01-05 08:00:00+00'),

  -- M12 · existencias irrelevantes; solo se usa para provocar errores
  (22, 12, 1,  10.0000, '2026-01-05 08:00:00+00');

-- ---------------------------------------------------------------------------
-- Solicitudes de reserva
-- ---------------------------------------------------------------------------
INSERT INTO reservation_requests
  (id, production_order_id, material_id, quantity_required) VALUES
  (101, 9001,  1, 40.0000),   -- cabe en un lote (y se llamará dos veces)
  (102, 9002,  2, 75.0000),   -- necesita varios lotes
  (103, 9003,  3, 50.0000),   -- agota el inventario justo
  (104, 9004,  4, 40.0000),   -- excede, con allow_partial
  (105, 9005,  5, 40.0000),   -- excede, sin allow_partial
  (106, 9006,  6, 10.0000),   -- material sin lotes, con allow_partial
  (107, 9007,  6, 10.0000),   -- material sin lotes, sin allow_partial
  (108, 9008,  7, 10.0000),   -- lotes en cero intercalados
  (109, 9009,  8, 50.0000),   -- parcial, para reintentar encima
  (110, 9010,  9, 25.0000),   -- FIFO con empate en received_at
  (111, 9011, 10, 50.0000),   -- no debe tocar el almacén 2
  (112, 9012, 11, 60.0000),   -- concurrencia, sesión A
  (113, 9013, 11, 60.0000),   -- concurrencia, sesión B
  (114, 9014, 12, 10.0000);   -- errores identificables

-- Las secuencias quedan por encima de los ids fijados a mano, para que
-- test.sql pueda insertar lotes y solicitudes nuevos sin colisionar.
DO $$
BEGIN
  PERFORM setval('materials_id_seq',            (SELECT MAX(id) FROM materials));
  PERFORM setval('stock_lots_id_seq',           (SELECT MAX(id) FROM stock_lots));
  PERFORM setval('reservation_requests_id_seq', (SELECT MAX(id) FROM reservation_requests));
END $$;

COMMIT;
