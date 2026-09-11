# frozen_string_literal: true

module EffectiveConfig
  # Objeto de valor: toma las filas candidatas que devolvió DirectiveQuery y
  # produce el hash efectivo. Aquí solo se aplican las reglas 3, 4 y 5; las
  # reglas 1 y 2 ya las resolvió la base de datos.
  class Resolution
    # Distingue «la clave no tiene ninguna directiva aplicable» de «la directiva
    # ganadora tiene valor NULL», que son cosas distintas: la segunda sí aparece
    # en el resultado, con valor nil.
    MISSING = Object.new.freeze
    private_constant :MISSING

    def initialize(rows:, unit_uids:, keys:)
      @unit_uids = unit_uids
      @keys      = keys
      @header    = {}
      @units     = {}

      rows.each { |row| index(row) }
    end

    # @return [Hash{String => Hash{String => String, nil}}]
    def to_h
      @unit_uids.each_with_object({}) do |unit_uid, result|
        unit = @units[unit_uid] || {}
        result[unit_uid] = effective_for(unit)
      end
    end

    private

    def index(row)
      bucket = if row["directive_type"] == LineItemDirective::HEADER
                 @header
               else
                 @units[row["unit_uid"]] ||= {}
               end

      key = row["key"]
      # Regla 3: entre las dos candidatas de una misma clave gana la de origen
      # `user`. La consulta solo marca `user_intent` cuando la clave está en
      # USER_INTENT_KEYS, así que basta preferir la marcada.
      return if bucket.key?(key) && !row["user_intent"]

      bucket[key] = row["value"]
    end

    def effective_for(unit)
      keys_for(unit).each_with_object({}) do |key, values|
        value = resolve(unit, key)
        values[key] = value unless value.equal?(MISSING)
      end
    end

    def resolve(unit, key)
      return unit[key] if unit.key?(key)
      # Regla 5: las dimensionales no heredan de la cabecera.
      return MISSING unless KeyRules.inheritable?(key)

      @header.fetch(key, MISSING)
    end

    # Con `keys: nil` el conjunto efectivo es la unión de las claves de la
    # unidad y las de la cabecera. Las dimensionales que solo existen en la
    # cabecera quedan fuera, porque no se heredan (regla 5).
    def keys_for(unit)
      return @keys if @keys

      unit.keys | @header.keys.select { |key| KeyRules.inheritable?(key) }
    end
  end
end
