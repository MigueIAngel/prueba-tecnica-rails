# frozen_string_literal: true

class CutPlanner
  # Piezas que no se pudieron producir, con el motivo. Devolverlas es parte del
  # contrato: el planificador nunca falla por falta de material.
  #
  #   :too_long      — no cabe en ninguna barra del catálogo, ni entera y sola.
  #                    Es un problema de geometría: con más inventario del
  #                    mismo tipo seguiría sin poder cortarse.
  #   :out_of_stock  — cabría, pero se acabaron las barras disponibles.
  class UnplacedPiece
    REASONS = %i[too_long out_of_stock].freeze

    attr_reader :length, :quantity, :reason

    def initialize(length:, quantity:, reason:)
      raise ArgumentError, "motivo desconocido: #{reason.inspect}" unless REASONS.include?(reason)

      @length   = length
      @quantity = quantity
      @reason   = reason
      freeze
    end

    def total_length
      length * quantity
    end

    def to_h
      { length: length, quantity: quantity, reason: reason }
    end

    def ==(other)
      other.is_a?(UnplacedPiece) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end
  end
end
