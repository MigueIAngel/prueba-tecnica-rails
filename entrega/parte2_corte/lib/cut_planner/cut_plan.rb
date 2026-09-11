# frozen_string_literal: true

class CutPlanner
  # El resultado: qué barras se abren, qué sale de cada una, qué se queda sin
  # producir y cuánto material se tira.
  class CutPlan
    attr_reader :bars, :unplaced

    def initialize(bars:, unplaced:)
      @bars     = bars.freeze
      @unplaced = unplaced.freeze
      freeze
    end

    # Material que sale del almacén: la longitud **entera** de cada barra
    # abierta. Una barra abierta está consumida aunque sobre medio metro.
    def consumed_length
      bars.sum(&:length)
    end

    # Material que sale como pieza aprovechable.
    def produced_length
      bars.sum(&:pieces_length)
    end

    # Desperdicio / material consumido. Incluye despuntes, kerf y retales,
    # porque todos ellos son barra que se gastó y no se vendió. Sin barras
    # abiertas no hay nada consumido y el desperdicio es cero.
    def waste_ratio
      return 0.0 if consumed_length.zero?

      (consumed_length - produced_length) / consumed_length
    end

    def bars_used
      bars.size
    end

    def placed_quantity
      bars.sum(&:pieces_count)
    end

    def unplaced_quantity
      unplaced.sum(&:quantity)
    end

    # Barras abiertas de cada tipo, para comprobar de un vistazo que no se
    # excedió el inventario.
    def bars_used_by_stock_id
      bars.each_with_object(Hash.new(0)) { |bar, counts| counts[bar.stock_id] += 1 }
    end

    def to_h
      {
        bars: bars.map(&:to_h),
        unplaced: unplaced.map(&:to_h),
        waste_ratio: waste_ratio
      }
    end
  end
end
