# frozen_string_literal: true

require_relative "cut_planner/config"
require_relative "cut_planner/stock_item"
require_relative "cut_planner/piece_pool"
require_relative "cut_planner/bar_fill"
require_relative "cut_planner/placed_piece"
require_relative "cut_planner/planned_bar"
require_relative "cut_planner/unplaced_piece"
require_relative "cut_planner/cut_plan"

# Reparte una lista de piezas entre las barras disponibles en almacén.
#
#   plan = CutPlanner.new(
#     pieces: [{ length: 1_450.0, quantity: 12 }, { length: 820.5, quantity: 30 }],
#     stock:  [{ id: "BAR-A", length: 6_000.0, available: 8 },
#              { id: "BAR-B", length: 4_000.0, available: 3 }],
#     config: { kerf: 4.0, head_trim: 100.0, tail_trim: 50.0 }
#   ).call
#
#   plan.bars        # barras usadas, con sus piezas y el sobrante
#   plan.unplaced    # lo que no se pudo producir, con el motivo
#   plan.waste_ratio # desperdicio / material consumido
#
# El problema es el de corte unidimensional (bin packing con tamaños de
# contenedor distintos y limitados), que es NP-difícil. Aquí se resuelve con
# una heurística voraz en dos niveles:
#
#   1. Dentro de una barra, FFD: se coloca siempre la pieza más larga que
#      quepa (CutPlanner::BarFill).
#   2. Entre barras, mejor ajuste: antes de abrir ninguna se simula el llenado
#      de cada tipo disponible y se abre la que menos material desperdicia.
#
# Ninguna parte es exponencial: el coste es
# O(barras abiertas x tipos de barra x longitudes distintas).
class CutPlanner
  # Las longitudes llegan en flotantes, así que las comparaciones de «cabe» se
  # hacen con holgura. 1e-6 mm es una millonésima de milímetro: no existe en
  # una planta, pero es de sobra para absorber el error binario de sumar unos
  # cuantos miles de milímetros.
  TOLERANCE = 1e-6

  # @param pieces [Array<Hash>] {length:, quantity:}
  # @param stock  [Array<Hash>] {id:, length:, available:}
  # @param config [Hash] {kerf:, head_trim:, tail_trim:}, todos opcionales
  def initialize(pieces:, stock:, config: {})
    @config = Config.build(config)
    @stock  = StockItem.build_all(stock, @config)
    @pieces = pieces
  end

  # @return [CutPlanner::CutPlan]
  def call
    pool     = PiecePool.new(@pieces)
    unplaced = withdraw_too_long(pool)
    bars     = []

    until pool.empty?
      fill = best_fill(pool)
      # Ni una barra disponible admite ya ninguna de las piezas que quedan.
      break if fill.nil?

      bars << commit(fill, pool)
    end

    CutPlan.new(bars: bars, unplaced: unplaced + out_of_stock(pool))
  end

  private

  # Las piezas que no caben enteras en la barra más larga del catálogo no son
  # un problema de inventario, sino de geometría: se apartan antes de empezar y
  # no vuelven a mirarse. Se mide contra el catálogo completo, aunque de ese
  # tipo no quede ninguna barra disponible; ver NOTAS.md, supuesto S3.
  def withdraw_too_long(pool)
    return [] if @stock.empty?

    limit = @stock.map(&:usable_length).max - @config.kerf
    pool.withdraw_longer_than(limit).map do |length, quantity|
      UnplacedPiece.new(length: length, quantity: quantity, reason: :too_long)
    end
  end

  # Simula una barra de cada tipo disponible y devuelve la mejor. El empate se
  # resuelve por orden de entrada del inventario —la comparación es estricta—,
  # que es lo que hace el plan reproducible.
  def best_fill(pool)
    best = nil
    @stock.each do |item|
      next unless item.usable?

      fill = BarFill.simulate(stock_item: item, pool: pool, config: @config)
      next if fill.empty?
      next if best && fill.waste_ratio >= best.waste_ratio

      best = fill
    end
    best
  end

  # Confirma la simulación: descuenta las piezas del multiconjunto, gasta una
  # barra del inventario y produce el renglón del plan.
  def commit(fill, pool)
    item = fill.stock_item
    fill.placements.each { |length, count| pool.take(length, count) }
    item.take!

    PlannedBar.new(
      stock_id: item.id,
      length: item.length,
      usable_length: item.usable_length,
      pieces: fill.placements.map { |length, count| PlacedPiece.new(length: length, quantity: count) },
      remainder: fill.remainder
    )
  end

  def out_of_stock(pool)
    pool.pending.map do |length, quantity|
      UnplacedPiece.new(length: length, quantity: quantity, reason: :out_of_stock)
    end
  end
end
