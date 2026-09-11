# Parte 2 — Planificador de corte de material

`CutPlanner` reparte una lista de piezas entre las barras disponibles en
almacén y devuelve el plan de corte: qué sale de cada barra, qué no se pudo
producir y cuánto material se tira.

```ruby
plan = CutPlanner.new(
  pieces: [{ length: 1_450.0, quantity: 12 }, { length: 820.5, quantity: 30 }],
  stock:  [{ id: "BAR-A", length: 6_000.0, available: 8 },
           { id: "BAR-B", length: 4_000.0, available: 3 }],
  config: { kerf: 4.0, head_trim: 100.0, tail_trim: 50.0 }
).call

plan.bars_used                # 8
plan.bars_used_by_stock_id    # { "BAR-A" => 7, "BAR-B" => 1 }
plan.unplaced                 # []
plan.waste_ratio              # 0.0866...
```

Ruby puro: ni Rails, ni base de datos, ni salida por pantalla. Las decisiones de
diseño y los supuestos están en [`NOTAS.md`](NOTAS.md).

## Requisitos

Ruby 3.1 o superior (desarrollado con 3.3.6). La única gema es RSpec.

## Pruebas

```bash
bundle install
bundle exec rspec
```

32 ejemplos. Cubren los tres casos que exige el enunciado —inventario
insuficiente, una pieza más larga que cualquier barra útil, y un caso donde el
kerf cambia el resultado— más los despuntes, el determinismo, el cálculo del
`waste_ratio` comprobado a mano, las invariantes del plan y dos pruebas de
rendimiento con 5.000 piezas.

## Probarlo a mano

```bash
ruby -Ilib -e 'require "cut_planner"
plan = CutPlanner.new(
  pieces: [{ length: 1_450.0, quantity: 12 }, { length: 820.5, quantity: 30 }],
  stock:  [{ id: "BAR-A", length: 6_000.0, available: 8 },
           { id: "BAR-B", length: 4_000.0, available: 3 }],
  config: { kerf: 4.0, head_trim: 100.0, tail_trim: 50.0 }
).call
pp plan.to_h'
```

## El plan que devuelve

| Método | Qué es |
| --- | --- |
| `plan.bars` | Barras abiertas, en el orden en que se abrieron. |
| `plan.unplaced` | Lo que no se pudo producir, con el motivo (`:too_long` o `:out_of_stock`). |
| `plan.waste_ratio` | Desperdicio / material consumido, contando despuntes, kerf y retales. |
| `plan.bars_used_by_stock_id` | Barras abiertas de cada tipo; nunca más de las disponibles. |
| `plan.to_h` | El plan entero como estructuras de Ruby, para serializar o comparar. |

De cada barra (`CutPlanner::PlannedBar`) interesan dos números distintos:

- `remainder` — el trozo de longitud útil que queda sin cortar: el **retal**
  físico que vuelve al almacén.
- `waste` — todo el material de la barra que no sale como pieza: despuntes +
  kerf + `remainder`. Es el que alimenta `waste_ratio`.

## Mapa del código

| Archivo | Qué hace |
| --- | --- |
| `lib/cut_planner.rb` | El servicio: aparta lo que no cabe, abre barras y confirma cada llenado. |
| `lib/cut_planner/config.rb` | Kerf y despuntes, y las medidas que se derivan de ellos. |
| `lib/cut_planner/piece_pool.rb` | Multiconjunto de piezas pendientes, de mayor a menor. |
| `lib/cut_planner/bar_fill.rb` | Simulación del llenado de una barra; aquí está la función de puntuación. |
| `lib/cut_planner/stock_item.rb` | Un tipo de barra y las que quedan disponibles. |
| `lib/cut_planner/planned_bar.rb` | Barra abierta: piezas y sobrante. |
| `lib/cut_planner/placed_piece.rb` | Piezas de una medida dentro de una barra. |
| `lib/cut_planner/unplaced_piece.rb` | Lo que no se pudo producir, con el motivo. |
| `lib/cut_planner/cut_plan.rb` | El resultado y sus totales. |
| `spec/support/plan_helpers.rb` | Azúcar de las pruebas, sin FactoryBot. |
