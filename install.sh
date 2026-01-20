#!/bin/bash

# set -e: exit on error
# set -u: error on unset variables
# set -o pipefail: catch errors in piped commands
set -euo pipefail

# --- Configuration ---
REPO_RAW_URL="https://raw.githubusercontent.com/StabRise/pdf-redaction-api/main"
ENV_FILE=".env"
EXAMPLE_FILE=".env.example"
COMPOSE_FILE="docker-compose.yml"
LICENSE_VAR="PDF_REDACTION_API_LICENSE"
PORTAL_URL="https://pdf-redaction.com/licenses"

# --- Helper Functions ---
info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[0;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

# 1. Dependency Check
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install Docker first."
fi

# 2. Download Configuration Files
# Helper function to download files
download_file() {
    local url=$1
    local dest=$2
    if command -v curl &> /dev/null; then
        curl -sSL "$url" -o "$dest"
    elif command -v wget &> /dev/null; then
        wget -q "$url" -O "$dest"
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

# 2. Download Configuration Files
info "Downloading configuration from GitHub..."
download_file "$REPO_RAW_URL/$COMPOSE_FILE" "$COMPOSE_FILE"
download_file "$REPO_RAW_URL/$EXAMPLE_FILE" "$EXAMPLE_FILE"

# 3. Ensure .env exists
if [ ! -f "$ENV_FILE" ]; then
    info "Creating $ENV_FILE from $EXAMPLE_FILE."
    cp "$EXAMPLE_FILE" "$ENV_FILE"
fi

# 4. License Key Logic
# Check shell environment first, then the .env file
CURRENT_LICENSE=${!LICENSE_VAR:-$(grep -E "^${LICENSE_VAR}=" "$ENV_FILE" | cut -d'=' -f2- || true)}

if [ -n "$CURRENT_LICENSE" ]; then
    info "License found in environment. Starting services..."
else
    info "No license key found. Redirecting to license portal..."

    # Browser logic
    if command -v open > /dev/null; then open "$PORTAL_URL"
    elif command -v xdg-open > /dev/null; then xdg-open "$PORTAL_URL"
    else warn "Please visit: $PORTAL_URL"; fi

    # Secure prompt
    read -r -s -p "Enter your License Key: " USER_KEY
    echo

    if [ -z "$USER_KEY" ]; then
        error "A license key is required to run the PDF Redaction API."
    fi

    # Write to .env using | delimiter to handle potential / in keys
    if grep -qE "^${LICENSE_VAR}=" "$ENV_FILE"; then
        sed -i.bak -E "s|^${LICENSE_VAR}=.*|${LICENSE_VAR}=${USER_KEY}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
    else
        echo "${LICENSE_VAR}=${USER_KEY}" >> "$ENV_FILE"
    fi
    info "License key saved to $ENV_FILE."
fi

# 5. Execute Docker Compose
info "Pulling images and starting API..."
docker compose pull
docker compose up -d

# 6. Health Check
info "Waiting for API to stabilize..."
sleep 5
if curl -s -f http://localhost:8080/health > /dev/null; then
    info "✅ Success! API is responding at http://localhost:8080"
else
    warn "API started but health check failed. Check logs with 'docker compose logs'."
fi