# frozen_string_literal: true

# Datos de ejemplo para probar el servicio a mano en la consola. Reproducen el
# caso completo de las pruebas: las cinco reglas actuando sobre un renglón.
#
#   bin/rails db:seed
#   bin/rails runner 'pp EffectiveConfigResolver.call(line_item_id: 1, unit_uids: %w[unit-a unit-b unit-c], version: 9)'

LINE_ITEM_ID = 1

LineItemDirective.where(line_item_id: LINE_ITEM_ID).delete_all

base = Time.utc(2026, 1, 1, 12, 0, 0)
escritura = 0

crear = lambda do |attributes|
  escritura += 1
  LineItemDirective.create!(
    line_item_id: LINE_ITEM_ID,
    directive_type: attributes[:unit_uid] ? "unit" : "header",
    created_at: base + escritura,
    **attributes
  )
end

# Cabecera del renglón.
crear.call(key: "glass_type", value: "laminated", source: "user",       version: 1)
crear.call(key: "glass_type", value: "tempered",  source: "resolution", version: 6)
crear.call(key: "coating",    value: "solar",     source: "default",    version: 2)
crear.call(key: "width",      value: "9999",      source: "default",    version: 2)
crear.call(key: "hardware",   value: "futuro",    source: "resolution", version: 12)

# unit-a: valores propios.
crear.call(unit_uid: "unit-a", key: "width",   value: "1200",    source: "user",       version: 3)
crear.call(unit_uid: "unit-a", key: "width",   value: "1250",    source: "resolution", version: 5)
crear.call(unit_uid: "unit-a", key: "coating", value: "ninguno", source: "user",       version: 4)

# unit-b: una elección de usuario que sobrevive a un cálculo posterior.
crear.call(unit_uid: "unit-b", key: "color_id", value: "azul", source: "user",       version: 2)
crear.call(unit_uid: "unit-b", key: "color_id", value: "gris", source: "resolution", version: 7)

# unit-c no tiene directivas propias: todo lo hereda de la cabecera.

puts "#{LineItemDirective.where(line_item_id: LINE_ITEM_ID).count} directivas creadas."
