-- Parte 3 — Batería de pruebas
--
-- Se ejecuta con:  psql -v ON_ERROR_STOP=1 -d <base> -f test.sql
-- (o, más cómodo, ./run.sh, que crea la base y carga todo antes).
--
-- Cada caso es un bloque DO con ASSERT: si una aserción falla, psql aborta con
-- el mensaje del ASSERT y un código de salida distinto de cero. No hay que
-- leer la salida para saber si pasó — basta el código de salida.
--
-- test.sql recarga seeds.sql al empezar, así que es idempotente: se puede
-- volver a ejecutar las veces que haga falta sobre la misma base.

\set ON_ERROR_STOP on
\set QUIET on
\i seeds.sql
\set QUIET off

-- Foto del inventario al arrancar, para comprobar la invariante 2 al final.
SET client_min_messages = warning;
DROP TABLE IF EXISTS lotes_iniciales;
CREATE TEMP TABLE lotes_iniciales AS SELECT id, quantity FROM stock_lots;
SET client_min_messages = notice;

\echo ''
\echo '=== Parte 3 · reserve_material ============================================'

-- ===========================================================================
-- Casos exigidos por el enunciado
-- ===========================================================================

-- 1 · Cabe en un solo lote -----------------------------------------------
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(101, 1);

  ASSERT r.status            = 'fulfilled', format('estado %s', r.status);
  ASSERT r.quantity_reserved = 40.0000,     format('reservado %s', r.quantity_reserved);
  ASSERT r.quantity_pending  = 0.0000,      format('pendiente %s', r.quantity_pending);
  ASSERT r.lots_used         = 1,           format('lotes %s', r.lots_used);

  -- El lote queda con el resto, no a cero.
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 1) = 60.0000;
  ASSERT (SELECT COUNT(*) FROM stock_movements WHERE request_id = 101) = 1;

  RAISE NOTICE 'OK   1 · cabe en un solo lote';
END $$;

-- 2 · Necesita varios lotes ----------------------------------------------
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(102, 1);   -- 75 sobre lotes de 30 + 30 + 30

  ASSERT r.status    = 'fulfilled', format('estado %s', r.status);
  ASSERT r.lots_used = 3,           format('lotes %s', r.lots_used);

  -- Los dos más antiguos se agotan y el tercero queda a medias: FIFO.
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 2) =  0.0000;
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 3) =  0.0000;
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 4) = 15.0000;

  ASSERT (SELECT array_agg(quantity_moved ORDER BY id)
          FROM stock_movements WHERE request_id = 102)
         = ARRAY[30.0000, 30.0000, 15.0000]::NUMERIC(14,4)[];

  RAISE NOTICE 'OK   2 · necesita varios lotes';
END $$;

-- 3 · Agota el inventario justo ------------------------------------------
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(103, 1);   -- 50 sobre 20 + 30

  ASSERT r.status           = 'fulfilled', format('estado %s', r.status);
  ASSERT r.quantity_pending = 0.0000;
  ASSERT r.lots_used        = 2;

  ASSERT (SELECT SUM(quantity) FROM stock_lots WHERE material_id = 3) = 0.0000;

  RAISE NOTICE 'OK   3 · agota el inventario justo';
END $$;

-- 4 · Excede el inventario CON allow_partial ------------------------------
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(104, 1, TRUE);   -- pide 40, hay 15

  ASSERT r.status            = 'partial', format('estado %s', r.status);
  ASSERT r.quantity_reserved = 15.0000,   format('reservado %s', r.quantity_reserved);
  ASSERT r.quantity_pending  = 25.0000,   format('pendiente %s', r.quantity_pending);
  ASSERT r.lots_used         = 2;

  ASSERT (SELECT SUM(quantity) FROM stock_lots WHERE material_id = 4) = 0.0000;

  RAISE NOTICE 'OK   4 · excede el inventario con allow_partial';
END $$;

