# frozen_string_literal: true

# Una fila del historial de configuración de un renglón de cotización.
#
# El modelo existe para escribir y para dar nombre a la tabla; la lectura
# efectiva la hace EffectiveConfigResolver con SQL crudo parametrizado, porque
# la resolución necesita un DISTINCT ON que Active Record no expresa bien.
class LineItemDirective < ApplicationRecord
  HEADER = "header"
  UNIT   = "unit"
  DIRECTIVE_TYPES = [HEADER, UNIT].freeze

  # Orden de menor a mayor autoridad; hoy solo `user` recibe trato especial
  # (regla 3), pero la lista documenta el vocabulario del campo.
  SOURCES = %w[default preserved resolution user].freeze

  validates :line_item_id, presence: true
  validates :directive_type, inclusion: { in: DIRECTIVE_TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :key, presence: true
  validates :version, numericality: { only_integer: true }
  validates :unit_uid, presence: true, if: -> { directive_type == UNIT }
  validates :unit_uid, absence: true, if: -> { directive_type == HEADER }

  scope :header, -> { where(directive_type: HEADER) }
  scope :unit,   -> { where(directive_type: UNIT) }
end
