#!/usr/bin/env bash
# fidrouter — one-line partner enable. Bundles cp-adapter beside your gateway so you can
# offer a verifiable, no-log lane. Agent-friendly: fully non-interactive via env vars.
#
#   curl -fsSL https://raw.githubusercontent.com/aoraki-labs/fidrouter-cp-adapter/main/enable.sh | \
#     NEWAPI_BASE=https://your-gateway \
#     ENCLAVE_URL=http://your-enclave:9090 \
#     EXPECTED_MEASUREMENT=sha256:... \
#     bash
#
# If CP_SEED_HEX is unset, a control-plane keypair is generated and its PUBLIC half is
# printed — bake that into your enclave image (config/public.json) and rebuild.
set -euo pipefail
: "${NEWAPI_BASE:?set NEWAPI_BASE}"; : "${ENCLAVE_URL:?set ENCLAVE_URL}"; : "${EXPECTED_MEASUREMENT:?set EXPECTED_MEASUREMENT}"
VERIFY_URL="${VERIFY_URL:-https://app.fidcore.xyz}"
MODELS="${MODELS:-claude-opus-5,claude-sonnet-5,claude-haiku-4-5-20251001}"
PORT="${PORT:-8091}"
DIR="${DIR:-/opt/cp-adapter}"
RAW="https://raw.githubusercontent.com/aoraki-labs/fidrouter-cp-adapter/main/adapter.py"

echo "[fidrouter] installing cp-adapter → $DIR"
command -v python3 >/dev/null || { echo "python3 required"; exit 1; }
python3 -c "import cryptography" 2>/dev/null || python3 -m pip install --quiet cryptography 2>/dev/null || \
  { echo "install python3 'cryptography' first"; exit 1; }
sudo mkdir -p "$DIR"
sudo curl -fsSL "$RAW" -o "$DIR/adapter.py"

if [ -z "${CP_SEED_HEX:-}" ]; then
  read -r CP_SEED_HEX CP_PUB_HEX < <(python3 - <<'PY'
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization as s
k=Ed25519PrivateKey.generate()
seed=k.private_bytes(s.Encoding.Raw,s.PrivateFormat.Raw,s.NoEncryption())
pub=k.public_key().public_bytes(s.Encoding.Raw,s.PublicFormat.Raw)
print(seed.hex(),pub.hex())
PY
)
  echo "[fidrouter] generated a control-plane keypair."
  echo "            >>> bake this cp_pub into your enclave (config/public.json), then rebuild:"
  echo "            cp_pub(hex) = $CP_PUB_HEX"
fi

sudo tee "$DIR/cpadapter.env" >/dev/null <<EOF
CP_SEED_HEX=$CP_SEED_HEX
NEWAPI_BASE=$NEWAPI_BASE
ENCLAVE_URL=$ENCLAVE_URL
EXPECTED_MEASUREMENT=$EXPECTED_MEASUREMENT
VERIFY_URL=$VERIFY_URL
MODELS=$MODELS
PORT=$PORT
EOF
sudo chmod 600 "$DIR/cpadapter.env"

if command -v systemctl >/dev/null; then
  sudo tee /etc/systemd/system/cpadapter.service >/dev/null <<EOF
[Unit]
Description=fidrouter cp-adapter
After=network-online.target
[Service]
EnvironmentFile=$DIR/cpadapter.env
ExecStart=$(command -v python3) $DIR/adapter.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload && sudo systemctl enable --now cpadapter
  sleep 2; curl -fsS "http://127.0.0.1:$PORT/healthz" && echo
else
  echo "[fidrouter] no systemd — run: env \$(cat $DIR/cpadapter.env|xargs) python3 $DIR/adapter.py"
fi

cat <<EOF

[fidrouter] cp-adapter is up on :$PORT (open it to the platform host, or keep it private).
Next: register your endpoint at $VERIFY_URL  (Endpoints → Register),
  base_url=$ENCLAVE_URL  measurement=$EXPECTED_MEASUREMENT  cp_adapter_url=http://<this-host>:$PORT
Then inject your upstream key operator-blind (BYOK tab). Done.
EOF
