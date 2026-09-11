# frozen_string_literal: true

# Azúcar para que las pruebas se lean como el enunciado, sin FactoryBot.
module PlanHelpers
  # Config por defecto: sin despuntes ni kerf, para que los números de una
  # prueba pequeña se puedan comprobar a mano. Cada prueba pone lo que necesita.
  def plan(pieces:, stock:, **config)
    CutPlanner.new(pieces: pieces, stock: stock, config: config).call
  end

  def piece(length, quantity)
    { length: length, quantity: quantity }
  end

  def bar(id, length, available)
    { id: id, length: length, available: available }
  end

  # Todas las piezas colocadas, sin importar de qué barra salen:
  # { longitud => cantidad }.
  def placed_counts(plan)
    plan.bars.each_with_object(Hash.new(0)) do |planned_bar, counts|
      planned_bar.pieces.each { |p| counts[p.length] += p.quantity }
    end
  end

  # { [longitud, motivo] => cantidad }.
  def unplaced_counts(plan)
    plan.unplaced.to_h { |p| [[p.length, p.reason], p.quantity] }
  end
end

RSpec.configure { |config| config.include PlanHelpers }
