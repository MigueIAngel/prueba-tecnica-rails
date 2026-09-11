# frozen_string_literal: true

class CutPlanner
  # Una barra abierta, con las piezas que salen de ella y lo que sobra.
  #
  # Hay dos números de «sobra» y conviene no confundirlos:
  #
  #   remainder — el trozo de longitud útil que queda sin cortar al final. Es
  #               el retal físico que vuelve al almacén o a la chatarra.
  #   waste     — todo el material de la barra que no sale como pieza:
  #               despuntes + kerf + remainder. Es el que alimenta
  #               `CutPlan#waste_ratio`.
  class PlannedBar
    attr_reader :stock_id, :length, :usable_length, :pieces, :remainder

    def initialize(stock_id:, length:, usable_length:, pieces:, remainder:)
      @stock_id      = stock_id
      @length        = length
      @usable_length = usable_length
      @pieces        = pieces.freeze
      @remainder     = remainder
      freeze
    end

    def pieces_count
      pieces.sum(&:quantity)
    end

    def pieces_length
      pieces.sum(&:total_length)
    end

    def waste
      length - pieces_length
    end

    def waste_ratio
      waste / length
    end

    def to_h
      {
        stock_id: stock_id,
        length: length,
        usable_length: usable_length,
        pieces: pieces.map(&:to_h),
        remainder: remainder
      }
    end
  end
end
