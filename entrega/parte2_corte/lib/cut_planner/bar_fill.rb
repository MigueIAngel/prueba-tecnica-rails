# frozen_string_literal: true

class CutPlanner
  # Simula el llenado voraz de **una** barra: recorre las longitudes pendientes
  # de mayor a menor y mete de cada una todas las que quepan.
  #
  # Es la pieza que usa el planificador para decidir: antes de abrir nada,
  # simula la barra de cada tipo disponible y abre la que menos material
  # desperdicia. La simulación no toca el inventario ni el multiconjunto; eso
  # lo hace el planificador al confirmar (`CutPlanner#commit`).
  class BarFill
    attr_reader :stock_item, :placements, :remainder

    def self.simulate(stock_item:, pool:, config:)
      new(stock_item: stock_item, pool: pool, config: config)
    end

    def initialize(stock_item:, pool:, config:)
      @stock_item = stock_item
      @placements = []
      @remainder  = stock_item.usable_length

      pool.each_pending do |length, available|
        footprint = config.footprint(length)
        next unless footprint <= @remainder + TOLERANCE

        # Cuántas caben de esta medida: una división, no un bucle. La
        # tolerancia evita que un flotante como 5850.0 / 1170.0 se quede en
        # 4,999… y pierda una pieza que físicamente sí entra.
        count = [((@remainder + TOLERANCE) / footprint).floor, available].min
        next unless count.positive?

        @placements << [length, count]
        @remainder -= count * footprint
      end
    end

    def empty?
      @placements.empty?
    end

    # Longitud útil producida por esta barra: solo las piezas, sin despuntes
    # ni kerf.
    def pieces_length
      @pieces_length ||= @placements.sum { |length, count| length * count }
    end

    def pieces_count
      @pieces_count ||= @placements.sum { |_, count| count }
    end

    # La función de puntuación del planificador: qué fracción de la barra
    # entera se tira si se abre esta. Se mide sobre la longitud **total** y no
    # sobre la útil porque lo que consume el almacén es la barra completa,
    # despuntes incluidos. Cambiar de criterio (por ejemplo, «gasta primero los
    # retales cortos») es cambiar este método. Ver NOTAS.md.
    def waste_ratio
      (stock_item.length - pieces_length) / stock_item.length
    end
  end
end
