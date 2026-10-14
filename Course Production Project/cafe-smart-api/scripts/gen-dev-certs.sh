#!/usr/bin/env bash
# Generate a local self-signed cert for development TLS (HTTP + WebSocket).
# Production should use Let's Encrypt (or your CA) fullchain + privkey instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT_DIR="${ROOT}/certs"
mkdir -p "${CERT_DIR}"

openssl req -x509 -newkey rsa:2048 \
  -keyout "${CERT_DIR}/privkey.pem" \
  -out "${CERT_DIR}/fullchain.pem" \
  -days 825 \
  -nodes \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

chmod 600 "${CERT_DIR}/privkey.pem"
chmod 644 "${CERT_DIR}/fullchain.pem"

echo "Wrote:"
echo "  ${CERT_DIR}/fullchain.pem"
echo "  ${CERT_DIR}/privkey.pem"
echo ""
echo "Add to .env (development TLS optional; production required):"
echo "  API_LOCAL_FULL_CHAIN=certs/fullchain.pem"
echo "  API_LOCAL_PRIV_KEY=certs/privkey.pem"
echo ""
echo "Then run with: swift run cafe-smart-api serve --env development"
echo "Or production:  swift run cafe-smart-api serve --env production"
