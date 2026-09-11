# frozen_string_literal: true

class CutPlanner
  # Un grupo de piezas de la misma medida dentro de una barra. Se agrupan por
  # longitud en vez de repetirse una a una porque una barra puede llevar
  # docenas de piezas iguales y el plan se lee mejor así.
  class PlacedPiece
    attr_reader :length, :quantity

    def initialize(length:, quantity:)
      @length   = length
      @quantity = quantity
      freeze
    end

    def total_length
      length * quantity
    end

    def to_h
      { length: length, quantity: quantity }
    end

    def ==(other)
      other.is_a?(PlacedPiece) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end
  end
end
