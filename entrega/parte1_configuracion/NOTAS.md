# Parte 1 — Notas

## Enfoque

La resolución se parte en dos mitades según dónde sale más barata cada regla.

**En PostgreSQL (una sola consulta).** Un `DISTINCT ON (directive_type, unit_uid,
key, user_intent)` ordenado por `version DESC, created_at DESC, id DESC` deja,
por cada ámbito y clave, como mucho dos filas: la ganadora por las reglas 1 y 2,
y la mejor directiva de origen `user` cuando la clave está en
`USER_INTENT_KEYS`. Añadir `user_intent` como cuarta clave de agrupación es lo
que permite traer las dos candidatas de una pasada.

**En Ruby (`EffectiveConfig::Resolution`).** Elegir entre esas dos candidatas es
una comparación booleana (regla 3); encima van la herencia desde la cabecera
(regla 4) y la excepción dimensional (regla 5). Trabaja sobre las pocas filas
ganadoras, no sobre el historial.

Así el número de consultas es **1**, independiente de unidades y de claves: lo
que crece es el tamaño de los parámetros `text[]`, no la cantidad de viajes.
`keys:` se concatena al `WHERE`, no al resultado — y se nota en el plan: con
`keys: %w[width glass_type]` el filtro pasa a ser `Index Cond` y la consulta lee
72 filas en vez de 432 (65 páginas en vez de 129).

## El índice

```
(line_item_id, directive_type, unit_uid, key, version DESC, created_at DESC, id DESC)
```

`line_item_id` primero porque es la única igualdad que acota la tabla entera;
después las tres claves de agrupación del `DISTINCT ON`; al final el desempate de
la regla 2 en el mismo sentido que el `ORDER BY`, de modo que la primera fila de
cada grupo ya es la ganadora. Plan real sobre 2.016.000 filas:

```
Unique  (rows=68)
  ->  Incremental Sort   Presorted Key: directive_type, unit_uid, key
        ->  Index Scan using index_line_item_directives_on_resolution
              Index Cond: (line_item_id = 1234) AND (version <= 9)
Execution Time: 3.035 ms
```

Solo queda un `Incremental Sort` por `user_intent`, que es una expresión y no
puede vivir en el índice. Descarté `(line_item_id, key, version)`: sirve cuando
siempre se pasa `keys:`, pero con `keys: nil` obliga a un `Sort` completo.

## Supuestos

- **S1 · La excepción dimensional también anula la herencia.** El enunciado dice
  que `width`, `height`, `dlo_width` y `dlo_height` «se resuelven únicamente por
  las reglas 1 y 2». Lo leo en sentido literal: tampoco heredan de la cabecera.
  La lectura alternativa —que la regla 5 solo excluye la regla 3— dejaría la
  regla **vacía de contenido**, porque ninguna clave dimensional está en
  `USER_INTENT_KEYS` y la regla 3 nunca podría aplicárseles de todos modos.
  Además encaja con el dominio: la medida de una unidad es suya, no del renglón.
  Si el criterio de la casa fuera el contrario, el cambio es una línea en
  `KeyRules.inheritable?`.
- **S2 · Desempate por `id`.** «Gana la escrita más tarde» se implementa con
  `created_at DESC`; cuando dos filas comparten versión *y* `created_at`, gana el
  `id` mayor. Es el único orden total disponible en el esquema y coincide con el
  orden de inserción de una secuencia.
- **S3 · `value = NULL` es un valor, no una ausencia.** Una directiva de unidad
  con `value` nulo tapa la cabecera y aparece en el resultado con `nil`. En un
  historial append-only, escribir `NULL` es la única forma de «borrar» algo.
- **S4 · Unidad sin directivas → hash vacío, no ausente.** El llamador pidió esa
  unidad; devolver `{}` distingue «no tiene configuración» de «no la pediste».
- **S5 · Una clave sin ninguna directiva aplicable no aparece**, ni siquiera
  cuando se pide en `keys:`.

## Qué dejaría fuera

Nada del enunciado. No hay controlador ni serialización: el entregable es el
servicio, y una capa HTTP encima solo añadiría ruido. Tampoco hay validación de
vocabulario de claves —no está en el esquema— ni caché.

## Qué haría con más tiempo

1. **Caché por `(line_item_id, version)`.** El historial es inmutable, así que
   una resolución ya calculada a una versión cerrada **nunca** cambia: es un caso
   perfecto para `Rails.cache` con clave `líneaitem/versión`, sin invalidación.
2. **Materialización incremental.** Con renglones de muchas versiones, guardar
   una tabla de estado efectivo por versión y aplicarle solo el delta de cada
   guardado, dejando esta consulta como el camino de reconstrucción.
3. **`INCLUDE (source, value)` en el índice** para conseguir un *index-only
   scan*. No lo hice porque `value` es `TEXT` y engordaría el índice con datos
   que casi nunca se leen enteros; habría que medirlo con datos reales antes.
4. **Resolver varios renglones a la vez.** La consulta ya está a un `= ANY` de
   aceptar `line_item_ids`, que es lo que pediría una vista de cotización
   completa.