-- 5 · Excede el inventario SIN allow_partial ------------------------------
DO $$
DECLARE r reservation_result;
BEGIN
  r := reserve_material(105, 1, FALSE);   -- pide 40, hay 15

  ASSERT r.status            = 'backordered', format('estado %s', r.status);
  ASSERT r.quantity_reserved = 0.0000;
  ASSERT r.quantity_pending  = 40.0000;
  ASSERT r.lots_used         = 0;

  -- Lo importante: no tocó NADA. Los lotes siguen intactos.
  ASSERT (SELECT quantity FROM stock_lots WHERE id =  9) = 10.0000;
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 10) =  5.0000;
  ASSERT (SELECT COUNT(*) FROM stock_movements WHERE request_id = 105) = 0;

  RAISE NOTICE 'OK   5 · excede el inventario sin allow_partial';
END $$;

-- 6 · Material sin lotes ---------------------------------------------------
DO $$
DECLARE r_si reservation_result;
        r_no reservation_result;
BEGIN
  r_si := reserve_material(106, 1, TRUE);
  r_no := reserve_material(107, 1, FALSE);

  -- Decisión D1 de NOTAS.md: con allow_partial = TRUE y cero reservado, la
  -- solicitud queda 'backordered', no 'partial'. No consumió nada, así que
  -- tiene que seguir siendo reintentable (ver caso 11).
  ASSERT r_si.status = 'backordered', format('con parcial: %s', r_si.status);
  ASSERT r_no.status = 'backordered', format('sin parcial: %s', r_no.status);

  ASSERT r_si.quantity_reserved = 0.0000 AND r_si.lots_used = 0;
  ASSERT r_no.quantity_reserved = 0.0000 AND r_no.lots_used = 0;

  ASSERT (SELECT COUNT(*) FROM stock_movements
          WHERE request_id IN (106, 107)) = 0;

  RAISE NOTICE 'OK   6 · material sin lotes, con y sin allow_partial';
END $$;

-- 7 · Lote con cantidad cero ----------------------------------------------
DO $$
DECLARE r reservation_result;
BEGIN
  -- El material 7 tiene un lote de 25 entre dos lotes agotados; el más
  -- antiguo de los tres está a cero, así que el FIFO tiene que saltárselo.
  r := reserve_material(108, 1);

  ASSERT r.status    = 'fulfilled', format('estado %s', r.status);
  ASSERT r.lots_used = 1,           format('lotes %s', r.lots_used);

  ASSERT (SELECT quantity FROM stock_lots WHERE id = 12) = 15.0000;

  -- Invariante 3: ni un movimiento sobre los lotes vacíos.
  ASSERT (SELECT COUNT(*) FROM stock_movements
          WHERE stock_lot_id IN (11, 13)) = 0;

  RAISE NOTICE 'OK   7 · lote con cantidad cero: se salta, sin movimiento';
END $$;

-- 8 · Segunda llamada sobre una solicitud ya atendida ---------------------
DO $$
DECLARE r1 reservation_result;
        r2 reservation_result;
BEGIN
  -- 8a · sobre una 'fulfilled' (la solicitud 101 del caso 1)
  r1 := reserve_material(101, 1);

  ASSERT r1.status            = 'fulfilled';
  ASSERT r1.quantity_reserved = 40.0000, format('reservado %s', r1.quantity_reserved);
  ASSERT r1.lots_used         = 1;

  -- Ni un movimiento nuevo, ni un gramo menos en el lote.
  ASSERT (SELECT COUNT(*) FROM stock_movements WHERE request_id = 101) = 1;
  ASSERT (SELECT quantity FROM stock_lots WHERE id = 1) = 60.0000;

  -- 8b · sobre una 'partial': 50 pedidos contra un lote de 30
  r1 := reserve_material(109, 1, TRUE);
  ASSERT r1.status            = 'partial', format('estado %s', r1.status);
  ASSERT r1.quantity_reserved = 30.0000;

  r2 := reserve_material(109, 1, TRUE);
  ASSERT r2.status            = r1.status;
  ASSERT r2.quantity_reserved = r1.quantity_reserved;
  ASSERT r2.quantity_pending  = r1.quantity_pending;
  ASSERT r2.lots_used         = r1.lots_used;

  ASSERT (SELECT COUNT(*) FROM stock_movements WHERE request_id = 109) = 1;

  RAISE NOTICE 'OK   8 · segunda llamada sobre fulfilled y sobre partial';
