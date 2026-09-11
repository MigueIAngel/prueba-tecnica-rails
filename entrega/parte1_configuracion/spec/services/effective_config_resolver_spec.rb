# frozen_string_literal: true

require "rails_helper"

RSpec.describe EffectiveConfigResolver do
  # --- Regla 1 — corte por versión ----------------------------------------

  describe "regla 1 · corte por versión" do
    it "ignora las directivas de versión posterior a la objetivo" do
      unit("unit-a", key: "coating", value: "hasta-v3", version: 3)
      unit("unit-a", key: "coating", value: "de-v7", version: 7)

      expect(resolve(unit_uids: %w[unit-a], version: 3))
        .to eq("unit-a" => { "coating" => "hasta-v3" })
    end

    it "incluye la versión objetivo (el corte es <= V, no < V)" do
      unit("unit-a", key: "coating", value: "justo-en-v5", version: 5)

      expect(resolve(unit_uids: %w[unit-a], version: 5))
        .to eq("unit-a" => { "coating" => "justo-en-v5" })
    end
  end

  # --- Regla 2 — gana la más reciente --------------------------------------

  describe "regla 2 · gana la más reciente" do
    it "prefiere la versión más alta aunque se haya escrito antes" do
      antigua = DirectiveFactory::BASE_TIME
      unit("unit-a", key: "hardware", value: "v9", version: 9, created_at: antigua)
      unit("unit-a", key: "hardware", value: "v2", version: 2, created_at: antigua + 1.hour)

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "hardware" => "v9" })
    end

    it "con empate de versión gana la escrita más tarde" do
      unit("unit-a", key: "hardware", value: "primera", version: 4)
      unit("unit-a", key: "hardware", value: "segunda", version: 4)

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "hardware" => "segunda" })
    end

    it "con empate de versión y de created_at desempata por id" do
      instante = DirectiveFactory::BASE_TIME
      unit("unit-a", key: "hardware", value: "id-menor", version: 4, created_at: instante)
      unit("unit-a", key: "hardware", value: "id-mayor", version: 4, created_at: instante)

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "hardware" => "id-mayor" })
    end
  end

  # --- Regla 3 — prioridad de la elección del usuario ----------------------

  describe "regla 3 · prioridad de la elección del usuario" do
    it "una directiva user gana a una resolution de versión posterior" do
      unit("unit-a", key: "glass_type", value: "laminated", version: 2, source: "user")
      unit("unit-a", key: "glass_type", value: "tempered",  version: 8, source: "resolution")

      expect(resolve(unit_uids: %w[unit-a], version: 8))
        .to eq("unit-a" => { "glass_type" => "laminated" })
    end

    it "entre varias directivas user gana la más reciente" do
      unit("unit-a", key: "color_id", value: "azul",  version: 2, source: "user")
      unit("unit-a", key: "color_id", value: "verde", version: 6, source: "user")
      unit("unit-a", key: "color_id", value: "gris",  version: 7, source: "resolution")

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "color_id" => "verde" })
    end

    it "no da prioridad a user cuando la clave no es de intención" do
      unit("unit-a", key: "hardware", value: "elegido", version: 2, source: "user")
      unit("unit-a", key: "hardware", value: "calculado", version: 8, source: "resolution")

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "hardware" => "calculado" })
    end

    it "respeta el corte por versión: una user posterior a V no cuenta" do
      unit("unit-a", key: "finish_id", value: "mate",   version: 2, source: "resolution")
      unit("unit-a", key: "finish_id", value: "brillo", version: 9, source: "user")

      expect(resolve(unit_uids: %w[unit-a], version: 5))
        .to eq("unit-a" => { "finish_id" => "mate" })
    end

    it "la prioridad user es por unidad, no contagia a las demás" do
      unit("unit-a", key: "low_e", value: "elegido-a", version: 1, source: "user")
      unit("unit-b", key: "low_e", value: "calculado-b", version: 4, source: "resolution")

      expect(resolve(unit_uids: %w[unit-a unit-b], version: 9)).to eq(
        "unit-a" => { "low_e" => "elegido-a" },
        "unit-b" => { "low_e" => "calculado-b" }
      )
    end
  end

  # --- Regla 4 — herencia desde la cabecera --------------------------------

  describe "regla 4 · herencia desde la cabecera" do
    it "la unidad sin valor propio hereda el de la cabecera" do
      header(key: "coating", value: "solar", version: 1)
      unit("unit-a", key: "hardware", value: "manilla", version: 1)

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "hardware" => "manilla", "coating" => "solar" })
    end

    it "el valor propio de la unidad tapa el de la cabecera" do
      header(key: "coating", value: "solar", version: 5)
      unit("unit-a", key: "coating", value: "ninguno", version: 1)

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "coating" => "ninguno" })
    end

    it "la cabecera se resuelve con las reglas 1 a 3 antes de heredarse" do
      header(key: "glass_type", value: "laminated", version: 2, source: "user")
      header(key: "glass_type", value: "tempered",  version: 8, source: "resolution")
      header(key: "glass_type", value: "futuro",    version: 12, source: "resolution")

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "glass_type" => "laminated" })
    end

    it "todas las unidades pedidas heredan la misma cabecera" do
      header(key: "coating", value: "solar", version: 1)
      unit("unit-b", key: "coating", value: "propio", version: 1)

      expect(resolve(unit_uids: %w[unit-a unit-b unit-c], version: 9)).to eq(
        "unit-a" => { "coating" => "solar" },
        "unit-b" => { "coating" => "propio" },
        "unit-c" => { "coating" => "solar" }
      )
    end
  end

  # --- Regla 5 — excepción dimensional -------------------------------------

  describe "regla 5 · excepción dimensional" do
    it "una resolution posterior gana a una user en una clave dimensional" do
      unit("unit-a", key: "width", value: "1200", version: 2, source: "user")
      unit("unit-a", key: "width", value: "1350", version: 6, source: "resolution")

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "width" => "1350" })
    end

    it "aplica a las cuatro claves dimensionales" do
      EffectiveConfig::KeyRules::DIMENSIONAL_KEYS.each do |key|
        unit("unit-a", key: key, value: "elegido", version: 2, source: "user")
        unit("unit-a", key: key, value: "calculado", version: 6, source: "resolution")
      end

      expect(resolve(unit_uids: %w[unit-a], version: 9)).to eq(
        "unit-a" => EffectiveConfig::KeyRules::DIMENSIONAL_KEYS.index_with { "calculado" }
      )
    end

    # Supuesto S1 de NOTAS.md: «se resuelven únicamente por las reglas 1 y 2»
    # se lee en sentido literal, así que tampoco heredan de la cabecera.
    it "no hereda de la cabecera una clave dimensional" do
      header(key: "width", value: "9999", version: 1)
      header(key: "coating", value: "solar", version: 1)

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "coating" => "solar" })
    end

    it "tampoco la hereda cuando se pide explícitamente en keys:" do
      header(key: "height", value: "9999", version: 1)

      expect(resolve(unit_uids: %w[unit-a], version: 9, keys: %w[height]))
        .to eq("unit-a" => {})
    end
  end

  # --- Contrato de la firma -------------------------------------------------

  describe "contrato de la firma" do
    it "devuelve una entrada por cada unidad pedida, aunque no tenga directivas" do
      header(key: "coating", value: "solar", version: 1)

      expect(resolve(unit_uids: %w[unit-a], version: 9, keys: %w[hardware]))
        .to eq("unit-a" => {})
    end

    it "devuelve hash vacío para una unidad que no existe en el historial" do
      unit("unit-a", key: "coating", value: "solar", version: 1)

      expect(resolve(unit_uids: %w[unit-z], version: 9)).to eq("unit-z" => {})
    end

    it "no mezcla directivas de otro renglón" do
      unit("unit-a", key: "coating", value: "mío", version: 1)
      directive(line_item_id: 999, unit_uid: "unit-a", key: "coating",
                value: "ajeno", version: 8)

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "coating" => "mío" })
    end

    it "distingue un valor NULL de la ausencia de directiva: el NULL tapa la cabecera" do
      header(key: "coating", value: "solar", version: 1)
      unit("unit-a", key: "coating", value: nil, version: 4)

      expect(resolve(unit_uids: %w[unit-a], version: 9))
        .to eq("unit-a" => { "coating" => nil })
    end

    it "no consulta la base de datos cuando no hay unidades o no hay claves" do
      unit("unit-a", key: "coating", value: "solar", version: 1)

      sin_unidades = count_queries { described_class.call(line_item_id: DirectiveFactory::LINE_ITEM_ID, unit_uids: [], version: 9) }
      sin_claves   = count_queries { resolve(unit_uids: %w[unit-a], version: 9, keys: []) }

      expect(sin_unidades).to be_empty
      expect(sin_claves).to be_empty
      expect(resolve(unit_uids: %w[unit-a], version: 9, keys: [])).to eq("unit-a" => {})
    end
  end

  # --- Requisitos no funcionales -------------------------------------------

  describe "requisito · keys: reduce el trabajo, no filtra al final" do
    it "lleva el filtro de claves al WHERE de la consulta" do
      resolver = described_class.new(
        line_item_id: DirectiveFactory::LINE_ITEM_ID,
        unit_uids: %w[unit-a], version: 9, keys: %w[coating]
      )

      expect(resolver.query.sql).to include(EffectiveConfig::DirectiveQuery::KEY_FILTER)
    end

    it "sin keys: no hay filtro de claves" do
      resolver = described_class.new(
        line_item_id: DirectiveFactory::LINE_ITEM_ID,
        unit_uids: %w[unit-a], version: 9
      )

      expect(resolver.query.sql).not_to include(EffectiveConfig::DirectiveQuery::KEY_FILTER)
    end

    it "la base de datos devuelve solo las filas de las claves pedidas" do
      unit("unit-a", key: "coating", value: "solar", version: 1)
      unit("unit-a", key: "hardware", value: "manilla", version: 1)
      unit("unit-a", key: "glass_type", value: "laminated", version: 1)

      filas = described_class.new(
        line_item_id: DirectiveFactory::LINE_ITEM_ID,
        unit_uids: %w[unit-a], version: 9, keys: %w[coating]
      ).query.rows

      expect(filas.map { |fila| fila["key"] }).to eq(%w[coating])
    end
  end

  describe "requisito · número de consultas independiente de unidades y claves" do
    it "usa una sola consulta con 3 unidades y con 30" do
      30.times do |indice|
        unit("unit-#{indice}", key: "coating", value: "solar-#{indice}", version: 1)
        unit("unit-#{indice}", key: "glass_type", value: "laminated", version: 1, source: "user")
      end
      header(key: "hardware", value: "manilla", version: 1)

      con_3  = count_queries { resolve(unit_uids: (0...3).map { "unit-#{_1}" }, version: 9) }
      con_30 = count_queries { resolve(unit_uids: (0...30).map { "unit-#{_1}" }, version: 9) }

      expect(con_3.size).to eq(1)
      expect(con_30.size).to eq(1)
      expect(con_30.size).to be <= 3
    end

    it "el número de consultas tampoco depende de cuántas claves se pidan" do
      %w[coating hardware glass_type width height].each do |key|
        unit("unit-a", key: key, value: "x", version: 1)
      end

      una_clave    = count_queries { resolve(unit_uids: %w[unit-a], version: 9, keys: %w[coating]) }
      cinco_claves = count_queries { resolve(unit_uids: %w[unit-a], version: 9, keys: %w[coating hardware glass_type width height]) }
      todas        = count_queries { resolve(unit_uids: %w[unit-a], version: 9) }

      expect([una_clave.size, cinco_claves.size, todas.size]).to eq([1, 1, 1])
    end
  end

  # --- Caso completo --------------------------------------------------------

  describe "caso completo" do
    it "combina las cinco reglas en un mismo renglón" do
      header(key: "glass_type", value: "laminated", version: 1, source: "user")
      header(key: "glass_type", value: "tempered",  version: 6, source: "resolution")
      header(key: "coating",    value: "solar",     version: 2, source: "default")
      header(key: "width",      value: "9999",      version: 2, source: "default")
      header(key: "hardware",   value: "futuro",    version: 12, source: "resolution")

      unit("unit-a", key: "width", value: "1200", version: 3, source: "user")
      unit("unit-a", key: "width", value: "1250", version: 5, source: "resolution")
      unit("unit-a", key: "coating", value: "ninguno", version: 4, source: "user")

      unit("unit-b", key: "color_id", value: "azul", version: 2, source: "user")
      unit("unit-b", key: "color_id", value: "gris", version: 7, source: "resolution")

      expect(resolve(unit_uids: %w[unit-a unit-b unit-c], version: 9)).to eq(
        # width propio y por reglas 1-2 (la user de v3 no manda: es dimensional);
        # coating propio; glass_type heredado con la user de la cabecera.
        "unit-a" => { "width" => "1250", "coating" => "ninguno", "glass_type" => "laminated" },
        # color_id propio por regla 3; el resto heredado, sin `width`.
        "unit-b" => { "color_id" => "azul", "glass_type" => "laminated", "coating" => "solar" },
        # solo herencia; `hardware` queda fuera por el corte de versión.
        "unit-c" => { "glass_type" => "laminated", "coating" => "solar" }
      )
    end
  end
end
