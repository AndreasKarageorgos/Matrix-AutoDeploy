#!/bin/bash
# Automates the deployment of a Matrix Synapse server via Docker Compose

# --- Configuration Variables ---

# Ask for server name, default to "matrix.local" if left blank
read -p "Enter server name [matrix.local]: " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-matrix.local}

# Ask for password silently, giving them the option to leave it blank
read -s -p "Enter PostgreSQL password [leave blank to auto-generate]: " POSTGRES_PASSWORD
echo # Prints a newline since -s suppresses the 'Enter' keystroke

# Check if the variable is empty (-z)
if [ -z "$POSTGRES_PASSWORD" ]; then
    # Generate the random password
    POSTGRES_PASSWORD=$(openssl rand -hex 32)
    
    # Print it so the user can copy/save it
    echo "No password provided. Auto-generated password: $POSTGRES_PASSWORD"
fi

echo "Starting Matrix Synapse deployment automation..."

# Step 1: Create the Matrix Project Directory
echo "Creating project directories..."
mkdir -p ~/matrix/synapse/data
cd ~/matrix

# Step 2: Define the Docker Compose Stack
echo "Generating docker-compose.yml..."
cat <<EOF > docker-compose.yml
services:
  postgres:
    image: postgres:16-alpine
    container_name: matrix-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
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
EOF

# Step 3: Generate the Synapse Configuration
echo "Generating Synapse configuration for ${SERVER_NAME}..."
sudo docker run -i --rm \
  -v ~/matrix/synapse/data:/data \
  -e SYNAPSE_SERVER_NAME=${SERVER_NAME} \
  -e SYNAPSE_REPORT_STATS=no \
  matrixdotorg/synapse:latest generate

# Step 4: Point Synapse at PostgreSQL
echo "Configuring PostgreSQL connection in homeserver.yaml..."
# Remove the default SQLite database configuration block and append PostgreSQL config
sed -i '/^database:/,/^$/d' ~/matrix/synapse/data/homeserver.yaml
cat <<EOF >> ~/matrix/synapse/data/homeserver.yaml

database:
  name: psycopg2
  args:
    user: synapse
    password: ${POSTGRES_PASSWORD}
    database: synapse
    host: postgres
    cp_min: 10
    cp_max: 50
EOF

# Step 5: Disable Open Registration
echo "Disabling open registration and setting shared secret..."
SHARED_SECRET=$(openssl rand -hex 32)
# Append registration settings to the top/end of the yaml file
echo "enable_registration: false" >> ~/matrix/synapse/data/homeserver.yaml
echo "registration_shared_secret: \"${SHARED_SECRET}\"" >> ~/matrix/synapse/data/homeserver.yaml

# Step 6: Start the Stack and Fix the Database Locale
echo "Starting the Docker stack..."
sudo docker compose up -d

echo "Waiting for containers to initialize..."
sleep 60

echo "Stopping Synapse to fix database locale..."
sudo docker compose stop synapse

echo "Recreating PostgreSQL database with correct locale..."
sudo docker exec -i matrix-postgres psql -U synapse postgres <<EOF
DROP DATABASE synapse;
CREATE DATABASE synapse
  WITH OWNER synapse
  TEMPLATE template0
  LC_COLLATE 'C'
  LC_CTYPE 'C';
\q
EOF

echo "Starting Synapse back up..."
sudo docker compose start synapse

# Step 7: Restart Synapse
echo "Restarting Synapse to apply final database changes..."
sudo docker compose restart synapse

echo "========================================================="
echo "Deployment Complete!"
echo ""
echo "To create your first administrator account (Step 9), run the following command manually:"
echo "docker exec -it matrix-synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml"
echo "========================================================="