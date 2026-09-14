# Parte 1 — Notas

## Enfoque

La resolución se parte en dos mitades según dónde sale más barata cada regla.

**En PostgreSQL, una sola consulta.** Un `DISTINCT ON (directive_type, unit_uid,
key, user_intent)` ordenado por `version DESC, created_at DESC, id DESC` deja,
por cada ámbito y clave, como mucho dos filas: la ganadora por las reglas 1 y 2,
y la mejor directiva `user` cuando la clave está en `USER_INTENT_KEYS`. Añadir
`user_intent` como cuarta clave de agrupación es lo que trae las dos candidatas
en una sola pasada.

**En Ruby (`EffectiveConfig::Resolution`).** Elegir entre esas dos candidatas es
una comparación booleana (regla 3); encima van la herencia desde la cabecera
(regla 4) y la excepción dimensional (regla 5), sobre las pocas filas ganadoras
y no sobre el historial.

Así el número de consultas es **1**, independiente de unidades y de claves: lo
que crece es el tamaño de los parámetros `text[]`, no los viajes. `keys:` se
concatena al `WHERE`, y se nota en el plan: con `keys: %w[width glass_type]` el
filtro pasa a `Index Cond` y se leen 72 filas en vez de 432.

## El índice

`(line_item_id, directive_type, unit_uid, key, version DESC, created_at DESC, id DESC)`

`line_item_id` primero porque es la única igualdad que acota la tabla; después
las tres claves de agrupación del `DISTINCT ON`; al final el desempate de la
regla 2 en el mismo sentido que el `ORDER BY`, para que la primera fila de cada
grupo ya sea la ganadora. Sobre 2.016.000 filas el plan es `Index Scan` con
`Index Cond: (line_item_id = 1234) AND (version <= 9)` e `Incremental Sort` con
tres claves presortadas, en **3,0 ms**. El `Sort` que queda es por `user_intent`,
que es una expresión y no puede vivir en el índice. Descarté `(line_item_id,
key, version)`: sirve si siempre se pasa `keys:`, pero con `keys: nil` obliga a
ordenar entero.

## Supuestos

- **S1 · La excepción dimensional también anula la herencia.** Leo «se resuelven
  únicamente por las reglas 1 y 2» en sentido literal: las dimensionales tampoco
  heredan de la cabecera. La lectura alternativa deja la regla vacía de
  contenido, porque ninguna de esas claves está en `USER_INTENT_KEYS` y la regla
  3 nunca podría aplicárseles. Encaja con el dominio —la medida de una unidad es
  suya—, y si el criterio de la casa fuera el otro, es una línea en
  `KeyRules.inheritable?`.
- **S2 · Desempate por `id`** cuando dos filas comparten versión *y*
  `created_at`: es el único orden total del esquema.
- **S3 · `value = NULL` es un valor, no una ausencia:** tapa la cabecera y sale
  como `nil`. En un historial append-only es la única forma de borrar algo.
- **S4 · Unidad sin directivas → `{}`, no ausente.** Distingue «no tiene
  configuración» de «no la pediste».
- **S5 · Una clave sin directiva aplicable no aparece**, ni pidiéndola en `keys:`.

## Qué dejaría fuera

Nada del enunciado. Sin controlador ni serialización: el entregable es el
servicio. Tampoco validación del vocabulario de claves —no está en el esquema—
ni caché.

## Qué haría con más tiempo

1. **Caché por `(line_item_id, version)`.** El historial es inmutable: una
   resolución a una versión cerrada nunca cambia, así que no hay invalidación.
2. **Materialización incremental:** una tabla de estado efectivo por versión que
   recibe el delta de cada guardado, con esta consulta como reconstrucción.
3. **`INCLUDE (source, value)`** para un *index-only scan*: no lo hice porque
   `value` es `TEXT` y engordaría el índice, pero hay que medirlo.
4. **Resolver varios renglones a la vez:** está a un `= ANY` de aceptarlo.
