-- Parte 3 — reserve_material()
--
-- Reserva material para una orden de producción consumiendo lotes en orden
-- FIFO (received_at, desempatando por id). La función es el contrato completo:
-- la aplicación solo la llama y lee el resultado.
--
-- No abre ni cierra transacciones: se ejecuta dentro de la transacción de la
-- aplicación. Tampoco tiene bloques EXCEPTION, y eso es deliberado — un bloque
-- EXCEPTION en PL/pgSQL crea una subtransacción, que atraparía el fallo y
-- dejaría a la aplicación creyendo que todo fue bien. Aquí cualquier excepción
-- aborta la transacción entera: no hay escrituras a medias sin necesidad de
-- deshacer nada a mano.

CREATE OR REPLACE FUNCTION reserve_material(
  p_request_id    BIGINT,
  p_warehouse_id  BIGINT,
  p_allow_partial BOOLEAN DEFAULT TRUE
) RETURNS reservation_result
LANGUAGE plpgsql
AS $$
DECLARE
  v_request   reservation_requests%ROWTYPE;
  v_lot       RECORD;
  v_pending   NUMERIC(14,4);   -- lo que falta por reservar
  v_taken     NUMERIC(14,4);   -- lo que se toma del lote en curso
  v_available NUMERIC(14,4);   -- solo se calcula si NO se admite parcial
  v_reserved  NUMERIC(14,4) := 0;
  v_lots_used INTEGER;
  v_status    VARCHAR(16);
