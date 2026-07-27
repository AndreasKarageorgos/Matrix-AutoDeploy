#!/bin/bash
#
#
# Automates the self-hosted Matrix (Synapse) deployment described in the
# "Deploying a Self Hosted Matrix Server" guide.
#
# This script assumes Docker and Docker Compose are ALREADY installed
# (the apt update/upgrade/docker.io install steps are intentionally
# excluded, per requirements) and that the current user is already able
# to run docker commands.
#
# It covers:
#   - Project directory creation
#   - docker-compose.yml generation
#   - Synapse config generation
#   - PostgreSQL wiring
#   - Disabling open registration
#   - Starting the stack and fixing the Postgres locale (C collation)
#   - Restarting Synapse
#   - Creating the first administrator account
#
set -euo pipefail

PROJECT_DIR="${HOME}/matrix"

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------

if [[ "${EUID}" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    echo "Please do NOT run this script as root or with sudo." >&2
    echo "Docker containers write files owned by your host user; running as root" >&2
    echo "(or root via sudo) puts everything under /root and can cause permission" >&2
    echo "problems later. Make sure your user is in the 'docker' group instead:" >&2
    echo "    sudo usermod -aG docker \$USER   (then log out and back in)" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Cannot talk to Docker as the current user (${USER})." >&2
    echo "Make sure you are in the 'docker' group and have logged out/in since" >&2
    echo "being added to it (usermod -aG docker \$USER requires a fresh login)." >&2
    exit 1
fi

# The official Synapse image runs internally as this uid/gid by default,
# which means any files it creates on a bind mount end up owned by that
# numeric uid on the host - NOT your user - causing permission errors when
# this script (running as your normal user) tries to edit homeserver.yaml.
# Pinning UID/GID to the current host user avoids that entirely.
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# ---------------------------------------------------------------------------
# 1. Gather input
# ---------------------------------------------------------------------------

echo "=== Matrix Synapse Deployment ==="
echo

read -rp "Enter the Matrix server domain (e.g. chat.mycompany.com) [default: matrix.local]: " SERVER_NAME
SERVER_NAME="${SERVER_NAME:-matrix.local}"

if [[ "${SERVER_NAME}" == "matrix.local" ]]; then
    echo "No domain entered - defaulting to matrix.local (placeholder, change for production)."
fi

read -rsp "Enter a PostgreSQL password for the 'synapse' user (leave empty to auto-generate): " DB_PASSWORD
echo
if [[ -z "${DB_PASSWORD}" ]]; then
    DB_PASSWORD="$(openssl rand -hex 16)"
    echo "No password entered - generated one automatically."
fi

echo
echo "Domain:            ${SERVER_NAME}"
echo "Postgres password:  ${DB_PASSWORD}"
echo
echo "Keep the password above somewhere safe (e.g. a password manager)."
echo

# ---------------------------------------------------------------------------
# Step 2. Create the Matrix project directory
# ---------------------------------------------------------------------------

echo "[Step 2] Creating project directory at ${PROJECT_DIR} ..."
mkdir -p "${PROJECT_DIR}/synapse"
cd "${PROJECT_DIR}"

# ---------------------------------------------------------------------------
# Step 3. Define the Docker Compose stack
# ---------------------------------------------------------------------------

echo "[Step 3] Writing docker-compose.yml ..."
cat > "${PROJECT_DIR}/docker-compose.yml" <<EOF
services:
  postgres:
    image: postgres:16-alpine
    container_name: matrix-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: synapse
      LANG: C.UTF-8
      LC_ALL: C.UTF-8
    volumes:
      - ./postgres:/var/lib/postgresql/data
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: matrix-synapse
    restart: unless-stopped
    depends_on:
      - postgres
    ports:
      - "8008:8008"
    volumes:
      - ./synapse/data:/data
    environment:
      SYNAPSE_CONFIG_DIR: /data
      SYNAPSE_CONFIG_PATH: /data/homeserver.yaml
      UID: ${HOST_UID}
      GID: ${HOST_GID}
EOF

# ---------------------------------------------------------------------------
# Step 4. Generate the Synapse configuration
# ---------------------------------------------------------------------------

HOMESERVER_YAML="${PROJECT_DIR}/synapse/data/homeserver.yaml"

if [[ -f "${HOMESERVER_YAML}" ]]; then
    echo "[Step 4] Existing homeserver.yaml found at ${HOMESERVER_YAML} - skipping generation."
    echo "         (Delete ${PROJECT_DIR}/synapse/data and rerun if you want a clean config.)"
else
    echo "[Step 4] Generating Synapse configuration for domain '${SERVER_NAME}' ..."
    docker run -it --rm \
        -v "${PROJECT_DIR}/synapse/data:/data" \
        -e SYNAPSE_SERVER_NAME="${SERVER_NAME}" \
        -e SYNAPSE_REPORT_STATS=no \
        -e UID="${HOST_UID}" \
        -e GID="${HOST_GID}" \
        matrixdotorg/synapse:latest generate
fi

if [[ ! -f "${HOMESERVER_YAML}" ]]; then
    echo "ERROR: homeserver.yaml was not generated as expected at ${HOMESERVER_YAML}" >&2
    exit 1
fi

if [[ ! -w "${HOMESERVER_YAML}" ]]; then
    echo "ERROR: ${HOMESERVER_YAML} is not writable by $(whoami)." >&2
    echo "It's likely owned by a different uid from a previous run. Fix with:" >&2
    echo "    sudo chown -R \$(id -u):\$(id -g) ${PROJECT_DIR}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 5. Point Synapse at PostgreSQL
# ---------------------------------------------------------------------------

echo "[Step 5] Configuring Synapse to use PostgreSQL ..."
python3 - "$HOMESERVER_YAML" "$DB_PASSWORD" <<'PYEOF'
import re
import sys

path, db_password = sys.argv[1], sys.argv[2]

with open(path, "r") as f:
    content = f.read()

new_database_block = f"""database:
  name: psycopg2
  args:
    user: synapse
    password: {db_password}
    database: synapse
    host: postgres
    cp_min: 10
    cp_max: 50
"""

# Replace the existing "database:" block (from "database:" up to, but not
# including, the next top-level key) with the new one.
pattern = re.compile(r"^database:\n(?:[ \t].*\n?)*", re.MULTILINE)

if pattern.search(content):
    content = pattern.sub(new_database_block, content, count=1)
else:
    content += "\n" + new_database_block

with open(path, "w") as f:
    f.write(content)
PYEOF

# ---------------------------------------------------------------------------
# Step 6. Disable open registration
# ---------------------------------------------------------------------------

echo "[Step 6] Disabling open registration ..."
REGISTRATION_SECRET="$(openssl rand -hex 32)"

# Remove any pre-existing enable_registration / registration_shared_secret
# lines, then insert fresh ones near the top of the file.
sed -i '/^enable_registration:/d; /^registration_shared_secret:/d' "${HOMESERVER_YAML}"

TMP_FILE="$(mktemp)"
{
    echo "enable_registration: false"
    echo "registration_shared_secret: \"${REGISTRATION_SECRET}\""
    cat "${HOMESERVER_YAML}"
} > "${TMP_FILE}"
mv "${TMP_FILE}" "${HOMESERVER_YAML}"

# ---------------------------------------------------------------------------
# Step 7. Start the stack and fix the database locale
# ---------------------------------------------------------------------------

echo "[Step 7] Starting the stack ..."
cd "${PROJECT_DIR}"
docker compose up -d

echo "Waiting for containers to finish starting ..."
sleep 60

echo "Stopping Synapse to safely recreate the database ..."
docker compose stop synapse

echo "Recreating the database with the correct C locale ..."
docker exec -i matrix-postgres psql -U synapse postgres <<'SQL'
DROP DATABASE synapse;
CREATE DATABASE synapse
  WITH OWNER synapse
  TEMPLATE template0
  LC_COLLATE 'C'
  LC_CTYPE 'C';
SQL

echo "Bringing Synapse back up ..."
docker compose start synapse

# ---------------------------------------------------------------------------
# Step 8. Restart Synapse
# ---------------------------------------------------------------------------

echo "[Step 8] Restarting Synapse to reload configuration ..."
docker compose restart synapse

echo "Waiting for Synapse to come back up ..."
sleep 15

# ---------------------------------------------------------------------------
# Step 9. Create the first administrator account
# ---------------------------------------------------------------------------

echo "[Step 9] Create the first administrator account."
echo "You will be prompted for a username and password for the admin account."
docker exec -it matrix-synapse \
    register_new_matrix_user \
    http://localhost:8008 \
    -c /data/homeserver.yaml

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo
echo "=== Deployment complete ==="
echo "Server name:        ${SERVER_NAME}"
echo "Project directory:  ${PROJECT_DIR}"
echo "Postgres password:  ${DB_PASSWORD}"
echo
echo "Production reminders:"
echo "  - Put a reverse proxy (Nginx/Caddy) in front of Synapse for TLS."
echo "  - Open port 8448 and configure well-known delegation if you need federation."
echo "  - Back up ${PROJECT_DIR}/postgres and ${PROJECT_DIR}/synapse regularly."
echo "  - Point clients such as Element at: ${SERVER_NAME}"