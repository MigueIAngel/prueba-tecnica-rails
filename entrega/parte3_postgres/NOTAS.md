# Parte 3 — Notas

## Enfoque

La función hace cinco cosas en orden fijo: bloquea la solicitud, valida, corta
por idempotencia, consume FIFO y cierra el estado. El orden **es** el diseño —
bloquear la solicitud antes de mirar el inventario es lo que convierte la
idempotencia en una propiedad y no en una carrera afortunada.

No hay bloques `EXCEPTION`: en PL/pgSQL abren una subtransacción, y una
subtransacción atrapa el fallo y deja a la aplicación creyendo que todo fue
bien. Sin ellos, cualquier excepción aborta la transacción entera y no quedan
escrituras a medias.

## 1 · Qué estrategia de bloqueo elegí

**`FOR UPDATE` sobre la fila de la solicitud, y después los lotes en el mismo
orden FIFO en que se consumen.** Una jerarquía fija es lo que evita los
interbloqueos: dos ejecuciones que se cruzan piden las mismas filas en el mismo
orden, así que una espera a la otra, nunca en círculo. Los lotes se bloquean
**perezosamente**, uno a uno según los recorre el cursor: un pedido que se
resuelve con el lote más antiguo no bloquea ninguno de los siguientes.

Con `p_allow_partial = FALSE` sí se bloquean todos los candidatos de golpe, con
un `SUM(...) FOR UPDATE` previo. Es inherente a la modalidad: no se puede
prometer «todo o nada» sobre un inventario que otro puede vaciar mientras
decides.

**Descarté `SKIP LOCKED`**, que es la respuesta refleja para inventario. Escala
mejor porque nadie espera, pero se salta los lotes bloqueados — y saltarse un
lote **es** romper el FIFO, que aquí no es una preferencia sino el requisito.
**Descarté `SERIALIZABLE`:** daría la misma garantía sin bloqueos explícitos, a
cambio de `serialization_failure` bajo contención y de que quien reintente sea
la aplicación; el enunciado dice que la función es el contrato. Y descarté los
bloqueos de aviso por material: más baratos, pero viven fuera de los datos y
quien lee el esquema no ve que existen.

## 2 · Cómo se garantiza la idempotencia

El `SELECT ... FOR UPDATE` de la solicitud es lo **primero** que ocurre, antes de
leer un solo lote. Después, `fulfilled` y `partial` se tratan como terminales
—ambos consumieron inventario— y se devuelve el resultado anterior, recomputado
desde `stock_movements`, sin tocar nada.

**Con dos reintentos a la vez:** el segundo espera en esa primera línea. Cuando
el primero confirma, `FOR UPDATE` entrega al segundo la versión **recién
confirmada** de la fila, no la de su instantánea inicial: lee `fulfilled` y
devuelve el resultado anterior. Solo funciona porque el bloqueo se toma antes de
leer el estado; al revés sería el clásico comprobar-y-luego-actuar y los dos
reservarían. Si la aplicación se cae antes de confirmar, todo se deshace y la
solicitud vuelve a `pending`, que también es correcto: no consumió nada.

## 3 · Por qué vive en la base de datos y qué se pierde

Porque «el mismo inventario no se reparte dos veces» es una propiedad **de los
datos**, no de la aplicación. En Ruby harían falta exactamente los mismos
bloqueos, con la diferencia de que ahí hay que acordarse: el job que reserva, la
consola de soporte y el importador tendrían cada uno su copia de la regla, y
bastaría con que uno se la saltara.

Se pierde el ecosistema de pruebas (quedan `psql` y `ASSERT`, que es lo que hace
`test.sql`), el versionado cómodo (desplegar es un `CREATE OR REPLACE` en una
migración, sin vuelta atrás fácil), la portabilidad —esto es PostgreSQL para
siempre— y la observabilidad: para el APM es una sola línea. Y lo más caro: la
lógica de negocio queda en dos sitios, y el siguiente desarrollador tiene que
saber mirar en los dos.

## 4 · Qué índice y cuál es el plan

