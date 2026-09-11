# frozen_string_literal: true

# Sustituto mínimo de FactoryBot, que el enunciado no permite.
#
# Todas las directivas de una prueba comparten `line_item_id` y una base de
# tiempo fija; `created_at` avanza un segundo por cada fila creada, de modo que
# el orden de escritura del historial es el orden en que se llama al helper.
# Para forzar un empate exacto de `created_at` (y ejercitar el desempate por
# `id`) se pasa `created_at:` a mano.
module DirectiveFactory
  BASE_TIME     = Time.utc(2026, 1, 1, 12, 0, 0)
  LINE_ITEM_ID  = 4_242

  def directive(key:, value:, version:, source: "resolution", unit_uid: nil,
                line_item_id: LINE_ITEM_ID, created_at: nil)
    LineItemDirective.create!(
      line_item_id: line_item_id,
      directive_type: unit_uid ? LineItemDirective::UNIT : LineItemDirective::HEADER,
      unit_uid: unit_uid,
      key: key,
      value: value,
      source: source,
      version: version,
      created_at: created_at || next_write_time
    )
  end

  # Azúcar para leerse como el enunciado: header(...) y unit("unit-a", ...).
  def header(...)
    directive(...)
  end

  def unit(unit_uid, **attributes)
    directive(unit_uid: unit_uid, **attributes)
  end

  def resolve(unit_uids:, version:, keys: nil, line_item_id: LINE_ITEM_ID)
    EffectiveConfigResolver.call(
      line_item_id: line_item_id,
      unit_uids: unit_uids,
      version: version,
      keys: keys
    )
  end

  # Cuenta las consultas reales a PostgreSQL de un bloque, ignorando el ruido
  # del adaptador (TRANSACTION, SCHEMA, CACHE).
  def count_queries
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      queries << payload[:sql]
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  private

  def next_write_time
    @write_offset = (@write_offset || 0) + 1
    BASE_TIME + @write_offset.seconds
  end
end
