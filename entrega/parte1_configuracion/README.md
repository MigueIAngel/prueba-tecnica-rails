# Parte 1 — Resolución de configuración efectiva

`EffectiveConfigResolver` responde, para un renglón de cotización y una versión
objetivo, cuál es el valor efectivo de cada clave en cada unidad, a partir del
historial append-only de directivas.

```ruby
EffectiveConfigResolver.call(
  line_item_id: 1,
  unit_uids:    %w[unit-a unit-b],
  version:      9,
  keys:         nil          # nil = todas las claves; array = solo esas
)
# => { "unit-a" => { "width" => "1250", "glass_type" => "laminated" }, ... }
```

Las decisiones de diseño y los supuestos están en [`NOTAS.md`](NOTAS.md).

## Requisitos

Ruby 3.3.6 · Rails 7.2 · PostgreSQL 13 o superior corriendo en local. Se asume
que el usuario del sistema puede conectarse sin contraseña (autenticación
`trust` o `peer`); si no, basta con exportar `DATABASE_URL`.

## Puesta en marcha

```bash
bundle install
bin/rails db:prepare      # crea las bases de desarrollo y de pruebas y migra
```

## Pruebas

```bash
bundle exec rspec
```

29 ejemplos. Cubren las cinco reglas de resolución, los cuatro casos que exige el
enunciado (empate de versión, herencia desde `header`, una clave donde `user`
gana a una `resolution` posterior y una clave dimensional donde `resolution` gana
a `user`) y los dos requisitos no funcionales: que `keys:` viaje al `WHERE` y que
el número de consultas no dependa de cuántas unidades o claves se pidan.

## Probarlo a mano

```bash
bin/rails db:seed
bin/rails runner 'pp EffectiveConfigResolver.call(
  line_item_id: 1, unit_uids: %w[unit-a unit-b unit-c], version: 9)'
```

```ruby
{"unit-a" => {"coating" => "ninguno", "width" => "1250", "glass_type" => "laminated"},
 "unit-b" => {"color_id" => "azul", "coating" => "solar", "glass_type" => "laminated"},
 "unit-c" => {"coating" => "solar", "glass_type" => "laminated"}}
```

Los datos de `db/seeds.rb` ejercitan las cinco reglas a la vez: `unit-a` fija su
propio `width` por las reglas 1 y 2 (la directiva `user` no manda porque la clave
es dimensional), `unit-b` conserva el `color_id` que eligió el usuario pese a un
cálculo posterior, `unit-c` lo hereda todo de la cabecera, y ninguna de las tres
hereda el `width` de la cabecera.

## Mapa del código

| Archivo | Qué hace |
| --- | --- |
| `app/services/effective_config_resolver.rb` | Punto de entrada; normaliza argumentos y orquesta. |
| `app/services/effective_config/directive_query.rb` | La única consulta: reglas 1 y 2, y las candidatas de la regla 3. |
| `app/services/effective_config/resolution.rb` | Reglas 3, 4 y 5 en memoria. |
| `app/services/effective_config/key_rules.rb` | `USER_INTENT_KEYS` y `DIMENSIONAL_KEYS`. |
| `app/models/line_item_directive.rb` | La tabla del historial. |
| `db/migrate/20260910120000_create_line_item_directives.rb` | Esquema del enunciado + índice de resolución. |
| `spec/support/directive_factory.rb` | Helper de datos y contador de consultas (sin FactoryBot). |
