# Parte 2 — Notas

## Enfoque

El kerf se carga **dentro** de la pieza (`Config#footprint` = longitud + kerf), y
con eso el problema se queda en un empaquetado clásico: una barra admite un
conjunto de piezas si la suma de sus `footprint` cabe en la longitud útil
(longitud − despuntes). Todo lo demás cuelga de ahí. Las piezas viven en un
**multiconjunto** `longitud => cantidad` (`PiecePool`) y no en una lista de 5.000
elementos: las entradas reales son media docena de medidas muy repetidas, así que
el coste va con el número de medidas distintas.

## 1 · Qué heurística elegí y cuál descarté

**FFD dentro de la barra + mejor ajuste al elegir la barra**, dos decisiones
voraces encadenadas: (1) llenar una barra colocando siempre la pieza más larga
que quepa (`BarFill`); (2) antes de abrir ninguna, **simular** el llenado de cada
tipo disponible y abrir la que menos material desperdicia, `(longitud − piezas) /
longitud`, con el orden de inventario como desempate.

El paso 2 es lo que aporta sobre un FFD normal, porque aquí los contenedores no
son iguales: hay varios tipos de barra y el inventario es limitado. En el ejemplo
del enunciado se nota al final —las dos últimas piezas de 820,5 salen de una
BAR-B de 4.000 en vez de gastar una BAR-A— y el plan cierra en **8 barras, la
cota inferior** (⌈42.183 / 5.850⌉), con 8,66 % de desperdicio.

**Descarté programación entera / generación de columnas:** da el óptimo y es el
estándar en corte industrial, pero es NP-difícil, necesita un resolutor
—prohibido— y no cabe en milisegundos. Y Next-Fit puro, que son cuatro líneas
pero nunca vuelve a mirar los huecos que deja. Coste O(barras × tipos × medidas
distintas): 5.000 piezas de 5 medidas → 3 ms; 5.000 medidas distintas → 0,5 s.

## 2 · Cómo mediría si un plan es bueno

Tres números, porque uno solo se deja engañar. **`waste_ratio`** es el titular,
pero baja solo con dejar piezas sin producir: únicamente compara planes que
producen lo mismo. **Barras usadas frente a la cota inferior** ⌈Σ footprints /
longitud útil máxima⌉ es la referencia honesta sin resolver el óptimo: dice
cuánto margen queda de verdad. Y el **aprovechamiento de la peor barra**, donde
se esconde toda heurística voraz: las primeras salen bien y el destrozo se
acumula en la última. En producción añadiría los **retales reutilizables** —los
sobrantes que vuelven al almacén en vez de a la chatarra—, que es lo que mira la
planta y no siempre coincide con el `waste_ratio`.

## 3 · Si mañana hay que «priorizar los retales cortos»

Es cambiar **un método**: `BarFill#waste_ratio`, la única función de puntuación
del planificador. Bastaría con desempatar por longitud de barra ascendente o,
más fino, penalizar el desperdicio con un factor que premie las barras cortas. El
algoritmo —llenado voraz, consumo del multiconjunto, control de inventario— no se
toca. Que la puntuación sea un método y no una condición repartida por el bucle
fue deliberado: es el cambio que más veces pide una planta.

## Supuestos

- **S1 · El kerf se cobra por cada pieza, incluida la última.** Es la lectura
  conservadora: nunca sobreestima la capacidad, así que todo plan es ejecutable.
  La alternativa (N−1 cortes) gana milímetros a cambio de planes que no cierran.
- **S2 · `waste_ratio` se mide sobre la barra entera:** una barra abierta está
  gastada aunque sobre medio metro. Medirlo sobre la longitud útil daría un
  número más bonito y menos cierto.
- **S3 · `:too_long` se mide contra el catálogo, no contra las existencias:** si
  cabría en un tipo agotado el motivo es `:out_of_stock`, que se arregla
  comprando.
- **S4 · Tolerancia de 1e-6 mm** al comprobar si algo cabe: las longitudes llegan
  en flotantes y sin holgura cinco piezas de 1.170 podrían no caber en 5.850.
- **S5 · Una entrada inválida es un error, no un resultado** (`ArgumentError`).
  Lo que el enunciado pide devolver «en vez de fallar» es la falta de material,
  que sí es una situación normal.

## Qué dejaría fuera y qué haría con más tiempo

Fuera quedan las posiciones absolutas de corte —salen del plan en tres líneas,
pero no se piden— y agrupar por perfil o color: aquí el inventario es
intercambiable. Con más tiempo: **reutilizar los retales** por encima de un
umbral, que es lo que hace la planta; un **pase de mejora local** que reparta las
piezas de la última barra entre los huecos de las anteriores, barato y suele
arañar una barra entera; y **medir contra el óptimo** con una fuerza bruta
acotada a 12 piezas, para saber cuánto cuesta ser voraz.
