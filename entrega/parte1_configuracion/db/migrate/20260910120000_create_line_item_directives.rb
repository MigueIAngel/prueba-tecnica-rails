# frozen_string_literal: true

# Historial append-only de directivas de configuración. Las filas se acumulan:
# no se actualizan ni se borran, así que no hay `updated_at`.
class CreateLineItemDirectives < ActiveRecord::Migration[7.2]
  def change
    create_table :line_item_directives do |t|
      t.bigint   :line_item_id,   null: false
      t.string   :directive_type, null: false, limit: 10 # 'header' | 'unit'
      t.string   :unit_uid,       limit: 64              # NULL cuando es 'header'
      t.string   :key,            null: false, limit: 64
      t.text     :value
      t.string   :source,         null: false, limit: 16 # 'user'|'resolution'|'preserved'|'default'
      t.integer  :version,        null: false
      t.datetime :created_at,     null: false, precision: 6
    end

    # Índice de resolución. El orden de las columnas sigue, en este orden:
    #
    #   1. `line_item_id`   — igualdad; es el filtro que acota la tabla entera.
    #   2. `directive_type`,
    #      `unit_uid`, `key` — las claves de agrupación del DISTINCT ON.
    #   3. `version`, `created_at`, `id` descendentes — el desempate de la
    #      regla 2, de modo que la primera fila de cada grupo ya es la ganadora.
    #
    # Con esto el planificador recorre el índice en el orden que necesita la
    # consulta y solo le queda un Incremental Sort por la bandera `user_intent`,
    # que es una expresión y no puede vivir en el índice.
    add_index :line_item_directives,
              %i[line_item_id directive_type unit_uid key version created_at id],
              order: { version: :desc, created_at: :desc, id: :desc },
              name: "index_line_item_directives_on_resolution"

    add_check_constraint :line_item_directives,
                         "directive_type IN ('header', 'unit')",
                         name: "chk_line_item_directives_type"

    # Invariante del esquema: las cabeceras no tienen unidad y las unidades sí.
    add_check_constraint :line_item_directives,
                         "(directive_type = 'header') = (unit_uid IS NULL)",
                         name: "chk_line_item_directives_scope"
  end
end
