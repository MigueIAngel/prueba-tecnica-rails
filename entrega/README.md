# Entrega — Prueba técnica Ruby on Rails

Cómo levantar el entorno y ejecutar el código y las pruebas de cada parte.

## Índice

- [Parte 1 — Resolución de configuración efectiva](parte1_configuracion/) · Rails 7 + PostgreSQL
- [Parte 2 — Planificador de corte de material](parte2_corte/) · Ruby puro
- [Parte 3 — Función de reserva de inventario](parte3_postgres/) · PL/pgSQL
- [Parte 4 — Video explicativo](parte4_video/)
- [Parte 5 — Tres preguntas cortas](parte5_preguntas.md)

## Entorno

Versiones con las que se desarrolló y verificó la entrega:

| Componente | Versión |
| --- | --- |
| Ruby | 3.3.6 (fijada en `.ruby-version`) |
| Rails | 7.2.3 |
| PostgreSQL | 16.15 |
| Pruebas | RSpec |

### Instalación desde cero (macOS)

```bash
# Ruby 3.3.6 con rbenv
brew install rbenv ruby-build
rbenv install 3.3.6

# Rails 7.x
gem install rails -v '~> 7.2'

# PostgreSQL 16
brew install postgresql@16
brew services start postgresql@16
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
```

En Linux basta con Ruby >= 3.1 y PostgreSQL >= 13 instalados por el gestor de
paquetes de la distribución; no se usa ninguna característica específica de macOS.

### Verificación rápida

```bash
ruby -v          # ruby 3.3.6
rails -v         # Rails 7.2.3
psql --version   # psql (PostgreSQL) 16.x
pg_isready       # accepting connections
```

## Ejecución por parte

> Pendiente: se completa a medida que se implementa cada parte.

## Supuestos generales

Cada parte documenta sus propios supuestos en su `NOTAS.md`.
