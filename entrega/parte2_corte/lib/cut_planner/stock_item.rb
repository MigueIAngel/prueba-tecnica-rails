# frozen_string_literal: true

class CutPlanner
  # Un tipo de barra del inventario. No es un objeto de valor: `remaining`
  # cambia según se van abriendo barras, y es la única garantía de que nunca se
  # usan más barras de un tipo que las disponibles.
  class StockItem
    attr_reader :id, :length, :usable_length, :available, :remaining

    def self.build_all(stock, config)
      Array(stock).map { |item| build(item, config) }
    end

    def self.build(item, config)
      attributes = item.to_h.transform_keys(&:to_sym)
      new(
        id: attributes.fetch(:id),
        length: attributes.fetch(:length),
        available: attributes.fetch(:available),
        config: config
      )
    end

    def initialize(id:, length:, available:, config:)
      @id     = id
      @length = Float(length)
      raise ArgumentError, "la longitud de #{id.inspect} debe ser positiva: #{length.inspect}" unless @length.positive?

      @available = Integer(available)
      raise ArgumentError, "la disponibilidad de #{id.inspect} no puede ser negativa" if @available.negative?

      @remaining     = @available
      @usable_length = config.usable_length(@length)
    end

    # ¿Queda alguna barra de este tipo, y sirve para algo? Una barra cuyos
    # despuntes se comen toda la longitud no admite ninguna pieza.
    def usable?
      @remaining.positive? && @usable_length.positive?
    end

    def take!
      raise ArgumentError, "no quedan barras de #{id.inspect}" unless @remaining.positive?

      @remaining -= 1
    end

    def used
      @available - @remaining
    end
  end
end
