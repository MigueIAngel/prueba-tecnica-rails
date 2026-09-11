# frozen_string_literal: true

module EffectiveConfig
  # Las dos listas de claves con tratamiento especial, y los predicados que las
  # consultan. Viven juntas porque las reglas 3 y 5 solo se entienden en pareja.
  module KeyRules
    # Regla 3 — la elección explícita del usuario gana sobre cualquier cálculo
    # posterior del motor de resolución.
    USER_INTENT_KEYS = %w[glass_type color_id finish_id coating low_e].freeze

    # Regla 5 — claves dimensionales: se resuelven únicamente por las reglas 1 y 2.
    DIMENSIONAL_KEYS = %w[width height dlo_width dlo_height].freeze

    module_function

    def user_intent?(key)
      USER_INTENT_KEYS.include?(key)
    end

    # Una clave dimensional no aplica la regla 3 (nunca podría: ninguna está en
    # USER_INTENT_KEYS) y tampoco la regla 4. Ver NOTAS.md, supuesto S1.
    def dimensional?(key)
      DIMENSIONAL_KEYS.include?(key)
    end

    # ¿Puede esta clave heredar el valor efectivo de la cabecera? (regla 4)
    def inheritable?(key)
      !dimensional?(key)
    end
  end
end