BEGIN
  --------------------------------------------------------------------------
  -- 1 · Bloquear la solicitud, antes de mirar el inventario
  --------------------------------------------------------------------------
  -- Este es el bloqueo que sostiene la idempotencia. Dos reintentos de la
  -- misma solicitud se serializan aquí: el segundo espera en esta línea y,
  -- cuando entra, ya lee el estado que dejó el primero.
  --
  -- El orden importa: solicitud primero, lotes después. Siempre en esa
  -- dirección, nunca al revés, y los lotes siempre en el mismo orden FIFO.
  -- Una jerarquía de bloqueo fija es lo que impide los interbloqueos.
  SELECT * INTO v_request
  FROM reservation_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reserve_material: la solicitud % no existe', p_request_id
      USING ERRCODE = 'ESM01',
            HINT    = 'Comprueba el id contra reservation_requests.';
  END IF;

  --------------------------------------------------------------------------
  -- 2 · Validaciones, antes de escribir nada
  --------------------------------------------------------------------------
  -- ESM02 y ESM03 son defensa en profundidad: con el esquema tal cual está,
  -- la clave foránea y el CHECK ya los hacen inalcanzables. Se quedan porque
  -- la función es el contrato y no puede depender de que nadie afloje una
  -- restricción en una migración futura. Ver NOTAS.md.
  IF NOT EXISTS (SELECT 1 FROM materials WHERE id = v_request.material_id) THEN
    RAISE EXCEPTION 'reserve_material: el material % no existe',
                    v_request.material_id
      USING ERRCODE = 'ESM02',
            HINT    = 'La solicitud apunta a un material que no está en materials.';
  END IF;

  IF v_request.quantity_required IS NULL OR v_request.quantity_required <= 0 THEN
    RAISE EXCEPTION 'reserve_material: cantidad requerida inválida (%) en la solicitud %',
                    v_request.quantity_required, p_request_id
      USING ERRCODE = 'ESM03',
            HINT    = 'quantity_required debe ser estrictamente mayor que cero.';
  END IF;

  -- No hay tabla warehouses en el esquema. «Almacén desconocido» se define
  -- como un warehouse_id del que no existe ni un solo lote, de ningún
  -- material. Es distinto de «este material no tiene lotes en este almacén»,
  -- que no es un error sino falta de inventario. Supuesto S2 de NOTAS.md.
  IF p_warehouse_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM stock_lots WHERE warehouse_id = p_warehouse_id) THEN
    RAISE EXCEPTION 'reserve_material: almacén desconocido (%)', p_warehouse_id
      USING ERRCODE = 'ESM04',
            HINT    = 'No existe ningún lote registrado en ese almacén.';
  END IF;

  --------------------------------------------------------------------------
  -- 3 · Idempotencia
  --------------------------------------------------------------------------
  -- Terminales: 'fulfilled' y 'partial'. Ambas consumieron inventario, así
  -- que repetirlas sería reservar dos veces. Se devuelve el resultado
  -- anterior sin tocar nada.
  --
  -- Reintentables: 'pending', 'backordered' y 'failed'. Ninguna consumió
  -- nada, y son justo las que tiene sentido reintentar cuando entra material.
  IF v_request.status IN ('fulfilled', 'partial') THEN
    SELECT COUNT(DISTINCT stock_lot_id) INTO v_lots_used
    FROM stock_movements
    WHERE request_id = p_request_id;

    RETURN (v_request.id,
            v_request.status,
            v_request.quantity_reserved,
            v_request.quantity_required - v_request.quantity_reserved,
            v_lots_used)::reservation_result;
  END IF;

  --------------------------------------------------------------------------
  -- 4 · Consumo FIFO
  --------------------------------------------------------------------------
  -- Se parte de lo ya reservado, no de cero. Con los estados de arriba
  -- siempre vale 0, pero así la invariante 1 (quantity_reserved = suma de los
  -- movimientos) se mantiene sola aunque la solicitud llegue a medias.
  v_pending := v_request.quantity_required - v_request.quantity_reserved;

  -- Sin parcial hay que saber el total ANTES de escribir: o alcanza para todo
  -- o no se toca nada. Ese SUM bloquea todos los lotes candidatos, que es
  -- inherente a la modalidad — no se puede prometer «todo o nada» sobre un
  -- inventario que otro puede vaciar mientras decides.
  --
  -- Con parcial NO se hace este recuento, precisamente para no tomar ese
  -- bloqueo: el bucle de abajo va bloqueando lote a lote y se detiene en
  -- cuanto cubre la cantidad. Un pedido que se resuelve con el lote más
  -- antiguo no bloquea ningún otro.
  IF NOT p_allow_partial THEN
    SELECT COALESCE(SUM(quantity), 0) INTO v_available
    FROM (
      SELECT quantity
      FROM stock_lots
      WHERE material_id  = v_request.material_id
        AND warehouse_id = p_warehouse_id
        AND quantity     > 0
      ORDER BY received_at, id
      FOR UPDATE
    ) AS candidatos;
  END IF;

  IF v_pending > 0 AND (p_allow_partial OR v_available >= v_pending) THEN
    FOR v_lot IN
      SELECT id, quantity
      FROM stock_lots
      WHERE material_id  = v_request.material_id
        AND warehouse_id = p_warehouse_id
        AND quantity     > 0        -- los lotes agotados no son candidatos
      ORDER BY received_at, id      -- FIFO, con el desempate del enunciado
      FOR UPDATE                    -- bloqueo perezoso: solo lo que se recorre
    LOOP
      -- El bucle solo llega aquí con v_pending > 0 y v_lot.quantity > 0, así
      -- que v_taken > 0 siempre: nunca se inserta un movimiento en cero
      -- (invariante 3). Y v_taken <= v_lot.quantity, así que el CHECK
      -- (quantity >= 0) del lote no puede saltar (invariante 2).
      v_taken := LEAST(v_pending, v_lot.quantity);

      UPDATE stock_lots
         SET quantity = quantity - v_taken
       WHERE id = v_lot.id;

      INSERT INTO stock_movements (request_id, stock_lot_id, quantity_moved)
      VALUES (p_request_id, v_lot.id, v_taken);

      v_pending  := v_pending  - v_taken;
      v_reserved := v_reserved + v_taken;

      -- La salida va al final, no al principio: el cursor bloquea la fila al
      -- traerla, y salir arriba ya habría bloqueado un lote de más.
      EXIT WHEN v_pending <= 0;
    END LOOP;
  END IF;

  --------------------------------------------------------------------------
  -- 5 · Cierre de estado
  --------------------------------------------------------------------------
  v_reserved := v_request.quantity_reserved + v_reserved;

  -- 'partial' significa «reservó algo pero no todo». Si no reservó nada, la
  -- solicitud queda 'backordered' aunque p_allow_partial sea TRUE: no ha
  -- consumido inventario, así que tiene que poder reintentarse. Es una
  -- separación deliberada de la letra del enunciado, argumentada en NOTAS.md
  -- (decisión D1).
  IF v_reserved >= v_request.quantity_required THEN
    v_status := 'fulfilled';
  ELSIF v_reserved > 0 THEN
    v_status := 'partial';
  ELSE
    v_status := 'backordered';
  END IF;

  UPDATE reservation_requests
     SET quantity_reserved = v_reserved,
         status            = v_status,
         updated_at        = now()
   WHERE id = p_request_id;

  -- lots_used se recuenta desde stock_movements, no se acumula en una
  -- variable: así el número que se devuelve sale de la misma fuente que
  -- verifica la invariante 1.
  SELECT COUNT(DISTINCT stock_lot_id) INTO v_lots_used
  FROM stock_movements
  WHERE request_id = p_request_id;

  RETURN (p_request_id,
          v_status,
          v_reserved,
          v_request.quantity_required - v_reserved,
          v_lots_used)::reservation_result;
END;
$$;

COMMENT ON FUNCTION reserve_material(BIGINT, BIGINT, BOOLEAN) IS
  'Reserva material para una solicitud consumiendo lotes en orden FIFO. '
  'Idempotente sobre solicitudes ya atendidas (fulfilled/partial). '
  'Errores: ESM01 solicitud inexistente, ESM02 material inexistente, '
  'ESM03 cantidad requerida inválida, ESM04 almacén desconocido.';
