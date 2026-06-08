#!/usr/bin/env bash
# ==============================================================================
# HIERANANO - UNIVERSAL AUTO-ADAPTIVE MASTER DEPLOYMENT LAYER (h-gold.sh)
# ==============================================================================
set -e

# ----------------------------------------------------------------------------
# Interactive helper: prompt for a value, defaulting to $3 if empty.
# Honors a non-interactive flag set ($NONINTERACTIVE=1) and the HIERANANO_*
# environment variables so CI / scripted runs work as well.
# ----------------------------------------------------------------------------
DEFAULT_PROMPT_TIMEOUT=60
if [ -z "${NONINTERACTIVE:-}" ]; then
  if [ -t 0 ]; then
    NONINTERACTIVE=0
  else
    NONINTERACTIVE=1
  fi
fi

ask() {
  # ask <varname> <prompt> <default>
  local __var="$1"
  local __prompt="$2"
  local __default="$3"
  # Allow pre-set env var (HIERANANO_<UPPER>) to override defaults
  local __env_key="HIERANANO_$(echo "$__var" | tr '[:lower:]' '[:upper:]')"
  local __env_val="${!__env_key:-}"

  if [ -n "$__env_val" ]; then
    printf -v "$__var" '%s' "$__env_val"
    echo "   ↳ $__prompt = $__env_val (from env $__env_key)"
    return
  fi

  if [ "$NONINTERACTIVE" -eq 1 ]; then
    printf -v "$__var" '%s' "$__default"
    echo "   ↳ $__prompt = $__default (non-interactive default)"
    return
  fi

  local __input
  read -t "$DEFAULT_PROMPT_TIMEOUT" -p "❓ $__prompt [$__default]: " __input || true
  echo
  if [ -z "$__input" ]; then
    printf -v "$__var" '%s' "$__default"
  else
    printf -v "$__var" '%s' "$__input"
  fi
}

echo "======================================================================"
echo "🚀 Starting HieraNano Master Enterprise Deployment"
echo "======================================================================"

# ==============================================================================
# STEP 1: INTERACTIVE PARAMS & PLATFORM CONTEXT LOOKUP
# ==============================================================================
ask HOST "Enter binding interface host" "127.0.0.1"
ask PORT "Enter target listening port" "5000"
ask CONTROL_REPO_DIR "Enter target Puppet control repository tree path" "/etc/puppetlabs/code/environments/production"
ask APP_DIR "Enter target deployment workspace root directory" "/root/.hieranano"
ask DATA_PERSIST_DIR "Enter target persistence storage directory" "/root/.hieranano"

# Force tracking matrices
mkdir -p "$APP_DIR"
mkdir -p "$DATA_PERSIST_DIR"

# Check dependencies
echo "⚙  Verifying critical underlying core software dependencies..."
for cmd in python3 sqlite3 lsof git; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Critical Dependency Missing: Please install '$cmd' using your system package manager first."
        exit 1
    fi
done
echo "✅ Prerequisites present."

# ==============================================================================
# STEP 2: PYTHON ISOLATED ENVIRONMENT LAYERING
# ==============================================================================
echo "⚙  Configuring clean sandboxed Python execution runtime venv..."
if [ ! -d "$APP_DIR/venv" ]; then
    python3 -m venv "$APP_DIR/venv"
fi

echo "⚙  Upgrading delivery tooling inside virtual workspace..."
"$APP_DIR/venv/bin/pip" install --upgrade pip setuptools wheel

echo "⚙  Ensuring Flask, Requests, and production WSGI Gunicorn interfaces exist..."
"$APP_DIR/venv/bin/pip" install flask requests gunicorn

# ==============================================================================
# STEP 3: DATA PERSISTENCE LAYER & MATRIX SCHEMA PROVISIONING
# ==============================================================================
DB_FILE="$DATA_PERSIST_DIR/hieranano.db"
echo "⚙  Initializing and updating local schema structures under $DB_FILE..."

