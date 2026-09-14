# Parte 4 — Video explicativo

**Parte explicada: la 3 — función de reserva de inventario en PL/pgSQL.**
Es la que tiene la decisión menos evidente de las tres (bloqueo, idempotencia y
concurrencia) y la que peor se entiende leyendo el código en frío.

🎥 <https://drive.google.com/file/d/1QUtqSRAzSsMNyPhkFByK55tfMGXTQAiP/view?usp=sharing>

Duración: menos de 3 minutos. Qué se cuenta, en este orden:

1. **El problema real:** dos procesos reservando el mismo material a la vez, y
   el reintento que duplicaría la reserva.
2. **Cómo lo estructuré:** bloquear la solicitud *antes* que el inventario. Por
   qué ese orden y no al revés.
3. **La decisión que pudo ser otra:** `FOR UPDATE` frente a `SKIP LOCKED`.
   `SKIP LOCKED` escala mejor, pero saltarse un lote bloqueado es romper el
   FIFO, que aquí es requisito y no preferencia.
4. **Qué tiene de flojo:** se rompe primero con contención alta sobre un
   material caliente; no cubrí la reserva multi-almacén; con dos días más,
   colas por material y pruebas de carga con `pgbench`.

El detalle escrito de todo esto está en
[`../parte3_postgres/NOTAS.md`](../parte3_postgres/NOTAS.md).
