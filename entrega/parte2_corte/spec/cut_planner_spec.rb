# frozen_string_literal: true

RSpec.describe CutPlanner do
  # --- Reglas físicas del corte --------------------------------------------

  describe "reglas físicas" do
    it "descuenta los dos despuntes de la longitud aprovechable" do
      # 6.000 - 100 - 50 = 5.850 de longitud útil.
      resultado = plan(pieces: [piece(5_850.0, 1)], stock: [bar("A", 6_000.0, 1)],
                       head_trim: 100.0, tail_trim: 50.0)

      expect(resultado.bars.first.usable_length).to eq(5_850.0)
      expect(placed_counts(resultado)).to eq(5_850.0 => 1)
      expect(resultado.bars.first.remainder).to eq(0.0)
    end

    it "no coloca una pieza que solo cabría invadiendo el despunte" do
      resultado = plan(pieces: [piece(5_851.0, 1)], stock: [bar("A", 6_000.0, 1)],
                       head_trim: 100.0, tail_trim: 50.0)

      expect(resultado.bars).to be_empty
      expect(unplaced_counts(resultado)).to eq([5_851.0, :too_long] => 1)
    end

    it "descarta un tipo de barra cuyos despuntes se comen toda la longitud" do
      resultado = plan(pieces: [piece(100.0, 1)],
                       stock: [bar("CORTA", 120.0, 5), bar("LARGA", 1_000.0, 1)],
                       head_trim: 100.0, tail_trim: 50.0)

      expect(resultado.bars_used_by_stock_id).to eq("LARGA" => 1)
    end

    it "cobra kerf también a la última pieza de la barra" do
      # Longitud útil 1.000; tres piezas de 300 más tres cortes de 10 = 930.
      # Una cuarta pieza necesitaría 310 más y no cabe.
      resultado = plan(pieces: [piece(300.0, 4)], stock: [bar("A", 1_000.0, 1)], kerf: 10.0)

      expect(placed_counts(resultado)).to eq(300.0 => 3)
      expect(resultado.bars.first.remainder).to eq(70.0)
    end
  end

  # --- Caso obligatorio: el kerf cambia el resultado ------------------------

  describe "el kerf cambia el resultado" do
    # Longitud útil 5.850 y piezas de 1.170: cinco caben exactas sin sierra,
    # pero con 4 mm por corte harían falta 5.870.
    let(:pieces) { [piece(1_170.0, 5)] }
    let(:stock)  { [bar("A", 6_000.0, 1)] }
    let(:trims)  { { head_trim: 100.0, tail_trim: 50.0 } }

    it "con kerf 0 las cinco piezas salen de una sola barra" do
      resultado = plan(pieces: pieces, stock: stock, kerf: 0.0, **trims)

      expect(placed_counts(resultado)).to eq(1_170.0 => 5)
      expect(resultado.unplaced).to be_empty
    end

    it "con kerf 4 solo caben cuatro y la quinta se queda fuera" do
      resultado = plan(pieces: pieces, stock: stock, kerf: 4.0, **trims)

      expect(placed_counts(resultado)).to eq(1_170.0 => 4)
      expect(unplaced_counts(resultado)).to eq([1_170.0, :out_of_stock] => 1)
    end
  end

  # --- Caso obligatorio: inventario insuficiente ----------------------------

  describe "inventario insuficiente" do
    it "coloca lo que puede y devuelve el resto como :out_of_stock" do
      resultado = plan(pieces: [piece(1_000.0, 10)], stock: [bar("A", 3_000.0, 2)])

      expect(placed_counts(resultado)).to eq(1_000.0 => 6)
      expect(unplaced_counts(resultado)).to eq([1_000.0, :out_of_stock] => 4)
      expect(resultado.bars_used).to eq(2)
    end

    it "nunca abre más barras de un tipo que las disponibles" do
      resultado = plan(pieces: [piece(1_000.0, 100)],
                       stock: [bar("A", 3_000.0, 2), bar("B", 5_000.0, 3)])

      expect(resultado.bars_used_by_stock_id).to eq("B" => 3, "A" => 2)
      expect(resultado.placed_quantity).to eq(21) # 3 x 5 + 2 x 3
      expect(resultado.unplaced_quantity).to eq(79)
    end

    it "devuelve todo como :out_of_stock cuando no hay inventario ninguno" do
      resultado = plan(pieces: [piece(1_000.0, 3)], stock: [])

      expect(resultado.bars).to be_empty
      expect(unplaced_counts(resultado)).to eq([1_000.0, :out_of_stock] => 3)
    end

    it "trata un tipo de barra con cero disponibles como si no estuviera" do
      resultado = plan(pieces: [piece(1_000.0, 2)],
                       stock: [bar("AGOTADA", 6_000.0, 0), bar("B", 2_500.0, 5)])

      expect(resultado.bars_used_by_stock_id).to eq("B" => 1)
    end
  end

  # --- Caso obligatorio: pieza más larga que cualquier barra útil -----------

  describe "pieza más larga que cualquier barra útil" do
    it "la aparta como :too_long y sigue colocando las demás" do
      resultado = plan(pieces: [piece(7_000.0, 2), piece(1_000.0, 3)],
                       stock: [bar("A", 6_000.0, 4)])

      expect(placed_counts(resultado)).to eq(1_000.0 => 3)
      expect(unplaced_counts(resultado)).to eq([7_000.0, :too_long] => 2)
    end

    it "distingue :too_long de :out_of_stock en la misma llamada" do
      resultado = plan(pieces: [piece(7_000.0, 1), piece(2_000.0, 5)],
                       stock: [bar("A", 6_000.0, 1)])

      expect(unplaced_counts(resultado)).to eq(
        [7_000.0, :too_long] => 1,
        [2_000.0, :out_of_stock] => 2
      )
    end

    it "es :out_of_stock, no :too_long, si la barra donde cabría está agotada" do
      # :too_long se mide contra el catálogo, no contra las existencias: la
      # pieza cabe en una LARGA, y que no queden es un problema de inventario.
      resultado = plan(pieces: [piece(5_000.0, 1)],
                       stock: [bar("LARGA", 6_000.0, 0), bar("CORTA", 3_000.0, 9)])

      expect(unplaced_counts(resultado)).to eq([5_000.0, :out_of_stock] => 1)
    end
  end

  # --- Desperdicio ----------------------------------------------------------

  describe "#waste_ratio" do
    it "es el material tirado sobre el consumido, con los números a mano" do
      # Una barra de 1.000 de la que salen 3 piezas de 300: se consumen 1.000 y
      # se producen 900.
      resultado = plan(pieces: [piece(300.0, 3)], stock: [bar("A", 1_000.0, 1)])

      expect(resultado.consumed_length).to eq(1_000.0)
      expect(resultado.produced_length).to eq(900.0)
      expect(resultado.waste_ratio).to eq(0.1)
    end

    it "cuenta despuntes y kerf como desperdicio" do
      # Útil 900; dos piezas de 400 más dos cortes de 10 = 820, sobran 80.
      resultado = plan(pieces: [piece(400.0, 2)], stock: [bar("A", 1_000.0, 1)],
                       kerf: 10.0, head_trim: 60.0, tail_trim: 40.0)

      expect(resultado.bars.first.remainder).to eq(80.0)
      expect(resultado.waste_ratio).to eq(0.2) # (1000 - 800) / 1000
    end

    it "es cero cuando no se abre ninguna barra" do
      expect(plan(pieces: [], stock: [bar("A", 1_000.0, 5)]).waste_ratio).to eq(0.0)
      expect(plan(pieces: [piece(9_000.0, 1)], stock: [bar("A", 1_000.0, 5)]).waste_ratio).to eq(0.0)
    end
  end

  # --- Elección de barra ----------------------------------------------------

  describe "elección del tipo de barra" do
    it "abre la barra que menos material desperdicia, no la más larga" do
      # Para dos piezas de 900 la barra de 2.000 desperdicia 200 (10 %) y la de
      # 6.000 desperdicia 4.200 (70 %).
      resultado = plan(pieces: [piece(900.0, 2)],
                       stock: [bar("LARGA", 6_000.0, 5), bar("JUSTA", 2_000.0, 5)])

      expect(resultado.bars_used_by_stock_id).to eq("JUSTA" => 1)
    end

    it "cambia de tipo de barra cuando quedan pocas piezas" do
      # El ejemplo del enunciado: las primeras barras salen de BAR-A, pero las
      # dos últimas piezas se cortan de una BAR-B, que desperdicia menos.
      resultado = plan(
        pieces: [piece(1_450.0, 12), piece(820.5, 30)],
        stock: [bar("BAR-A", 6_000.0, 8), bar("BAR-B", 4_000.0, 3)],
        kerf: 4.0, head_trim: 100.0, tail_trim: 50.0
      )

      expect(resultado.bars_used_by_stock_id).to eq("BAR-A" => 7, "BAR-B" => 1)
      expect(resultado.unplaced).to be_empty
      expect(resultado.waste_ratio).to be_within(1e-6).of(0.086_630)
    end

    it "resuelve el empate por orden de entrada del inventario" do
      resultado = plan(pieces: [piece(1_000.0, 1)],
                       stock: [bar("PRIMERA", 2_000.0, 1), bar("SEGUNDA", 2_000.0, 1)])

      expect(resultado.bars_used_by_stock_id).to eq("PRIMERA" => 1)
    end
  end

  # --- Determinismo ---------------------------------------------------------

  describe "determinismo" do
    it "dos ejecuciones con la misma entrada producen el mismo plan" do
      argumentos = {
        pieces: [piece(1_450.0, 12), piece(820.5, 30), piece(330.0, 25), piece(1_995.5, 7)],
        stock: [bar("BAR-A", 6_000.0, 8), bar("BAR-B", 4_000.0, 3), bar("BAR-C", 2_500.0, 4)],
        config: { kerf: 4.0, head_trim: 100.0, tail_trim: 50.0 }
      }

      primera  = CutPlanner.new(**argumentos).call
      segunda  = CutPlanner.new(**argumentos).call

      expect(primera.to_h).to eq(segunda.to_h)
    end

    it "agrupa las piezas repetidas de la misma medida" do
      juntas   = plan(pieces: [piece(1_000.0, 4)], stock: [bar("A", 3_000.0, 2)])
      sueltas  = plan(pieces: [piece(1_000.0, 1)] * 4, stock: [bar("A", 3_000.0, 2)])

      expect(sueltas.to_h).to eq(juntas.to_h)
    end
  end

  # --- Entradas de borde ----------------------------------------------------

  describe "entradas de borde" do
    it "sin piezas no abre ninguna barra" do
      resultado = plan(pieces: [], stock: [bar("A", 6_000.0, 5)])

      expect(resultado.bars).to be_empty
      expect(resultado.unplaced).to be_empty
    end

    it "ignora los renglones de cantidad cero" do
      resultado = plan(pieces: [piece(1_000.0, 0), piece(500.0, 2)], stock: [bar("A", 6_000.0, 1)])

      expect(placed_counts(resultado)).to eq(500.0 => 2)
    end

    it "rechaza una longitud no positiva" do
      expect { plan(pieces: [piece(0.0, 1)], stock: [bar("A", 100.0, 1)]) }
        .to raise_error(ArgumentError, /longitud de una pieza/)
    end

    it "rechaza una cantidad negativa" do
      expect { plan(pieces: [piece(10.0, -1)], stock: [bar("A", 100.0, 1)]) }
        .to raise_error(ArgumentError, /cantidad de una pieza/)
    end

    it "rechaza un parámetro físico negativo" do
      expect { plan(pieces: [], stock: [], kerf: -1.0) }
        .to raise_error(ArgumentError, /kerf/)
    end

    it "acepta las claves en texto además de en símbolo" do
      resultado = CutPlanner.new(
        pieces: [{ "length" => 1_000.0, "quantity" => 2 }],
        stock: [{ "id" => "A", "length" => 3_000.0, "available" => 1 }],
        config: { "kerf" => 5.0 }
      ).call

      expect(placed_counts(resultado)).to eq(1_000.0 => 2)
    end
  end

  # --- Rendimiento ----------------------------------------------------------

  describe "rendimiento" do
    it "planifica 5.000 piezas en una fracción de segundo" do
      pieces = [piece(1_450.0, 1_200), piece(1_995.5, 800), piece(820.5, 1_500),
                piece(640.0, 1_000), piece(330.0, 500)]
      stock  = [bar("BAR-A", 6_000.0, 900), bar("BAR-B", 4_000.0, 400)]

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      resultado = plan(pieces: pieces, stock: stock, kerf: 4.0, head_trim: 100.0, tail_trim: 50.0)
      transcurrido = Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio

      expect(resultado.placed_quantity + resultado.unplaced_quantity).to eq(5_000)
      # Umbral holgado a propósito: lo que se comprueba es que no hay
      # explosión combinatoria, no la velocidad de esta máquina.
      expect(transcurrido).to be < 2.0
    end

    it "aguanta el peor caso: 5.000 piezas y ninguna medida repetida" do
      # El coste va con el número de medidas distintas, no con el de piezas,
      # así que este es el caso caro: el multiconjunto no comprime nada.
      pieces = (1..5_000).map { |i| piece((200 + (i * 0.37)).round(1), 1) }
      stock  = [bar("BAR-A", 6_000.0, 2_000), bar("BAR-B", 4_000.0, 500)]

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      resultado = plan(pieces: pieces, stock: stock, kerf: 4.0, head_trim: 100.0, tail_trim: 50.0)
      transcurrido = Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio

      expect(resultado.placed_quantity).to eq(5_000)
      expect(transcurrido).to be < 5.0
    end
  end

  # --- Invariantes ----------------------------------------------------------

  describe "invariantes" do
    let(:resultado) do
      plan(
        pieces: [piece(1_450.0, 40), piece(820.5, 60), piece(330.0, 25), piece(9_999.0, 3)],
        stock: [bar("BAR-A", 6_000.0, 6), bar("BAR-B", 4_000.0, 4), bar("BAR-C", 2_500.0, 2)],
        kerf: 4.0, head_trim: 100.0, tail_trim: 50.0
      )
    end

    it "no pierde ni inventa piezas" do
      total = placed_counts(resultado).values.sum + resultado.unplaced_quantity

      expect(total).to eq(40 + 60 + 25 + 3)
    end

    it "nunca supera la longitud útil de ninguna barra" do
      resultado.bars.each do |planned_bar|
        ocupado = planned_bar.pieces.sum { |p| (p.length + 4.0) * p.quantity }

        expect(ocupado).to be <= planned_bar.usable_length + CutPlanner::TOLERANCE
        expect(planned_bar.remainder).to be >= -CutPlanner::TOLERANCE
      end
    end

    it "no deja ninguna barra abierta vacía" do
      expect(resultado.bars).to all(have_attributes(pieces_count: be_positive))
    end
  end
end