sqlite3 "$DB_FILE" <<SQL_EOF
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
);
SQL_EOF

# Safely stage structural operational environment metrics inside tables
echo "⚙  Seeding tracking state schemas with directory variables..."
sqlite3 "$DB_FILE" <<SQL_EOF
INSERT OR IGNORE INTO settings (key, value) VALUES ('control_repo_dir', '${CONTROL_REPO_DIR}');
INSERT OR IGNORE INTO settings (key, value) VALUES ('ai_endpoint', 'https://api.openai.com/v1/chat/completions');
INSERT OR IGNORE INTO settings (key, value) VALUES ('ai_model', 'gpt-4o-mini');
SQL_EOF

# ==============================================================================
# STEP 4: BACKEND AUTHENTICATION RE-SEED BARRIER
# ==============================================================================
# Check if install tokens exist before processing token seed layers
EXISTING_TOKEN=$(sqlite3 "$DB_FILE" "SELECT value FROM settings WHERE key='plaintext_install_token';" 2>/dev/null || true)

if [ -z "$EXISTING_TOKEN" ]; then
    echo "⚙  No operational tokens found. Generating system authentication metrics..."
    ask INSTALL_SECRET "Enter target AI Token (or temporary setup placeholder string)" "setup_placeholder_token_string"
    
    EYAML_PUB_KEY="/etc/puppetlabs/secure/keys/public_key.pkcs7.pem"
    INITIAL_ENC_TOKEN=""

    if [ -f "$EYAML_PUB_KEY" ] && command -v eyaml &> /dev/null; then
        echo "⚙  Eyaml keys recognized. Encrypting system tokens for transit protection..."
        INITIAL_ENC_TOKEN=$(eyaml encrypt --pkcs7-public-key "$EYAML_PUB_KEY" --stdin <<< "$INSTALL_SECRET")
    fi

    CLEAN_TOKEN=$(echo "$INITIAL_ENC_TOKEN" | tr -d '\n' | tr -d ' ' | tr -d '\r')
    CLEAN_SECRET=$(echo "$INSTALL_SECRET" | tr -d '\n' | tr -d ' ' | tr -d '\r')

    sqlite3 "$DB_FILE" <<SQL_EOF
INSERT OR REPLACE INTO settings (key, value) VALUES ('plaintext_install_token', '${CLEAN_SECRET}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('secure_install_token', '${CLEAN_TOKEN}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('ai_token', '${CLEAN_SECRET}');
SQL_EOF
else
    echo "✅ Authentication credentials already verified in database. Skipping token re-seed."
fi

# ==============================================================================
# STEP 5: HOUSEKEEPING AND STALE PID HOUSE-CLEANING
# ==============================================================================
echo "⚙  Flushing dead network sockets and orphaned upstream microservice workers..."

# Identify and cleanly close port locks
find_pid=$(lsof -t -i:"$PORT" || true)
if [ -n "$find_pid" ]; then 
    echo "⚠️  Port $PORT bound by active PID $find_pid. Disconnecting socket process..."
    kill -9 $find_pid || true
fi

# Terminate unmanaged sub-worker threads running in the background
pkill -f "gunicorn.*app:app" || true

# ==============================================================================
# STEP 6: WSGI WORKER DAEMON STARTUP
# ==============================================================================
echo "⚙  Spawning workspace engine microservice via Gunicorn daemon runtime..."

nohup "$APP_DIR/venv/bin/python" -m gunicorn \
    --workers 1 \
    --bind "$HOST:$PORT" \
    --chdir "$APP_DIR" \
    --timeout 90 \
    app:app > "$APP_DIR/runtime.log" 2>&1 &

echo "----------------------------------------------------------------------"
echo "🎉 DEPLOY SUCCESSFUL"
echo "----------------------------------------------------------------------"
echo "  • Workspace Target Root : $APP_DIR"
echo "  • Internal Binding Port : http://$HOST:$PORT"
echo "  • Log Output Stream     : tail -f $APP_DIR/runtime.log"
echo "======================================================================"
