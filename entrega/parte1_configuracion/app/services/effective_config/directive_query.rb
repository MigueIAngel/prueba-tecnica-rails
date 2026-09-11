# frozen_string_literal: true

module EffectiveConfig
  # La única consulta a base de datos de la resolución.
  #
  # Devuelve, para cada ámbito (la cabecera y cada unidad pedida) y cada clave,
  # como mucho dos filas candidatas:
  #
  #   * `user_intent = false` — la ganadora por las reglas 1 y 2 (versión más
  #     alta; a igual versión, la escrita más tarde).
  #   * `user_intent = true`  — la directiva de origen `user` más reciente,
  #     cuando la clave pertenece a USER_INTENT_KEYS. Es la candidata de la
  #     regla 3.
  #
  # Elegir entre las dos es una comparación booleana que se hace en Ruby, así
  # que basta una consulta: ni el número de unidades ni el de claves cambian la
  # cantidad de consultas, solo el tamaño de los parámetros.
  class DirectiveQuery
    SQL = <<~SQL.freeze
      WITH scoped AS (
        SELECT directive_type,
               unit_uid,
               key,
               value,
               version,
               created_at,
               id,
               (source = 'user' AND key = ANY($4)) AS user_intent
          FROM line_item_directives
         WHERE line_item_id = $1
           AND version <= $2
           AND (directive_type = 'header' OR unit_uid = ANY($3))
           %<key_filter>s
      )
      SELECT DISTINCT ON (directive_type, unit_uid, key, user_intent)
             directive_type,
             unit_uid,
             key,
             value,
             user_intent
        FROM scoped
       ORDER BY directive_type, unit_uid, key, user_intent,
                version DESC, created_at DESC, id DESC
    SQL

    # El filtro de claves se añade al WHERE, no al resultado: cuando el llamador
    # pasa `keys:` la base de datos lee y ordena menos filas.
    KEY_FILTER = "AND key = ANY($5)"

    def initialize(line_item_id:, unit_uids:, version:, keys:)
      @line_item_id = line_item_id
      @unit_uids    = unit_uids
      @version      = version
      @keys         = keys
    end

    # @return [Array<Hash>] filas candidatas, ya reducidas por la base de datos.
    def rows
      connection.exec_query(sql, "EffectiveConfigResolver", binds).to_a
    end

    def sql
      format(SQL, key_filter: @keys ? KEY_FILTER : "")
    end

    private

    def binds
      list = [
        bind("line_item_id", @line_item_id, ActiveRecord::Type::BigInteger.new),
        bind("version",      @version,      ActiveRecord::Type::Integer.new),
        bind("unit_uids",    @unit_uids,    text_array),
        bind("user_intent_keys", KeyRules::USER_INTENT_KEYS, text_array)
      ]
      list << bind("keys", @keys, text_array) if @keys
      list
    end

    def bind(name, value, type)
      ActiveRecord::Relation::QueryAttribute.new(name, value, type)
    end

    def text_array
      @text_array ||= ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array
                      .new(ActiveRecord::Type::Text.new)
    end

    def connection
      LineItemDirective.connection
    end
  end
end
