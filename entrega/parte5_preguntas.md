# Parte 5 

---

## 1

Puede que estén midiendo cosas diferentes. **(a)** Bajó el promedio, pero empeoraron los casos lentos: con caché unos tardan 50 ms y otros 3 s. **(b)** Cambió la cantidad o tipo de usuarios, así que los promedios ya no son comparables. **(c)** Mejoró el endpoint, pero empeoró el flujo: ahora se hacen varias peticiones de 400 ms en vez de una de 800. Mediría p95/p99 antes y después, número de peticiones por tarea y latencia real desde el navegador.

---

## 2

Preguntaría: **1)** ¿Se respetan los precios modificados manualmente? **2)** ¿Se calcula con la fecha de la cotización o la actual? **3)** ¿Se necesita poder deshacer y tener trazabilidad? **4)** ¿Cuántos renglones hay y de dónde sale el precio? Las respuestas cambian si es un `UPDATE`, un recálculo selectivo o un job. Sin más información, haría el recálculo selectivo con previsualización de cambios y traza.

---

## 3

Primero mediría dónde se van las seis horas: CPU, E/S, bloqueos o base de datos. Según eso, procesaría solo lo que cambió, paralelizaría por almacén, ejecutaría etapas independientes en paralelo y revisaría índices y planes. También agruparía escrituras en lotes en vez de fila por fila y separaría lo urgente de lo que puede esperar. Mi apuesta inicial sería encontrar el cuello de botella y atacar principalmente escrituras y paralelización.
