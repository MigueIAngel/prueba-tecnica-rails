# Parte 2 — Notas

## Enfoque

El kerf se carga **dentro** de la pieza (`Config#footprint` = longitud + kerf).
Con eso el problema se queda en un empaquetado clásico: una barra admite un
conjunto de piezas si la suma de sus `footprint` cabe en la longitud útil
(longitud − despunte inicial − despunte final). Todo lo demás cuelga de ahí.

Las piezas viven en un **multiconjunto** `longitud => cantidad` ordenado de mayor
a menor (`PiecePool`), no en una lista de 5.000 elementos: las entradas reales
son media docena de medidas muy repetidas, y así el coste va con el número de
medidas distintas y no con el de piezas.

## 1 · Qué heurística elegí y cuál descarté

**FFD dentro de la barra + mejor ajuste al elegir la barra**, dos decisiones
voraces encadenadas:

1. Llenar una barra: colocar siempre la pieza más larga que quepa (`BarFill`).
2. Elegir cuál abrir: antes de abrir ninguna se **simula** el llenado de cada
   tipo disponible y se abre la que menos material desperdicia,
   `(longitud − piezas) / longitud`. Empate → orden de entrada del inventario.

El paso 2 es lo que aporta sobre un FFD normal, porque aquí los contenedores no
son iguales: hay varios tipos de barra y con inventario limitado. En el ejemplo
del enunciado se nota al final —las dos últimas piezas de 820,5 salen de una
BAR-B de 4.000 en vez de gastar una BAR-A de 6.000— y el plan cierra en **8
barras, que es la cota inferior** (⌈42.183 / 5.850⌉ = 8), con 8,66 % de
desperdicio.

**Descarté programación entera / generación de columnas:** da el óptimo y es el
estándar en corte industrial, pero es NP-difícil, necesita un resolutor
—prohibido— y no cabe en un presupuesto de milisegundos. También descarté
Next-Fit puro: cuatro líneas, pero desperdicia mucho más porque nunca vuelve a
mirar los huecos que deja.

Coste O(barras abiertas × tipos de barra × medidas distintas), nada exponencial:
5.000 piezas de 5 medidas → 3 ms; el peor caso, 5.000 piezas sin ninguna medida
repetida → 0,5 s. Las dos están en las pruebas.

## 2 · Cómo mediría si un plan es bueno

Tres números, porque uno solo se deja engañar:

- **`waste_ratio`** — el titular, pero baja solo con dejar piezas sin producir:
  únicamente compara planes que producen lo mismo.
- **Barras usadas frente a la cota inferior** ⌈Σ footprints / longitud útil
  máxima⌉. Es la referencia honesta sin resolver el óptimo: dice cuánto margen
  queda de verdad.
- **Aprovechamiento de la peor barra.** Ahí se esconde una heurística voraz: las
  primeras barras siempre salen bien y el destrozo se acumula en la última.

En producción añadiría el número de **retales reutilizables** (sobrantes por
encima de un umbral, que vuelven al almacén en vez de a la chatarra): es lo que
mira la planta, y no siempre coincide con el `waste_ratio`.

## 3 · Si mañana hay que «priorizar los retales cortos»

Es cambiar **un método**: `BarFill#waste_ratio`, la única función de puntuación
del planificador. Bastaría con desempatar por longitud de barra ascendente, o
—más fino— penalizar el desperdicio con un factor que premie las barras cortas.
El algoritmo (llenado voraz, consumo del multiconjunto, control de inventario) no
se toca. Que la puntuación sea un método y no una condición repartida por el
bucle fue deliberado: es el cambio que más veces pide una planta.

## Supuestos

- **S1 · El kerf se cobra por cada pieza, incluida la última.** Es la lectura
  conservadora: nunca sobreestima la capacidad, así que todo plan que sale de
  aquí es ejecutable. La alternativa (N−1 cortes, asumiendo que el último trozo
  es chatarra) gana milímetros a cambio de planes que en planta no cierran.
- **S2 · `waste_ratio` se mide sobre la barra entera.** Consumido = suma de las
  longitudes **totales** de las barras abiertas: una barra abierta está gastada
  aunque sobre medio metro. Medirlo solo sobre la longitud útil daría un número
  más bonito y menos cierto.
- **S3 · `:too_long` se mide contra el catálogo, no contra las existencias.** Lo
  que no cabe en la barra más larga del catálogo no se podrá cortar nunca; si
  cabría en un tipo agotado, el motivo es `:out_of_stock`, que se arregla
  comprando. Sin catálogo, todo es `:out_of_stock`.
- **S4 · Tolerancia de 1e-6 mm** al comprobar si algo cabe
  (`CutPlanner::TOLERANCE`): las longitudes llegan en flotantes y sin holgura
  cinco piezas de 1.170 podrían no caber en 5.850 por un error binario.
- **S5 · Una entrada inválida es un error, no un resultado.** Longitud ≤ 0 o
  cantidad negativa levantan `ArgumentError`. Lo que el enunciado pide devolver
  «en vez de fallar» es la falta de material, que sí es una situación normal.

## Qué dejaría fuera

Las posiciones absolutas de corte dentro de la barra: son la acumulada de los
`footprint` y se derivan del plan en tres líneas, pero no las pide el enunciado.
Tampoco agrupo por perfil o color: aquí todo el inventario es intercambiable.

## Qué haría con más tiempo

1. **Reutilizar los retales:** devolver al inventario los sobrantes por encima de
   un umbral y replanificar. Es lo que hace la planta de verdad.
2. **Un pase de mejora local:** intentar repartir las piezas de la última barra
   —siempre la peor— entre los huecos de las anteriores. Barato, y suele arañar
   una barra entera.
3. **Medir contra el óptimo** con una fuerza bruta acotada a 12 piezas, para
   saber cuánto se pierde por ser voraz.
