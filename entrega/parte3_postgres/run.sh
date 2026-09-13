#!/usr/bin/env bash
#
# Parte 3 — Crea la base, carga el esquema y la función, y corre las pruebas.
#
# Uso:  ./run.sh [nombre_de_la_base]     (por defecto: prueba_parte3)
#
# Sale con código distinto de cero si algo falla: sirve tal cual para CI.

set -euo pipefail

DB="${1:-prueba_parte3}"
cd "$(dirname "$0")"

echo "» Recreando la base ${DB}"
dropdb --if-exists "$DB"
createdb "$DB"

# Los NOTICE de los DROP ... IF EXISTS no aportan nada al cargar; los NOTICE de
# las pruebas sí, así que esto solo silencia la carga.
echo "» Cargando schema.sql y reserve_material.sql"
PGOPTIONS='-c client_min_messages=warning' \
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f schema.sql
PGOPTIONS='-c client_min_messages=warning' \
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f reserve_material.sql

# test.sql recarga seeds.sql por su cuenta. Toda su salida útil sale por \echo
# y por RAISE NOTICE; -o /dev/null se lleva solo las etiquetas de comando.
psql -q -v ON_ERROR_STOP=1 -o /dev/null -d "$DB" -f test.sql

./test_concurrencia.sh "$DB"
