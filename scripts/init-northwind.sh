#!/usr/bin/env bash
#
# Inicializa la base de datos Northwind en una instancia de SQL Server ya accesible.
# Crea la base (si no existe) y carga "instnwnd.sql".
#
# Pensado para CI (GitHub Actions: contenedor de servicio en localhost) y para uso local.
# No requiere sqlcmd en el host: ejecuta sqlcmd dentro de un contenedor efímero de
# la imagen de SQL Server 2022 usando la red del host.
#
# Variables de entorno:
#   SERVER        Nombre/host del servidor SQL Server (por defecto: localhost)
#   SA_PASSWORD   Contraseña de "sa"                  (por defecto: Your_password123)
#   DB_NAME       Nombre de la base de datos          (por defecto: Northwind)
#   IMAGE         Imagen de SQL Server                (por defecto: mcr.microsoft.com/mssql/server:2022-latest)
#   SCRIPT_PATH   Ruta al script de datos             (por defecto: instnwnd.sql)
#
set -euo pipefail

SERVER="${SERVER:-localhost}"
SA_PASSWORD="${SA_PASSWORD:-Your_password123}"
DB_NAME="${DB_NAME:-Northwind}"
IMAGE="${IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"
SCRIPT_PATH="${SCRIPT_PATH:-instnwnd.sql}"

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
SCRIPT_FILE="$(basename "${SCRIPT_PATH}")"

# Ejecuta sqlcmd dentro de un contenedor efímero, en la red del host.
sqlcmd() {
  docker run --rm --network host \
    --entrypoint /bin/bash "${IMAGE}" -c \
      'TOOLS=/opt/mssql-tools18/bin/sqlcmd; [ -x "$TOOLS" ] || TOOLS=/opt/mssql-tools/bin/sqlcmd; exec "$TOOLS" "$@"' \
      -- "$@"
}

echo "Esperando a SQL Server en ${SERVER}..."
for attempt in $(seq 1 30); do
  if sqlcmd -C -S "${SERVER}" -U sa -P "${SA_PASSWORD}" -Q "SELECT 1" >/dev/null 2>&1; then
    echo "SQL Server disponible."
    break
  fi
  if [ "${attempt}" -eq 30 ]; then
    echo "ERROR: SQL Server no respondió tras 30 intentos." >&2
    exit 1
  fi
  echo "  intento ${attempt}/30..."
  sleep 5
done

echo "Creando la base de datos '${DB_NAME}' (si no existe)..."
sqlcmd -C -S "${SERVER}" -U sa -P "${SA_PASSWORD}" \
  -Q "IF DB_ID('${DB_NAME}') IS NULL CREATE DATABASE [${DB_NAME}];"

echo "Cargando ${SCRIPT_PATH} en '${DB_NAME}'..."
docker run --rm --network host \
  -v "${SCRIPT_DIR}/${SCRIPT_FILE}:/scripts/instnwnd.sql:ro" \
  --entrypoint /bin/bash "${IMAGE}" -c \
    'TOOLS=/opt/mssql-tools18/bin/sqlcmd; [ -x "$TOOLS" ] || TOOLS=/opt/mssql-tools/bin/sqlcmd; exec "$TOOLS" "$@"' \
    -- -C -S "${SERVER}" -U sa -P "${SA_PASSWORD}" -d "${DB_NAME}" -i /scripts/instnwnd.sql -f 65001

echo "Base de datos '${DB_NAME}' lista."
