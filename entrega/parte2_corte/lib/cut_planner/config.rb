# frozen_string_literal: true

class CutPlanner
  # Los tres parámetros físicos del corte, y las medidas que se derivan de
  # ellos. Todo está en milímetros.
  #
  # Aquí vive la decisión más importante del modelo: **el kerf se cobra por
  # cada pieza colocada, incluida la última**. Cargarlo dentro de la pieza
  # (`footprint`) convierte el problema en un empaquetado clásico: una barra
  # admite un conjunto de piezas si la suma de sus `footprint` cabe en la
  # longitud útil. Ver NOTAS.md, supuesto S1.
  class Config
    attr_reader :kerf, :head_trim, :tail_trim

    # Acepta claves en símbolo o en texto; cualquier clave desconocida es un
    # error de programación y se avisa como tal.
    def self.build(config)
      new(**config.to_h.transform_keys(&:to_sym))
    end

    def initialize(kerf: 0.0, head_trim: 0.0, tail_trim: 0.0)
      @kerf      = non_negative(kerf, :kerf)
      @head_trim = non_negative(head_trim, :head_trim)
      @tail_trim = non_negative(tail_trim, :tail_trim)
    end

    # Material que se pierde en los dos despuntes de cada barra.
    def trim
      head_trim + tail_trim
    end

    # Tramo de barra donde se puede cortar, una vez quitados los despuntes.
    def usable_length(bar_length)
      [bar_length - trim, 0.0].max
    end

    # Lo que le cuesta a la barra una pieza: su longitud más el corte que la
    # separa de la siguiente.
    def footprint(length)
      length + kerf
    end

    def to_h
      { kerf: kerf, head_trim: head_trim, tail_trim: tail_trim }
    end

    private

    def non_negative(value, name)
      number = Float(value)
      return number unless number.negative?

      raise ArgumentError, "#{name} no puede ser negativo: #{value.inspect}"
    end
  end
end
