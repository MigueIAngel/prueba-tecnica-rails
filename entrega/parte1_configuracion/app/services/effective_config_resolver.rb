# frozen_string_literal: true

# Resuelve la configuración efectiva de un renglón de cotización a una versión
# objetivo, unidad por unidad.
#
#   EffectiveConfigResolver.call(
#     line_item_id: 42,
#     unit_uids:    %w[unit-a unit-b],
#     version:      7,
#     keys:         nil   # nil = todas las claves; array = solo esas
#   )
#   # => { "unit-a" => { "width" => "1200", "glass_type" => "laminated" }, ... }
#
# El reparto de responsabilidades es el siguiente:
#
#   * EffectiveConfig::DirectiveQuery — una sola consulta; resuelve las reglas
#     1 (corte por versión) y 2 (gana la más reciente), y marca las candidatas
#     de la regla 3.
#   * EffectiveConfig::Resolution     — reglas 3, 4 (herencia) y 5 (excepción
#     dimensional) en memoria, sobre las pocas filas que devolvió la consulta.
#   * EffectiveConfig::KeyRules       — las listas de claves de las reglas 3 y 5.
class EffectiveConfigResolver
  def self.call(...)
    new(...).call
  end

  # @param line_item_id [Integer]
  # @param unit_uids [Array<String>]
  # @param version [Integer] versión objetivo V
  # @param keys [Array<String>, nil] nil = todas
  def initialize(line_item_id:, unit_uids:, version:, keys: nil)
    @line_item_id = Integer(line_item_id)
    @version      = Integer(version)
    @unit_uids    = Array(unit_uids).map(&:to_s).uniq
    @keys         = keys && Array(keys).map(&:to_s).uniq
  end

  def call
    # Sin unidades no hay nada que resolver, y con `keys: []` el llamador pidió
    # explícitamente ninguna clave. En ambos casos, cero consultas.
    return {} if @unit_uids.empty?
    return @unit_uids.index_with { {} } if @keys && @keys.empty?

    EffectiveConfig::Resolution.new(
      rows: query.rows,
      unit_uids: @unit_uids,
      keys: @keys
    ).to_h
  end

  # Expuesto para las pruebas: permite comprobar que `keys:` viaja al WHERE de
  # la consulta y no se aplica al final, en Ruby.
  def query
    @query ||= EffectiveConfig::DirectiveQuery.new(
      line_item_id: @line_item_id,
      unit_uids: @unit_uids,
      version: @version,
      keys: @keys
    )
  end
end
