# Parte 3 — Función de reserva de inventario

`reserve_material()` reserva material para una orden de producción consumiendo
lotes en orden FIFO, deja constancia de cada consumo y es segura frente a
reintentos y a ejecuciones concurrentes.

```sql
SELECT * FROM reserve_material(
  p_request_id    => 101,
  p_warehouse_id  => 1,
  p_allow_partial => TRUE   -- por defecto
);

 request_id |  status   | quantity_reserved | quantity_pending | lots_used
------------+-----------+-------------------+------------------+-----------
        101 | fulfilled |           40.0000 |           0.0000 |         1
```

PL/pgSQL puro. La función no abre ni cierra transacciones: se ejecuta dentro de
la de la aplicación. Las decisiones de diseño y los supuestos están en
[`NOTAS.md`](NOTAS.md).

## Requisitos

PostgreSQL 13 o superior (desarrollado y verificado con 16.15) y `psql` en el
`PATH`. Nada más: no hay Ruby en esta parte.

## Ejecutarlo todo

```bash
./run.sh                 # crea la base prueba_parte3, carga todo y prueba
./run.sh mi_base         # o con el nombre de base que prefieras
```

`run.sh` sale con código distinto de cero si algo falla, así que sirve tal cual
para CI. Salida esperada:

```
=== Parte 3 · reserve_material ============================================
NOTICE:  OK   1 · cabe en un solo lote
...
NOTICE:  OK  14 · las tres invariantes se cumplen sobre el estado final
=== Todas las pruebas pasaron ============================================

=== Parte 3 · concurrencia ===============================================
  sesión A (solicitud 112): fulfilled 60.0000
  sesión B (solicitud 113): partial 40.0000   (bloqueada 714 ms)
NOTICE:  OK · una fulfilled y una partial; 100 repartidos de 100, nunca 120
```

Esos 714 ms son la prueba de concurrencia: la sesión B se quedó esperando el
bloqueo de A sobre el lote y, al entrar, solo encontró los 40 que quedaban.

### O paso a paso

```bash
createdb prueba_parte3
psql -v ON_ERROR_STOP=1 -d prueba_parte3 -f schema.sql
psql -v ON_ERROR_STOP=1 -d prueba_parte3 -f reserve_material.sql
psql -v ON_ERROR_STOP=1 -d prueba_parte3 -f test.sql   # recarga seeds.sql solo
./test_concurrencia.sh prueba_parte3
```

`test.sql` es reejecutable: recarga `seeds.sql` al empezar.

## Estados posibles

| Situación | `p_allow_partial` | Estado final | Consume |
| --- | --- | --- | --- |
| Se cubre toda la cantidad | cualquiera | `fulfilled` | sí |
| Alcanza para una parte | `TRUE` | `partial` | sí |
| Alcanza para una parte | `FALSE` | `backordered` | no |
| No hay nada de inventario | cualquiera | `backordered` | no |

La última fila se aparta de la letra del enunciado a propósito: una solicitud que
no consumió nada tiene que poder reintentarse. Es la decisión **D1** de
`NOTAS.md`.

Sobre una solicitud ya atendida (`fulfilled` o `partial`) la función no consume
nada y devuelve el resultado anterior. Las demás —`pending`, `backordered`,
`failed`— se reintentan.

## Errores identificables

Todos con `SQLSTATE` propio de la clase `ES`, mensaje y `HINT`. Una excepción
aborta la transacción, así que nunca quedan escrituras a medias.

| Código | Condición |
| --- | --- |
| `ESM01` | La solicitud no existe. |
| `ESM02` | El material de la solicitud no existe. |
| `ESM03` | `quantity_required` no es mayor que cero. |
| `ESM04` | Almacén desconocido o `NULL`. |

`ESM02` y `ESM03` son inalcanzables mientras el esquema conserve su clave foránea
y su `CHECK`; se quedan como defensa en profundidad (supuesto S3 de `NOTAS.md`).

## Mapa de los archivos

| Archivo | Qué hace |
| --- | --- |
| `schema.sql` | El DDL del enunciado sin tocar, más los tres índices añadidos. |
| `reserve_material.sql` | La función. |
| `seeds.sql` | Datos de prueba: un material por escenario. |
| `test.sql` | 14 casos con `ASSERT`, incluidas las tres invariantes. |
| `test_concurrencia.sh` | Dos sesiones `psql` simultáneas sobre el mismo lote. |
| `run.sh` | Crea la base, carga todo y corre las dos baterías. |

## Qué cubren las pruebas

Los ocho casos que exige el enunciado —cabe en un lote, necesita varios, agota el
inventario justo, lo excede con y sin `allow_partial`, material sin lotes, lote
con cantidad cero y segunda llamada sobre una solicitud ya atendida— más seis
extra: el FIFO desempatado por `id` cuando dos lotes comparten `received_at`, que
el inventario de otro almacén no se toca, que una solicitud `backordered` sigue
siendo reintentable, los errores identificables, que un error no deja escrituras
a medias, y las tres invariantes verificadas sobre el estado final completo.
