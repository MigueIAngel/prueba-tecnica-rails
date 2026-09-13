#!/usr/bin/env bash
#
# Parte 3 — Prueba de concurrencia
#
# Dos sesiones psql simultáneas reservan del MISMO lote. El material 11 tiene
# un único lote de 100 y las solicitudes 112 y 113 piden 60 cada una: sumadas
# piden 120, así que el inventario no da para las dos. Si el bloqueo funciona,
# una queda 'fulfilled' con 60 y la otra 'partial' con 40, y la suma reservada
# es exactamente 100 — nunca 120.
#
# La sesión A se queda 1 s dentro de la transacción después de reservar, para
# que el solape sea real y no cuestión de suerte: B tiene que esperar a que A
# libere el bloqueo del lote. El tiempo que tarda B es la prueba de que esperó.
#
# Uso:  ./test_concurrencia.sh [nombre_de_la_base]

set -euo pipefail

DB="${1:-prueba_parte3}"
cd "$(dirname "$0")"

echo ''
echo '=== Parte 3 · concurrencia ==============================================='

# Estado de partida limpio para el material 11, sin tocar el resto.
psql -q -v ON_ERROR_STOP=1 -d "$DB" <<'SQL'
BEGIN;
DELETE FROM stock_movements WHERE request_id IN (112, 113);
UPDATE stock_lots SET quantity = 100.0000 WHERE id = 21;
UPDATE reservation_requests
   SET quantity_reserved = 0, status = 'pending'
 WHERE id IN (112, 113);
COMMIT;
SQL

salida_a=$(mktemp) && salida_b=$(mktemp)
trap 'rm -f "$salida_a" "$salida_b"' EXIT

# Sesión A: reserva y retiene el bloqueo un segundo antes de confirmar.
(
  psql -q -At -v ON_ERROR_STOP=1 -d "$DB" <<'SQL' > "$salida_a"
BEGIN;
SELECT status || ' ' || quantity_reserved FROM reserve_material(112, 1);
SELECT pg_sleep(1);
COMMIT;
SQL
) &
pid_a=$!

# Sesión B: entra 300 ms después, con A todavía dentro de su transacción.
(
  sleep 0.3
  inicio=$(date +%s%N)
  psql -q -At -v ON_ERROR_STOP=1 -d "$DB" <<'SQL' > "$salida_b"
BEGIN;
SELECT status || ' ' || quantity_reserved FROM reserve_material(113, 1);
COMMIT;
SQL
  fin=$(date +%s%N)
  echo "espera_ms $(( (fin - inicio) / 1000000 ))" >> "$salida_b"
) &
pid_b=$!

wait "$pid_a" "$pid_b"

a=$(head -1 "$salida_a")
b=$(head -1 "$salida_b")
espera=$(grep espera_ms "$salida_b" | awk '{print $2}')

echo "  sesión A (solicitud 112): $a"
echo "  sesión B (solicitud 113): $b   (bloqueada ${espera} ms)"

# El veredicto no lo da la salida, lo dan las aserciones.
psql -q -v ON_ERROR_STOP=1 -d "$DB" <<'SQL'
DO $$
DECLARE v_reservado NUMERIC;
        v_lote      NUMERIC;
        v_estados   TEXT;
BEGIN
  SELECT SUM(quantity_reserved) INTO v_reservado
  FROM reservation_requests WHERE id IN (112, 113);

  SELECT quantity INTO v_lote FROM stock_lots WHERE id = 21;

  SELECT string_agg(status, '+' ORDER BY status) INTO v_estados
  FROM reservation_requests WHERE id IN (112, 113);

  -- Lo esencial: el mismo inventario no se reparte dos veces.
  ASSERT v_reservado = 100.0000,
         format('se repartieron %s de un lote de 100', v_reservado);
  ASSERT v_lote = 0.0000,
         format('el lote quedó en %s', v_lote);
  ASSERT v_estados = 'fulfilled+partial',
         format('estados inesperados: %s', v_estados);

  -- Invariante 1 sobre las dos solicitudes.
  ASSERT (SELECT COUNT(*) FROM reservation_requests r
          WHERE r.id IN (112, 113)
            AND r.quantity_reserved <> (
              SELECT COALESCE(SUM(m.quantity_moved), 0)
              FROM stock_movements m WHERE m.request_id = r.id)) = 0,
         'invariante 1 rota tras la ejecución concurrente';

  RAISE NOTICE 'OK · una fulfilled y una partial; 100 repartidos de 100, nunca 120';
END $$;
SQL

echo '=== Concurrencia correcta ================================================'
echo ''