END $$;

-- ===========================================================================
-- Casos extra
-- ===========================================================================

-- 9 · FIFO con empate en received_at, desempatado por id -------------------
DO $$
DECLARE r reservation_result;
BEGIN
  -- Lote 16 es el más antiguo; 17 y 18 comparten received_at al segundo.
  r := reserve_material(110, 1);   -- pide 25 sobre 10 + 10 + 10

  ASSERT r.status = 'fulfilled';

  -- El orden de consumo tiene que ser 16, 17, 18 — nunca 16, 18, 17.
  ASSERT (SELECT array_agg(stock_lot_id ORDER BY id)
          FROM stock_movements WHERE request_id = 110)
         = ARRAY[16, 17, 18]::BIGINT[];

  ASSERT (SELECT quantity FROM stock_lots WHERE id = 18) = 5.0000;

  RAISE NOTICE 'OK   9 · FIFO con empate en received_at, desempatado por id';
END $$;

-- 10 · Los lotes de otro almacén no se tocan ------------------------------
DO $$
DECLARE r reservation_result;
BEGIN
  -- El material 10 tiene 10 en el almacén 1 y 500 en el 2. Se piden 50 en el
  -- almacén 1: tiene que quedarse en 10, sin asomarse al almacén 2.
  r := reserve_material(111, 1, TRUE);

  ASSERT r.status            = 'partial', format('estado %s', r.status);
  ASSERT r.quantity_reserved = 10.0000,   format('reservado %s', r.quantity_reserved);

  ASSERT (SELECT quantity FROM stock_lots WHERE id = 20) = 500.0000;
  ASSERT (SELECT COUNT(*) FROM stock_movements WHERE stock_lot_id = 20) = 0;

  RAISE NOTICE 'OK  10 · el inventario de otro almacén no se toca';
END $$;

-- 11 · Una solicitud 'backordered' se puede reintentar ---------------------
DO $$
DECLARE r reservation_result;
BEGIN
  -- Este es el caso que justifica la decisión D1. La solicitud 106 quedó en
  -- 'backordered' en el caso 6 sin consumir nada. Entra material y el
  -- reintento la resuelve. Si se hubiera quedado en 'partial' con cero —la
  -- lectura literal del enunciado— la regla de idempotencia la habría dejado
  -- congelada para siempre.
  WITH nuevo AS (
    INSERT INTO stock_lots (material_id, warehouse_id, quantity, received_at)
    VALUES (6, 1, 10.0000, '2026-03-01 08:00:00+00')
    RETURNING id, quantity
  )
  INSERT INTO lotes_iniciales SELECT id, quantity FROM nuevo;

  r := reserve_material(106, 1, TRUE);

  ASSERT r.status            = 'fulfilled', format('estado %s', r.status);
  ASSERT r.quantity_reserved = 10.0000;
  ASSERT r.lots_used         = 1;

  RAISE NOTICE 'OK  11 · backordered sigue siendo reintentable';
END $$;

-- 12 · Errores identificables ---------------------------------------------
DO $$
BEGIN
  PERFORM reserve_material(999999, 1);
  RAISE EXCEPTION 'se esperaba ESM01 y no se levantó ninguna excepción';
EXCEPTION WHEN SQLSTATE 'ESM01' THEN
  RAISE NOTICE 'OK  12a · ESM01 solicitud inexistente';
END $$;