```sql
CREATE INDEX idx_stock_lots_fifo
  ON stock_lots (material_id, warehouse_id, received_at, id)
  WHERE quantity > 0;
```

Las columnas van en el orden de la consulta: igualdad por `(material_id,
warehouse_id)` y luego el orden `(received_at, id)`, el desempate exacto del
enunciado. Así el índice entrega las filas ya ordenadas y **no hace falta un
`Sort`** — que importa porque el bloqueo es perezoso, y un `Sort` obligaría a
materializar todos los lotes antes de tomar el primero.

Es **parcial** porque los lotes agotados no se borran, son historial. Sobre
4.000.000 de lotes con solo 200.149 con existencias, el índice parcial ocupa
**9,7 MB** frente a los 189 MB del mismo índice sin el predicado. El plan real,
en caliente:

```
LockRows (actual time=0.089..0.104 rows=6 loops=1)
  Buffers: shared hit=13
  ->  Index Scan using idx_stock_lots_fifo on stock_lots (rows=6)
        Index Cond: ((material_id = 1234) AND (warehouse_id = 7))
Execution Time: 0.150 ms
```

Sin él, la misma consulta es `Seq Scan` + `Sort`: 33.346 buffers y 192 ms para
las mismas 6 filas. El peaje: `quantity` está indexada, así que descontar un lote
impide la actualización HOT — se paga en escritura lo que se ahorra en lectura.
Los otros dos índices son `stock_movements (request_id)`, para el retorno
idempotente y la invariante 1, y `stock_lots (warehouse_id)`, peaje del supuesto
S2.

## Supuestos

- **D1 · Reservar cero deja la solicitud en `backordered`, no en `partial`,
  aunque `p_allow_partial` sea `TRUE`.** Me separo de la letra a propósito.
  Literalmente, «reserva lo que haya y queda en `partial`» incluye reservar cero;
  pero `partial` es terminal por la regla de idempotencia, así que una solicitud
  que no consumió ni un gramo quedaría congelada para siempre. La regla queda
  simple: **`partial` es que consumió algo; `backordered`, que no consumió
  nada**, y lo que no consumió se puede reintentar. El caso 11 de `test.sql` es
  justo eso: sin inventario, un lote que entra después, y el reintento que la
  resuelve.
- **S2 · «Almacén desconocido» = un `warehouse_id` sin un solo lote
  registrado.** No hay tabla `warehouses` donde comprobarlo de verdad. Es
  distinto de «este material no tiene lotes aquí», que no es error sino falta de
  inventario. Punto débil: un almacén recién abierto daría `ESM04`.
- **S3 · `ESM02` y `ESM03` son inalcanzables con el esquema intacto.** La clave
  foránea y el `CHECK (quantity_required > 0)` ya los impiden. Se quedan como
  defensa en profundidad, pero `test.sql` no los ejercita: provocarlos exigiría
  desactivar una restricción, y el enunciado lo prohíbe. Preferí decirlo antes
  que fingir una prueba.
- **S4 · `pending`, `backordered` y `failed` son reintentables** — ninguno
  consumió nada. La función nunca escribe `failed`: una excepción aborta la
  transacción, así que no hay forma de persistirlo desde aquí.
- **S5 · El consumo parte de `quantity_reserved`, no de cero**, para que la
  invariante 1 se sostenga sola aunque la solicitud llegue a medias.

## Qué dejaría fuera

La función inversa (`release_material`) y la reserva multi-almacén. Ninguna la
pide el enunciado, y la segunda necesita una política de negocio que nadie ha
escrito: ¿coste de traslado?, ¿almacén preferente?

## Qué haría con más tiempo

1. **Una tabla `warehouses`**, para que `ESM04` deje de ser una heurística.
2. **Devolver el desglose por lote**, no solo `lots_used`: la planta quiere saber
   de qué lotes salió el material.
3. **Medir la contención con `pgbench`** sobre un material caliente.
   `test_concurrencia.sh` prueba que el bloqueo funciona con dos sesiones, no
   dónde se cae con doscientas.
