# frozen_string_literal: true

class CutPlanner
  # Las piezas pendientes, como multiconjunto `longitud => cantidad` ordenado
  # de mayor a menor.
  #
  # Las entradas reales tienen muchas repeticiones y pocas longitudes
  # distintas: 5.000 piezas suelen ser media docena de medidas. Trabajar sobre
  # el multiconjunto y no sobre 5.000 elementos sueltos es lo que mantiene el
  # coste ligado al número de medidas distintas y no al de piezas.
  class PiecePool
    Entry = Struct.new(:length, :count)
    private_constant :Entry

    # Piezas que quedan por colocar.
    attr_reader :size

    def initialize(pieces)
      @first = 0
      build_entries(pieces)
    end

    def empty?
      @size.zero?
    end

    # Recorre las longitudes pendientes de mayor a menor. El bloque recibe
    # `(longitud, cantidad)`.
    def each_pending
      skip_exhausted
      @first.upto(@entries.size - 1) do |position|
        entry = @entries[position]
        yield entry.length, entry.count if entry.count.positive?
      end
    end

    def pending
      [].tap { |list| each_pending { |length, count| list << [length, count] } }
    end

    def take(length, count)
      entry = @index.fetch(length)
      raise ArgumentError, "no hay #{count} piezas de #{length}" if count > entry.count

      entry.count -= count
      @size -= count
    end

    # Retira de golpe las piezas que superan un límite de longitud. Como el
    # multiconjunto está ordenado de mayor a menor, son siempre un prefijo: en
    # cuanto una entra, todas las siguientes entran.
    def withdraw_longer_than(limit)
      taken = []
      each_pending do |length, count|
        break unless length > limit + TOLERANCE

        taken << [length, count]
      end
      taken.each { |length, count| take(length, count) }
      taken
    end

    private

    def build_entries(pieces)
      counts = Hash.new(0)
      Array(pieces).each do |piece|
        length, quantity = read(piece)
        counts[length] += quantity
      end

      @entries = counts.sort_by { |length, _| -length }
                       .map { |length, count| Entry.new(length, count) }
      @index   = @entries.to_h { |entry| [entry.length, entry] }
      @size    = @entries.sum(&:count)
    end

    def read(piece)
      attributes = piece.to_h.transform_keys(&:to_sym)
      length     = Float(attributes.fetch(:length))
      quantity   = Integer(attributes.fetch(:quantity))

      raise ArgumentError, "la longitud de una pieza debe ser positiva: #{length}" unless length.positive?
      raise ArgumentError, "la cantidad de una pieza no puede ser negativa: #{quantity}" if quantity.negative?

      [length, quantity]
    end

    # Las longitudes agotadas se quedan al principio del multiconjunto, porque
    # siempre se coloca primero la pieza más larga que quepa. Adelantar el
    # cursor evita repasarlas en cada barra.
    def skip_exhausted
      @first += 1 while @first < @entries.size && @entries[@first].count.zero?
    end
  end
end