DO $$
BEGIN
  PERFORM reserve_material(114, 99);   -- almacén sin un solo lote
  RAISE EXCEPTION 'se esperaba ESM04 y no se levantó ninguna excepción';
EXCEPTION WHEN SQLSTATE 'ESM04' THEN
  RAISE NOTICE 'OK  12b · ESM04 almacén desconocido';
END $$;

DO $$
BEGIN
  PERFORM reserve_material(114, NULL);
  RAISE EXCEPTION 'se esperaba ESM04 y no se levantó ninguna excepción';
EXCEPTION WHEN SQLSTATE 'ESM04' THEN
  RAISE NOTICE 'OK  12c · ESM04 almacén NULL';
END $$;

-- ESM02 (material inexistente) y ESM03 (cantidad <= 0) no se pueden
-- provocar: la clave foránea reservation_requests.material_id -> materials y
-- el CHECK (quantity_required > 0) los hacen imposibles, y el enunciado
-- prohíbe desactivar restricciones del esquema. Las dos ramas se quedan en la
-- función como defensa en profundidad. Está argumentado en NOTAS.md.

-- 13 · Un error no deja escrituras a medias -------------------------------
DO $$
DECLARE v_antes NUMERIC;
        v_movs  INTEGER;
BEGIN
  SELECT SUM(quantity), (SELECT COUNT(*) FROM stock_movements)
    INTO v_antes, v_movs FROM stock_lots;

  BEGIN
    PERFORM reserve_material(114, 99);
  EXCEPTION WHEN SQLSTATE 'ESM04' THEN
    NULL;   -- la excepción deshace el bloque entero
  END;

  ASSERT (SELECT SUM(quantity) FROM stock_lots)   = v_antes;
  ASSERT (SELECT COUNT(*) FROM stock_movements)   = v_movs;
  ASSERT (SELECT status FROM reservation_requests WHERE id = 114) = 'pending';

  RAISE NOTICE 'OK  13 · un error no deja escrituras a medias';
END $$;

-- ===========================================================================
-- Invariantes del enunciado, sobre el estado final completo
-- ===========================================================================
DO $$
DECLARE v_fallos INTEGER;
BEGIN
  -- 1 · Para cada solicitud: quantity_reserved = SUM(movimientos).
  SELECT COUNT(*) INTO v_fallos
  FROM reservation_requests r
  WHERE r.quantity_reserved <> (
    SELECT COALESCE(SUM(m.quantity_moved), 0)
    FROM stock_movements m WHERE m.request_id = r.id
  );
  ASSERT v_fallos = 0,
         format('invariante 1 rota en %s solicitud(es)', v_fallos);

  -- 2 · Para cada lote: cantidad actual + total movido = cantidad inicial.
  SELECT COUNT(*) INTO v_fallos
  FROM lotes_iniciales i
  JOIN stock_lots l ON l.id = i.id
  WHERE l.quantity + (
    SELECT COALESCE(SUM(m.quantity_moved), 0)
    FROM stock_movements m WHERE m.stock_lot_id = l.id
  ) <> i.quantity;
  ASSERT v_fallos = 0,
         format('invariante 2 rota en %s lote(s)', v_fallos);

  -- 3 · Ningún movimiento con cantidad cero.
  SELECT COUNT(*) INTO v_fallos
  FROM stock_movements WHERE quantity_moved = 0;
  ASSERT v_fallos = 0,
         format('invariante 3 rota en %s movimiento(s)', v_fallos);

  -- Y el suelo del esquema: ningún lote en negativo.
  SELECT COUNT(*) INTO v_fallos FROM stock_lots WHERE quantity < 0;
  ASSERT v_fallos = 0, format('%s lote(s) en negativo', v_fallos);

  RAISE NOTICE 'OK  14 · las tres invariantes se cumplen sobre el estado final';
END $$;

\echo '=== Todas las pruebas pasaron ============================================'
\echo ''
