-- Parte 3 — Esquema
--
-- El DDL de las cuatro tablas y el tipo compuesto es literalmente el del
-- enunciado: no se toca ni una restricción. Lo único añadido son los dos
-- índices del final, justificados en NOTAS.md.

BEGIN;

DROP TABLE IF EXISTS stock_movements       CASCADE;
DROP TABLE IF EXISTS reservation_requests  CASCADE;
DROP TABLE IF EXISTS stock_lots            CASCADE;
DROP TABLE IF EXISTS materials             CASCADE;
DROP TYPE  IF EXISTS reservation_result    CASCADE;

CREATE TABLE materials (
  id   BIGSERIAL PRIMARY KEY,
  code VARCHAR(32) NOT NULL UNIQUE,
  unit VARCHAR(8)  NOT NULL
);

CREATE TABLE stock_lots (
  id           BIGSERIAL PRIMARY KEY,
  material_id  BIGINT        NOT NULL REFERENCES materials(id),
  warehouse_id BIGINT        NOT NULL,
  quantity     NUMERIC(14,4) NOT NULL CHECK (quantity >= 0),
  received_at  TIMESTAMPTZ   NOT NULL
);

CREATE TABLE reservation_requests (
  id                  BIGSERIAL PRIMARY KEY,
  production_order_id BIGINT        NOT NULL,
  material_id         BIGINT        NOT NULL REFERENCES materials(id),
  quantity_required   NUMERIC(14,4) NOT NULL CHECK (quantity_required > 0),
  quantity_reserved   NUMERIC(14,4) NOT NULL DEFAULT 0,
  status              VARCHAR(16)   NOT NULL DEFAULT 'pending',
      -- 'pending' | 'fulfilled' | 'partial' | 'backordered' | 'failed'
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE stock_movements (
  id             BIGSERIAL PRIMARY KEY,
  request_id     BIGINT        NOT NULL REFERENCES reservation_requests(id),
  stock_lot_id   BIGINT        NOT NULL REFERENCES stock_lots(id),
  quantity_moved NUMERIC(14,4) NOT NULL CHECK (quantity_moved > 0),
  moved_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TYPE reservation_result AS (
  request_id        BIGINT,
  status            VARCHAR,
  quantity_reserved NUMERIC,
  quantity_pending  NUMERIC,
  lots_used         INTEGER
);

-- ---------------------------------------------------------------------------
-- Índices añadidos
-- ---------------------------------------------------------------------------

-- El recorrido FIFO de la función. Las cuatro columnas van en el orden exacto
-- de la consulta: igualdad por (material_id, warehouse_id) y luego el orden
-- (received_at, id), que es el desempate que pide el enunciado. Así el plan es
-- un Index Scan que entrega las filas ya ordenadas: sin Sort, y sin leer más
-- lotes que los que se consumen (el bloqueo es perezoso, lote a lote).
--
-- Es un índice PARCIAL sobre quantity > 0 porque los lotes agotados no se
-- borran: son historial. Un almacén con años de operación acumula muchos lotes
-- en cero, y ninguno es candidato. El predicado los deja fuera del índice.
CREATE INDEX idx_stock_lots_fifo
  ON stock_lots (material_id, warehouse_id, received_at, id)
  WHERE quantity > 0;

-- Sin tabla `warehouses`, la validación «almacén desconocido» es una consulta
-- de existencia sobre stock_lots. Este índice la convierte en una lectura de
-- índice en vez de un recorrido secuencial de la tabla de lotes. Es el peaje
-- de suplir una tabla que el esquema no tiene (ver NOTAS.md, supuesto S2).
CREATE INDEX idx_stock_lots_warehouse
  ON stock_lots (warehouse_id);

-- Recuento de lotes usados en el retorno idempotente, y la consulta que
-- verifica la invariante 1 (quantity_reserved = SUM(quantity_moved)).
CREATE INDEX idx_stock_movements_request
  ON stock_movements (request_id);

COMMIT;
