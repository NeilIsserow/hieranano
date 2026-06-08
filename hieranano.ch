cat: hiernanano/: Is a directory
root@localai:~# cd hiernanano/
root@localai:~/hiernanano# cat hieranano.sh 
#!/usr/bin/env bash
# ==============================================================================
# HIERANANO - UNIVERSAL AUTO-ADAPTIVE MASTER DEPLOYMENT LAYER (h-gold.sh)
# ==============================================================================
set -e

# ----------------------------------------------------------------------------
# Interactive helper: prompt for a value, defaulting to $2 if empty.
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

  local __reply
  if [ -n "$__default" ]; then
    read -r -t "$DEFAULT_PROMPT_TIMEOUT" -p "   $__prompt [$__default]: " __reply || true
    if [ -z "$__reply" ]; then __reply="$__default"; fi
  else
    read -r -t "$DEFAULT_PROMPT_TIMEOUT" -p "   $__prompt: " __reply || true
  fi
  printf -v "$__var" '%s' "$__reply"
}

INSTALL_SECRET="$1"

if [ -z "$INSTALL_SECRET" ]; then
  echo "❌ CRITICAL: You must pass a secure secret key to initialize authentication."
  echo "👉 Usage: ./h.sh 'your_secure_passphrase'"
  exit 1
fi

# 📍 Standard Production Defaults (used unless overridden interactively)
DEFAULT_KEY_DIR="/etc/puppetlabs/puppet/keys"
DEFAULT_EYAML_PUB_KEY="${DEFAULT_KEY_DIR}/public_key.pkcs7.pem"
DEFAULT_EYAML_PRIV_KEY="${DEFAULT_KEY_DIR}/private_key.pkcs7.pem"
DEFAULT_CONTROL_REPO_DIR="/var/www/production"
DEFAULT_AI_ENDPOINT="https://api.openai.com/v1/chat/completions"
DEFAULT_AI_MODEL="gpt-4o-mini"
DEFAULT_AI_TOKEN=""
DEFAULT_AI_PROMPT="You are a Puppet / Hiera architecture assistant. The user supplies hiera class/parameter NAMES (no values) and a Puppet file. For each key: state its likely purpose, where in the puppet file it would be looked up, suggest companions/renames, and flag redundancy. Output as a compact markdown list. No preamble. No code blocks unless needed."

# ----------------------------------------------------------------------------
# INTERACTIVE CONFIGURATION PROMPTS
# Press Enter to accept the default shown in [brackets]. Set NONINTERACTIVE=1
# or HIERANANO_<UPPER_VAR> env vars to skip prompts (for CI / scripting).
# ----------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  HIERANANO INTERACTIVE INSTALL CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Press Enter to accept each default in [brackets]."
echo "  You can re-run with NONINTERACTIVE=1 or HIERANANO_* env vars to skip."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "📁  Control Repository (where your Hiera/Puppet files live):"
ask CONTROL_REPO_DIR "    Control repository path" "$DEFAULT_CONTROL_REPO_DIR"

echo ""
echo "🔐  eyaml PKCS7 Key Pair (used to encrypt/decrypt Hiera secrets):"
ask EYAML_PUB_KEY  "    eyaml public key (.pem)"  "$DEFAULT_EYAML_PUB_KEY"
ask EYAML_PRIV_KEY "    eyaml private key (.pem)" "$DEFAULT_EYAML_PRIV_KEY"

echo ""
echo "🤖  OpenAI-compatible AI backend (used by '🤖 Consult AI'):"
ask AI_ENDPOINT "    AI base URL (chat completions)"  "$DEFAULT_AI_ENDPOINT"
ask AI_MODEL    "    AI model name"                   "$DEFAULT_AI_MODEL"
ask AI_TOKEN    "    AI bearer token (leave blank if none)" "$DEFAULT_AI_TOKEN"
ask AI_PROMPT   "    AI system prompt"                "$DEFAULT_AI_PROMPT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Configuration summary:"
echo "    control_repo_dir : $CONTROL_REPO_DIR"
echo "    eyaml_public_key : $EYAML_PUB_KEY"
echo "    eyaml_private_key: $EYAML_PRIV_KEY"
echo "    ai_endpoint      : $AI_ENDPOINT"
echo "    ai_model         : $AI_MODEL"
echo "    ai_token         : $([ -n "$AI_TOKEN" ] && echo "*** set ($(printf '%s' "$AI_TOKEN" | wc -c) chars) ***" || echo "(empty)")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 👤 Dynamic Environment & Home Directory Discovery
RUNNING_USER=$(whoami)
RUNNING_UID=$(id -u)

if [ "$RUNNING_UID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
  REAL_USER="$SUDO_USER"
  REAL_HOME=$(eval echo "~$SUDO_USER")
else
  REAL_USER="$RUNNING_USER"
  REAL_HOME="$HOME"
fi

APP_DIR="${REAL_HOME}/.hieranano"
DATA_PERSIST_DIR="${APP_DIR}/data_store"
PORT=5525
HOST="0.0.0.0"

echo "🚀 Bootstrapping Hieranano Workspace Canvas for user: ${REAL_USER}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/templates"
mkdir -p "$DATA_PERSIST_DIR"

# ==============================================================================
# 🛡️ STEP 1: RESILIENT CRYPTO PATH & PERMISSION RESOLUTION
# ==============================================================================
if [ -f "/opt/puppetlabs/puppet/bin/eyaml" ]; then
  FINAL_EYAML="/opt/puppetlabs/puppet/bin/eyaml"
elif command -v eyaml >/dev/null 2>&1; then
  FINAL_EYAML=$(command -v eyaml)
else
  echo "❌ CRITICAL: The 'eyaml' binary could not be found automatically."
  exit 1
fi

NEEDS_SUDO=0
if [ -f "$EYAML_PUB_KEY" ] && [ -f "$EYAML_PRIV_KEY" ]; then
  if [ ! -r "$EYAML_PUB_KEY" ] || [ ! -r "$EYAML_PRIV_KEY" ]; then
    NEEDS_SUDO=1
  fi
fi

if [ "$NEEDS_SUDO" -eq 1 ] && [ "$RUNNING_UID" -ne 0 ]; then
  echo "🔐 Key read access restricted. Requesting JIT elevation permissions..."
  sudo -v
fi

# ==============================================================================
# STEP 2: ISOLATED DEPENDENCY WORKSPACE PROVISIONING
# ==============================================================================
echo "📦 Building isolated Python Virtual Environment..."
python3 -m venv "$APP_DIR/venv"
source "$APP_DIR/venv/bin/activate"
pip install --upgrade pip --quiet
pip install Flask ruamel.yaml gitpython gunicorn requests --quiet

# ==============================================================================
# STEP 3: WEB APPLICATION RUNTIME ARCHITECTURE (app.py)
# ==============================================================================
echo "⚙️  Assembling Backend Intelligence Engine Core..."
cat << 'EOF' > "$APP_DIR/app.py"
import os
import io
import json
import sqlite3
import subprocess
from flask import Flask, render_template, request, redirect, url_for, flash, session, abort, Response, jsonify
from ruamel.yaml import YAML

app = Flask(__name__)
app.secret_key = os.urandom(32)

# Custom Jinja filter: URL-encode a path component for safe use in ?active=...
import urllib.parse as _urllib_parse
@app.template_filter('urlenc')
def _urlenc(s):
    return _urllib_parse.quote(s, safe='')

DB_PATH = os.path.expanduser("~/.hieranano/data_store/hieranano.db")

# ----------------------------------------------------------------------------
# AI PROMPT CACHE: built once at import time. The system prompt and
# instruction text are static for the life of the worker, so we avoid
# re-reading the SQLite DB and re-concatenating strings on every request.
# The cache is invalidated at install time (gunicorn re-execs the script).
# ----------------------------------------------------------------------------
_BASE_SYSTEM_PROMPT = (
    "You are a Puppet / Hiera architecture assistant. "
    "The user supplies hiera class/parameter NAMES (no values) and a Puppet file. "
    "For each key: state its likely purpose, where in the puppet file it would be "
    "looked up, suggest companions/renames, and flag redundancy. "
    "Output as a compact markdown list. No preamble. No code blocks unless needed."
)

def _build_system_prompt():
    user_prompt = get_setting("ai_prompt", "").strip()
    # If the user configured a custom prompt, use it; otherwise use the
    # terse base. We do NOT concatenate the two -- that would just inflate
    # tokens with redundant instructions.
    return user_prompt if user_prompt else _BASE_SYSTEM_PROMPT

# Response cap removed: we stream with no max_tokens cap so the model can
# return as much as it wants. Cost is bounded by the user closing the tray.
MAX_PUPPET_FILE_BYTES = 50_000  # 50KB hard cap on puppet file sent to AI

def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")
        conn.execute("CREATE TABLE IF NOT EXISTS file_visibility (filepath TEXT PRIMARY KEY, is_hidden INTEGER DEFAULT 0)")
        conn.commit()

init_db()

def get_setting(key, default=""):
    try:
        with sqlite3.connect(DB_PATH) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT value FROM settings WHERE key = ?", (key,))
            row = cursor.fetchone()
            return row[0] if row else default
    except Exception:
        return default

def set_settings(data_dict):
    with sqlite3.connect(DB_PATH) as conn:
        for k, v in data_dict.items():
            conn.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (k, v))
        conn.commit()

def run_eyaml(action, input_data, pub_key=None, priv_key=None):
    cmd = ["/opt/puppetlabs/puppet/bin/eyaml", action, "--stdin"]
    
    if pub_key: cmd.extend(["--pkcs7-public-key", pub_key])
    if priv_key: cmd.extend(["--pkcs7-private-key", priv_key])
    
    # FIX: Safely inherit and append to the existing OS environment layout
    custom_env = os.environ.copy()
    custom_env["PATH"] = "/opt/puppetlabs/puppet/bin:/usr/bin:/bin:" + custom_env.get("PATH", "")
    custom_env["RUBYLIB"] = "/opt/puppetlabs/puppet/lib/ruby/vendor_ruby"
    
    try:
        res = subprocess.run(cmd, input=input_data, capture_output=True, text=True, check=True, env=custom_env)
        return res.stdout
    except subprocess.CalledProcessError as e:
        print(f"DEBUG: Eyaml failed. Stderr: {e.stderr}")
        return None

@app.before_request
def enforce_token_authentication():
    if request.path.startswith('/static/') or request.path == '/api/ai-consult' or request.path.startswith('/api/eyaml/'):
        return

    provided_token = request.args.get('token') or session.get('access_token')
    if provided_token:
        provided_token = provided_token.strip()
    else:
        return abort(403, "Access Denied: Append ?token=YOUR_TOKEN to your URL path.")
        
    plaintext_master = get_setting("plaintext_install_token", "").strip()
    encrypted_passkey = get_setting("secure_install_token", "").strip()

    if plaintext_master and provided_token == plaintext_master:
        session['access_token'] = provided_token
        return

    if encrypted_passkey and provided_token == encrypted_passkey:
        session['access_token'] = provided_token
        return

    pub_key = get_setting("eyaml_public_key")
    priv_key = get_setting("eyaml_private_key")
    decrypted_master = run_eyaml("decrypt", encrypted_passkey, pub_key=pub_key, priv_key=priv_key)
    
    if decrypted_master and provided_token == decrypted_master.strip():
        session['access_token'] = provided_token
        return

    return abort(403, "Invalid security token credential provided.")

def generate_tree_node(dir_path, root_repo_path, mode="all"):
    tree = []
    if not dir_path or not os.path.exists(dir_path):
        return tree
    try:
        for entry in os.scandir(dir_path):
            if entry.name.startswith('.'): continue
            rel_path = os.path.relpath(entry.path, root_repo_path)
            if entry.is_dir():
                sub_children = generate_tree_node(entry.path, root_repo_path, mode)
                if mode == "yaml" and not sub_children:
                    continue
                tree.append({
                    "name": entry.name, "type": "directory", "path": rel_path,
                    "children": sub_children
                })
            else:
                is_yaml = entry.name.endswith(('.yaml', '.yml', '.eyaml'))
                if mode == "yaml" and not is_yaml:
                    continue
                tree.append({"name": entry.name, "type": "file", "path": rel_path})
    except Exception: 
        pass
    tree.sort(key=lambda x: (x['type'] != 'directory', x['name'].lower()))
    return tree

@app.context_processor
def inject_global_settings():
    return {
        "repo_path": get_setting("control_repo_dir", ""),
        "ai_endpoint": get_setting("ai_endpoint", ""),
        "ai_prompt": get_setting("ai_prompt", "This is Puppet Enterprise code. Hiera architecture query context input details follow below:")
    }

@app.route('/')
def index():
    repo_path = get_setting("control_repo_dir", "")
    hiera_tree = generate_tree_node(repo_path, repo_path, mode="yaml") if repo_path else []
    full_tree = generate_tree_node(repo_path, repo_path, mode="all") if repo_path else []

    # Single-editor model: one active file at a time.
    active_file = request.args.get('active', '').strip()
    requested_view = request.args.get('view', '').strip().lower()

    file_content, file_type, key_value_pairs, yaml_valid = "", "none", [], False

    if active_file and repo_path:
        fp = os.path.normpath(os.path.join(repo_path, active_file))
        # Path safety: must remain inside the repo root.
        if os.path.commonpath([fp, os.path.normpath(repo_path)]) == os.path.normpath(repo_path) and os.path.isfile(fp):
            with open(fp, 'r') as f:
                file_content = f.read()
            lower = active_file.lower()
            is_yaml_ext = lower.endswith(('.yaml', '.yml'))
            if is_yaml_ext:
                file_type = "yaml"
                try:
                    yaml = YAML()
                    data = yaml.load(file_content) or {}
                    yaml_valid = True
                    if isinstance(data, dict):
                        for k, v in data.items():
                            val_str = json.dumps(v) if isinstance(v, (dict, list)) else str(v)
                            is_enc = "ENC[PKCS7" in str(v) or val_str.startswith("ENC[PKCS7")
                            key_value_pairs.append({
                                "key": k,
                                "value_raw": val_str,
                                "is_encrypted": is_enc
                            })
                except Exception:
                    yaml_valid = False
            else:
                file_type = "raw"

    # Decide which view to render. Visual only makes sense for a valid YAML.
    can_visual = (file_type == "yaml" and yaml_valid)
    if not can_visual:
        view_mode = "raw"
    else:
        if requested_view in ("visual", "raw"):
            view_mode = requested_view
        else:
            view_mode = "visual"

    return render_template(
        'index.html',
        hiera_tree=hiera_tree,
        full_tree=full_tree,
        active_file=active_file,
        file_content=file_content,
        file_type=file_type,
        key_value_pairs=key_value_pairs,
        yaml_valid=yaml_valid,
        view_mode=view_mode,
        can_visual=can_visual,
        access_token=session.get('access_token', ''),
    )

@app.route('/api/eyaml/decrypt', methods=['POST'])
def api_decrypt():
    pub_key = get_setting("eyaml_public_key")
    priv_key = get_setting("eyaml_private_key")
    ciphertext = request.json.get('ciphertext', '')
    decrypted = run_eyaml("decrypt", ciphertext, pub_key=pub_key, priv_key=priv_key)
    if decrypted:
        return jsonify({"success": True, "plaintext": decrypted.strip()})
    return jsonify({"success": False, "error": "Decryption engine failed"}), 400

@app.route('/api/eyaml/encrypt', methods=['POST'])
def api_encrypt():
    pub_key = get_setting("eyaml_public_key")
    priv_key = get_setting("eyaml_private_key")
    plaintext = request.json.get('plaintext', '')
    encrypted = run_eyaml("encrypt", plaintext, pub_key=pub_key, priv_key=priv_key)
    if encrypted:
        # FIX: Eyaml may emit a leading 'ENC[PKCS7,...]' block plus secondary
        # metadata. We only persist/store the FIRST ENC[...] envelope so the
        # stored value is a single, clean Hiera-safe ENC() string.
        import re
        cleaned = encrypted.strip()
        match = re.search(r'ENC\[[^\]]*\]', cleaned, flags=re.DOTALL)
        if match:
            clean_enc = match.group(0).replace("\n", "").replace(" ", "").replace("\r", "")
        else:
            clean_enc = cleaned.replace("\n", "").replace(" ", "").replace("\r", "")
        return jsonify({"success": True, "ciphertext": clean_enc})
    return jsonify({"success": False, "error": "Encryption engine failed"}), 400

@app.route('/api/git/sync', methods=['POST'])
def api_git_sync():
    """Run git add . / git commit / git push inside the configured control repo."""
    repo_path = get_setting("control_repo_dir", "").strip()
    if not repo_path or not os.path.isdir(repo_path):
        return jsonify({"success": False, "error": "control_repo_dir is not configured or missing."}), 400

    commit_msg = (request.json or {}).get("message", "hieranano: auto-sync via web UI").strip()
    custom_env = os.environ.copy()
    custom_env["PATH"] = "/opt/puppetlabs/puppet/bin:/usr/bin:/bin:" + custom_env.get("PATH", "")
    custom_env["GIT_TERMINAL_PROMPT"] = "0"

    def run(cmd):
        return subprocess.run(cmd, cwd=repo_path, capture_output=True, text=True, env=custom_env)

    # 1. Ensure we are inside a git working tree
    chk = run(["git", "rev-parse", "--is-inside-work-tree"])
    if chk.returncode != 0:
        return jsonify({
            "success": False,
            "error": "Not a git repository",
            "details": (chk.stderr or chk.stdout).strip()
        }), 400

    # 2. Stage all changes
    add_res = run(["git", "add", "."])
    if add_res.returncode != 0:
        return jsonify({
            "success": False,
            "stage": "add",
            "error": add_res.stderr.strip() or add_res.stdout.strip()
        }), 500

    # 3. Commit (only if there is something to commit)
    status_res = run(["git", "status", "--porcelain"])
    if status_res.stdout.strip():
        commit_res = run(["git", "commit", "-m", commit_msg])
        if commit_res.returncode != 0:
            return jsonify({
                "success": False,
                "stage": "commit",
                "error": commit_res.stderr.strip() or commit_res.stdout.strip()
            }), 500
    else:
        commit_res = None  # nothing to commit

    # 4. Push (best-effort; failure here is reported but does not block)
    push_res = run(["git", "push"])
    push_ok = push_res.returncode == 0

    return jsonify({
        "success": True,
        "staged": True,
        "committed": bool(commit_res),
        "pushed": push_ok,
        "push_error": (push_res.stderr.strip() if not push_ok else ""),
        "commit_message": commit_msg,
    })

@app.route('/save-file', methods=['POST'])
def save_file():
    """Persist a file in the control repo. The visual grid and the raw editor
    both POST here with the relative `filepath` and `content`."""
    repo_path = get_setting("control_repo_dir")
    rel_path = request.form.get('filepath', '').strip()
    content = request.form.get('content', '')

    if repo_path and rel_path:
        full_path = os.path.normpath(os.path.join(repo_path, rel_path))
        # Path safety: must remain inside the repo root.
        if os.path.commonpath([full_path, os.path.normpath(repo_path)]) == os.path.normpath(repo_path):
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            with open(full_path, 'w') as f:
                f.write(content)
            flash(f"Saved file {rel_path}", "success")
        else:
            flash("Refused to write outside the control repo.", "error")
    else:
        flash("No active file or repo path configured.", "error")

    return redirect(url_for('index', active=rel_path))

@app.route('/save-visual-hiera', methods=['POST'])
def save_visual_hiera():
    repo_path = get_setting("control_repo_dir")
    rel_path = request.form.get('filepath', '').strip()
    keys = request.form.getlist('keys[]')
    values = request.form.getlist('values[]')

    if not repo_path or not rel_path:
        return redirect(url_for('index'))

    yaml_dict = {}
    for k, v in zip(keys, values):
        if not k.strip(): continue
        try:
            parsed_val = json.loads(v)
        except Exception:
            parsed_val = v
        yaml_dict[k.strip()] = parsed_val

    full_path = os.path.normpath(os.path.join(repo_path, rel_path))
    # Path safety
    if os.path.commonpath([full_path, os.path.normpath(repo_path)]) != os.path.normpath(repo_path):
        flash("Refused to write outside the control repo.", "error")
        return redirect(url_for('index'))

    yaml = YAML()
    yaml.default_flow_style = False

    with open(full_path, 'w') as f:
        yaml.dump(yaml_dict, f)

    flash(f"Visual Grid compiled and saved cleanly to {rel_path}", "success")
    return redirect(url_for('index', active=rel_path))

@app.route('/api/ai-consult', methods=['POST'])
def ai_consult():
    """AI consult: send ONLY the hiera class names and the selected puppet
    file's content. No hiera values (encrypted or otherwise) are sent.

    Token-saving design:
      * System prompt (instructions) is sent as a separate 'system' message
        so backends with prompt caching (OpenAI GPT-4o, Anthropic) can reuse it.
      * Puppet file is minified: comments stripped, blank lines collapsed,
        leading/trailing whitespace removed, then hard-capped at 50KB.
      * No decorative === HEADER === banners -- they cost tokens and convey
        no information the model doesn't already have.
    """
    import requests
    import traceback

    # Helper function to strip raw binary database types
    def clean_str(val):
        if isinstance(val, bytes):
            return val.decode('utf-8', errors='replace')
        return str(val) if val is not None else ""

    endpoint = clean_str(get_setting("ai_endpoint"))
    token = clean_str(get_setting("ai_token"))
    model = clean_str(get_setting("ai_model") or "gpt-4o-mini")
    repo_path = get_setting("control_repo_dir")

    req_json = request.get_json() or {}
    hiera_path = (req_json.get('hiera_path') or '').strip()
    hiera_keys = req_json.get('hiera_keys') or []   # LIST OF STRINGS ONLY
    puppet_path = (req_json.get('puppet_path') or '').strip()

    # Validate both paths live inside the repo
    def safe_join(rel):
        if not repo_path or not rel: return None
        p = os.path.normpath(os.path.join(repo_path, rel))
        if os.path.commonpath([p, os.path.normpath(repo_path)]) != os.path.normpath(repo_path):
            return None
        return p

    hiera_full = safe_join(hiera_path)
    puppet_full = safe_join(puppet_path)

    if not hiera_full or not os.path.isfile(hiera_full):
        return jsonify({"success": False, "error": "Invalid hiera file path"}), 400
    if not puppet_full or not os.path.isfile(puppet_full):
        return jsonify({"success": False, "error": "Invalid puppet file path"}), 400

    # ---- Minify the puppet file: drop comments, blank lines, edge whitespace
    def minify_puppet(text):
        out_lines = []
        for line in text.splitlines():
            stripped = line.strip()
            if not stripped:
                continue                       # drop blank lines
            if stripped.startswith('#'):
                continue                       # drop shell-style comments
            # Drop trailing inline comments ONLY when '#' is preceded by
            # whitespace and not inside a quoted string (good-enough heuristic).
            if ' #' in stripped:
                in_quote = False
                cut = -1
                for i, ch in enumerate(stripped):
                    if ch in ('"', "'"):
                        in_quote = not in_quote
                    elif ch == '#' and not in_quote and i > 0 and stripped[i-1] == ' ':
                        cut = i
                        break
                if cut > 0:
                    stripped = stripped[:cut].rstrip()
                    if not stripped:
                        continue
            out_lines.append(stripped)
        return "\n".join(out_lines)

    try:
        with open(puppet_full, 'r', encoding='utf-8', errors='replace') as f:
            puppet_raw = f.read()
    except Exception as e:
        return jsonify({"success": False, "error": f"Cannot read puppet file: {e}"}), 400

    puppet_min = minify_puppet(puppet_raw)
    truncated = False
    if len(puppet_min.encode('utf-8')) > MAX_PUPPET_FILE_BYTES:
        puppet_min = puppet_min.encode('utf-8')[:MAX_PUPPET_FILE_BYTES].decode('utf-8', errors='ignore')
        truncated = True

    # Sanitise: only string keys, no values from the hiera file
    safe_keys = [clean_str(k).strip() for k in hiera_keys if clean_str(k).strip()]
    keys_inline = ",".join(safe_keys)

    user_payload = (
        f"hiera={hiera_path}\n"
        f"puppet={puppet_path}\n"
        f"keys=[{keys_inline}]\n"
        f"---\n{puppet_min}"
    )
    if truncated:
        user_payload += f"\n[truncated to {MAX_PUPPET_FILE_BYTES}B]"

    # Evaluate system prompt execution immediately outside the generator loop
    try:
        system_prompt_content = clean_str(_build_system_prompt())
    except NameError:
        # Fallback if _build_system_prompt function isn't defined or imported in your app scope
        system_prompt_content = (
            "You are a helpful Puppet and Hiera configuration design assistant. "
            "Analyze the given keys against the provided layout."
        )
    except Exception as e:
        return jsonify({"success": False, "error": f"System prompt compilation failed: {str(e)}"}), 500

    def safe_str(obj):
        try:
            if isinstance(obj, bytes):
                return obj.decode('utf-8', errors='replace')
            if isinstance(obj, (list, tuple)):
                return safe_str(obj[0]) if obj else ''
            return str(obj)
        except Exception:
            return '<unprintable>'

    def stream_request():
        buf = ""
        try:
            # Format authorization appropriately for OpenAI endpoints
            auth_header = token if token.lower().startswith("bearer ") else f"Bearer {token}"
            headers = {
                "Authorization": auth_header,
                "Content-Type": "application/json",
                "Accept": "text/event-stream"
            }
            
            payload = {
                "model": model,
                "messages": [
                    {"role": "system", "content": system_prompt_content},
                    {"role": "user", "content": user_payload},
                ],
                "stream": True,
            }

            with requests.post(endpoint, json=payload, headers=headers, stream=True, timeout=60) as r:
                if r.status_code >= 400:
                    err_body = r.text or r.content.decode('utf-8', errors='replace') or '<no body>'
                    yield f"\n💥 AI endpoint returned HTTP {r.status_code}: {err_body.strip()}\n"
                    return

                for raw in r.iter_content(chunk_size=None, decode_unicode=False):
                    if not raw:
                        continue
                    if isinstance(raw, bytes):
                        try:
                            buf += raw.decode('utf-8', errors='replace')
                        except Exception:
                            continue
                    else:
                        buf += str(raw)
                    
                    while '\n\n' in buf:
                        event, buf = buf.split('\n\n', 1)
                        for line in event.splitlines():
                            line = line.strip()
                            if not line:
                                continue
                            if line.startswith('data:'):
                                data = line[5:].lstrip()
                                if data == '[DONE]':
                                    return
                                try:
                                    j = json.loads(data)
                                except Exception:
                                    continue
                                try:
                                    delta = j['choices'][0].get('delta') or {}
                                    piece = delta.get('content')
                                    if piece is None:
                                        piece = (j['choices'][0].get('message') or {}).get('content', '')
                                    if piece:
                                        yield piece
                                except Exception:
                                    if 'error' in j:
                                        err = j['error']
                                        msg = err.get('message') if isinstance(err, dict) else str(err)
                                        yield f"\n💥 AI error: {msg}\n"
        except Exception as e:
            tb_string = traceback.format_exc()
            yield f"\n💥 Connection Error: {safe_str(e)}\nTraceback Details:\n{tb_string}\n"

    return Response(
        stream_request(),
        mimetype='text/event-stream',
        headers={
            'Cache-Control': 'no-cache',
            'X-Accel-Buffering': 'no',
            'Connection': 'keep-alive',
        },
    )
@app.route('/update-config', methods=['POST'])
def update_config():
    set_settings({
        "control_repo_dir": request.form.get('control_repo_dir', '').strip(),
        "eyaml_public_key": request.form.get('eyaml_public_key', '').strip(),
        "eyaml_private_key": request.form.get('eyaml_private_key', '').strip(),
        "ai_endpoint": request.form.get('ai_endpoint', '').strip(),
        "ai_token": request.form.get('ai_token', '').strip(),
        "ai_prompt": request.form.get('ai_prompt', '').strip()
    })
    flash("Configuration settings stored successfully.", "success")
    return redirect(url_for('index'))

if __name__ == '__main__':
    pass
EOF

# ==============================================================================
# STEP 4: INTERFACE RENDERER COMPILING (templates/index.html)
# ==============================================================================
echo "🎨 Compiling Frontend Deck Assets..."
cat << 'EOF' > "$APP_DIR/templates/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Hieranano - Intelligence Control Deck</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        :root {
            --bg-0: #0f172a;
            --bg-1: #1e293b;
            --bg-2: #111827;
            --bg-code: #090d16;
            --border: #334155;
            --text: #cbd5e1;
            --accent: #38bdf8;
            --warn: #f59e0b;
        }
        *, *::before, *::after { box-sizing: border-box; }
        html, body { height: 100%; }
        body { margin: 0; background: var(--bg-0); color: var(--text); font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; overflow: hidden; }
        .wrapper { display: flex; height: 100vh; width: 100vw; min-height: 0; }

        /* ---------------- Sidebar (resizable) ---------------- */
        .sidebar {
            width: 340px; min-width: 220px; max-width: 600px;
            background: var(--bg-1); border-right: 1px solid var(--border);
            display: flex; flex-direction: column; height: 100%;
            position: relative; flex: 0 0 auto;
        }
        .sidebar-split-pane {
            display: flex; flex-direction: column;
            border-bottom: 2px solid var(--bg-0);
            overflow: hidden; min-height: 80px;
            flex: 1 1 50%;
        }
        .sidebar-split-pane:last-child { border-bottom: none; }
        .tree-root { padding: 10px; overflow-y: auto; overflow-x: auto; flex: 1 1 auto; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
        .tree-folder { cursor: pointer; user-select: none; padding: 3px 0; display: block; color: var(--accent); }
        .tree-folder::before { content: "📁 "; }
        .tree-files { padding-left: 15px; }
        .tree-file-link { display: block; color: #94a3b8; text-decoration: none; padding: 2px 5px; border-radius: 3px; text-overflow: ellipsis; overflow: hidden; white-space: nowrap; }
        .tree-file-link:hover { background: var(--border); color: #fff; }
        .tree-file-link.active { background: #0284c7; color: #fff; }

        /* Resizer handle between sidebar and main */
        .resizer-v {
            width: 6px; cursor: col-resize; background: transparent; flex: 0 0 auto; z-index: 5;
        }
        .resizer-v:hover, .resizer-v.dragging { background: #475569; }

        /* Resizer between the two sidebar split panes */
        .resizer-h {
            height: 6px; cursor: row-resize; background: var(--bg-0); flex: 0 0 auto; z-index: 4;
        }
        .resizer-h:hover, .resizer-h.dragging { background: #475569; }

        /* ---------------- Main desk ---------------- */
        .main-desk { flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; overflow: hidden; background: var(--bg-0); }
        .top-deck { height: 55px; background: var(--bg-1); border-bottom: 1px solid var(--border); display: flex; align-items: center; justify-content: space-between; padding: 0 20px; gap: 10px; flex-wrap: wrap; }
        .workspace-split {
            flex: 1 1 auto; min-height: 0; overflow-y: auto; overflow-x: hidden;
            padding: 20px; gap: 25px;
            display: flex; flex-direction: column;
        }

        .canvas-card { background: var(--bg-1); border: 1px solid var(--border); border-radius: 8px; display: flex; flex-direction: column; overflow: hidden; margin-bottom: 5px; }
        .canvas-header { padding: 12px 20px; background: var(--bg-2); border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px; }

        /* Tab strip for visual / raw switching (yaml files only) */
        .view-tabs { display: flex; gap: 0; background: #050a14; border-bottom: 1px solid var(--border); }
        .view-tabs a { flex: 1 1 50%; text-align: center; padding: 8px 10px; color: #94a3b8; text-decoration: none; font-size: 12px; font-weight: 700; letter-spacing: 0.5px; border-right: 1px solid var(--border); transition: background 0.15s; }
        .view-tabs a:last-child { border-right: none; }
        .view-tabs a:hover { background: #1e293b; color: #fff; }
        .view-tabs a.active { background: #0284c7; color: #fff; }

        /* Editor bodies. Both panes get a vertical scrollbar that always shows */
        .code-desk { width: 100%; height: 480px; max-height: 70vh; background: var(--bg-code); color: #f8fafc; border: none; padding: 15px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; outline: none; resize: vertical; overflow-y: auto !important; }
        .visual-grid-scroll { max-height: 65vh; overflow-y: auto; padding: 12px; background: #050a14; }
        .visual-grid-scroll #visualGridContainer { margin: 0; }

        .ai-assistant-tray { background: #0284c7; color: #fff; padding: 12px; border-radius: 6px; margin-bottom: 15px; display: none; flex-direction: column; gap: 8px; }
        .ai-stream-window { background: var(--bg-0); color: var(--accent); padding: 12px; border-radius: 4px; font-family: ui-monospace, monospace; font-size: 13px; max-height: 200px; overflow-y: auto; white-space: pre-wrap; }
        .grid-row-item { background: var(--bg-2); border: 1px solid var(--border); border-radius: 4px; margin-bottom: 8px; padding: 10px; }
        .eyaml-active { border-left: 4px solid var(--warn) !important; }

        /* Git sync banner / button */
        .git-sync-status { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; padding: 4px 10px; border-radius: 4px; background: #052e16; color: #4ade80; border: 1px solid #14532d; }
        .git-sync-status.error { background: #450a0a; color: #fca5a5; border-color: #7f1d1d; }
        .git-sync-status.pending { background: #1e293b; color: #fde68a; border-color: var(--warn); }

        /* AI Consult modal */
        .ai-key-list { max-height: 360px; overflow-y: auto; background: #0b1220; }
        .ai-key-row { display: flex; align-items: center; gap: 8px; padding: 6px 8px; border-radius: 4px; cursor: pointer; }
        .ai-key-row:hover { background: #1e293b; }
        .ai-key-row .form-check-input { cursor: pointer; }
        .ai-key-name { font-family: ui-monospace, monospace; font-size: 12px; color: #fde68a; word-break: break-all; }

        .ai-tree { max-height: 360px; overflow: auto; background: #0b1220; font-family: ui-monospace, monospace; font-size: 12px; }
        .ai-tree .tree-folder { color: #38bdf8; }
        .ai-tree .ai-file { display: block; color: #cbd5e1; padding: 3px 8px; border-radius: 3px; cursor: pointer; text-decoration: none; }
        .ai-tree .ai-file:hover { background: #1e293b; }
        .ai-tree .ai-file.selected { background: #075985; color: #fff; }
        .ai-tree .ai-file .ppath { color: #64748b; font-size: 11px; margin-left: 6px; }

        /* Custom scrollbars for the dark theme */
        *::-webkit-scrollbar { width: 10px; height: 10px; }
        *::-webkit-scrollbar-track { background: var(--bg-2); }
        *::-webkit-scrollbar-thumb { background: #475569; border-radius: 6px; }
        *::-webkit-scrollbar-thumb:hover { background: #64748b; }

        /* ---------------- Responsive breakpoints ---------------- */
        @media (max-width: 900px) {
            .wrapper { flex-direction: column; }
            .sidebar { width: 100% !important; max-width: none !important; height: 40vh; min-height: 220px; border-right: none; border-bottom: 1px solid var(--border); }
            .resizer-v { display: none; }
            .resizer-h { display: none; }
            .sidebar-split-pane { flex: 1 1 50%; min-height: 0; }
            .main-desk { width: 100%; height: 60vh; }
            .top-deck { height: auto; padding: 8px 12px; }
            .canvas-header { padding: 10px 12px; }
            .workspace-split { padding: 12px; gap: 15px; }
        }
        @media (max-width: 600px) {
            .canvas-header .input-group { width: 100% !important; }
            .canvas-header { flex-direction: column; align-items: stretch; }
            .top-deck { flex-direction: column; align-items: flex-start; }
        }
    </style>
</head>
<body>

<div class="wrapper">
    <div class="sidebar">
        <div class="sidebar-split-pane">
            <div class="p-2 bg-dark border-bottom border-secondary text-info fw-bold small">📊 HIERA DATA LAYERS (.yaml)</div>
            <div class="tree-root">
                {% macro render_hiera_node(nodes) %}
                    {% for node in nodes %}
                        {% if node.type == 'directory' %}
                            <div onclick="toggleFolder(event, 'hiera-dir-{{ node.path | replace('/', '-') | replace('.', '-') }}')" class="tree-folder fw-bold">{{ node.name }}</div>
                            <div class="tree-files" id="hiera-dir-{{ node.path | replace('/', '-') | replace('.', '-') }}">
                                {{ render_hiera_node(node.children) }}
                            </div>
                        {% else %}
                            <a href="?active={{ node.path | urlenc }}" class="tree-file-link {% if active_file == node.path %}active{% endif %}">📄 {{ node.name }}</a>
                        {% endif %}
                    {% endfor %}
                {% endmacro %}
                {% if hiera_tree %}{{ render_hiera_node(hiera_tree) }}{% else %}<div class="text-muted text-center p-2 small">No Hiera files loaded</div>{% endif %}
            </div>
        </div>

        <div class="sidebar-split-pane">
            <div class="p-2 bg-dark border-bottom border-secondary text-warning fw-bold small">📂 FULL REPOSITORY ROOT</div>
            <div class="tree-root">
                {% macro render_all_node(nodes) %}
                    {% for node in nodes %}
                        {% if node.type == 'directory' %}
                            <div onclick="toggleFolder(event, 'all-dir-{{ node.path | replace('/', '-') | replace('.', '-') }}')" class="tree-folder fw-bold">{{ node.name }}</div>
                            <div class="tree-files" id="all-dir-{{ node.path | replace('/', '-') | replace('.', '-') }}">
                                {{ render_all_node(node.children) }}
                            </div>
                        {% else %}
                            <a href="?active={{ node.path | urlenc }}" class="tree-file-link {% if active_file == node.path %}active{% endif %}">📄 {{ node.name }}</a>
                        {% endif %}
                    {% endfor %}
                {% endmacro %}
                {% if full_tree %}{{ render_all_node(full_tree) }}{% else %}<div class="text-muted text-center p-2 small">Configure a repository target</div>{% endif %}
            </div>
        </div>
    </div>

    <div class="resizer-v" id="sidebarResizer" title="Drag to resize"></div>

    <div class="main-desk">
        <div class="top-deck">
            <div class="d-flex gap-2 align-items-center"><span class="badge bg-secondary">System Platform Ready</span></div>
            <div class="d-flex gap-2 align-items-center">
                <span class="git-sync-status" id="gitSyncStatus" style="display:none;">● Idle</span>
                <button type="button" class="btn btn-sm btn-outline-success" onclick="triggerGitSync()">🔁 Git Sync</button>
            </div>
        </div>

        <div class="workspace-split">
            {% with messages = get_flashed_messages() %}
                {% if messages %}{% for msg in messages %}<div class="alert alert-success p-2 small mb-0 shadow">{{ msg }}</div>{% endfor %}{% endif %}
            {% endwith %}

            <div class="ai-assistant-tray" id="aiTray">
                <div class="d-flex justify-content-between align-items-center">
                    <span class="fw-bold">🤖 Hieranano AI Code Architect Pilot</span>
                    <button class="btn btn-xs btn-dark text-white py-0 px-2 small" onclick="document.getElementById('aiTray').style.display='none'">✕ Close</button>
                </div>
                <div class="small text-white-50">Context: <span class="text-warning" id="aiContextBadge">None</span></div>
                <div class="ai-stream-window" id="aiStreamOutput">Awaiting generation stream...</div>
            </div>

            <div class="canvas-card" id="editorCard">
                <div class="canvas-header">
                    <span class="text-info font-monospace fw-bold" id="editorTitle">
                        🎯 FILE WORKSPACE
                        {% if active_file %}[ {{ active_file }} ]{% endif %}
                    </span>
                    <div class="d-flex gap-2 align-items-center flex-wrap">
                        {% if active_file and view_mode == 'visual' and can_visual %}
                        <span class="badge bg-success">✨ Visual Hiera Mode</span>
                        <button class="btn btn-sm btn-warning fw-bold" onclick="openAiConsult()">🤖 Consult AI</button>
                        {% elif active_file and view_mode == 'raw' and can_visual %}
                        <span class="badge bg-info text-dark">📄 Raw YAML Mode</span>
                        <button class="btn btn-sm btn-warning fw-bold" onclick="openAiConsult()">🤖 Consult AI</button>
                        {% elif active_file and file_type == 'yaml' and not yaml_valid %}
                        <span class="badge bg-warning text-dark">⚠ YAML invalid — editing as raw</span>
                        {% elif active_file %}
                        <span class="badge bg-secondary">🛠 Raw Editor Mode</span>
                        {% endif %}
                    </div>
                </div>

                {% if active_file %}
                    {% if can_visual %}
                    <div class="view-tabs">
                        <a href="?active={{ active_file | urlenc }}&view=visual{{ ("&token=" + access_token) if access_token else "" }}" class="{% if view_mode == 'visual' %}active{% endif %}">✨ VISUAL HIERA GRID</a>
                        <a href="?active={{ active_file | urlenc }}&view=raw{{ ("&token=" + access_token) if access_token else "" }}" class="{% if view_mode == 'raw' %}active{% endif %}">📄 RAW SOURCE</a>
                    </div>
                    {% endif %}

                    {% if view_mode == 'visual' and can_visual %}
                    <div class="visual-grid-scroll">
                    <form action="{{ url_for('save_visual_hiera') }}" method="POST" id="visualGridForm">
                        <input type="hidden" name="filepath" value="{{ active_file }}">

                        <div id="visualGridContainer">
                            {% for item in key_value_pairs %}
                            <div class="row g-2 grid-row-item align-items-center {% if item.is_encrypted %}eyaml-active{% endif %}">
                                <div class="col-12 col-md-4">
                                    <input type="text" name="keys[]" class="form-control form-control-sm bg-dark text-white border-secondary font-monospace hiera-key" value="{{ item.key }}" placeholder="parameter.name">
                                </div>
                                <div class="col-9 col-md-6">
                                    <textarea name="values[]" class="form-control form-control-sm bg-dark text-info border-secondary font-monospace val-field" rows="1" data-raw-state="{% if item.is_encrypted %}ciphertext{% else %}plaintext{% endif %}" placeholder="Value mapping or literal">{{ item.value_raw }}</textarea>
                                </div>
                                <div class="col-3 col-md-2 d-flex gap-1 justify-content-end">
                                    {% if item.is_encrypted %}
                                    <button type="button" class="btn btn-sm btn-warning text-dark fw-bold px-2 py-1 small crypto-toggle-btn" onclick="toggleCryptoState(this)">🔓 Reveal</button>
                                    {% else %}
                                    <button type="button" class="btn btn-sm btn-outline-warning fw-bold px-2 py-1 small crypto-toggle-btn" onclick="toggleCryptoState(this)">🔒 Encrypt</button>
                                    {% endif %}
                                    <button type="button" class="btn btn-sm btn-outline-danger p-1 px-2" onclick="this.closest('.row').remove()">✕</button>
                                </div>
                            </div>
                            {% endfor %}
                        </div>
                        <div class="d-flex justify-content-between mt-3 gap-2 flex-wrap">
                            <button type="button" class="btn btn-sm btn-outline-info" onclick="addNewGridRow()">➕ Add Property Entry</button>
                            <div class="d-flex gap-2">
                                <a class="btn btn-sm btn-outline-secondary" href="?active={{ active_file | urlenc }}&view=raw{{ ("&token=" + access_token) if access_token else "" }}">📝 Edit Raw</a>
                                <button type="submit" class="btn btn-sm btn-success px-4 fw-bold">💾 Save & Compile Parameters</button>
                            </div>
                        </div>
                    </form>
                    </div>
                    {% else %}
                    <form action="{{ url_for('save_file') }}" method="POST" class="m-0">
                        <input type="hidden" name="filepath" value="{{ active_file }}">
                        <textarea id="rawTextarea" name="content" class="code-desk">{{ file_content }}</textarea>
                        <div class="p-2 bg-dark text-end border-top border-secondary d-flex justify-content-between align-items-center">
                            <span class="small text-muted ms-2">
                                {% if file_type == 'yaml' and not yaml_valid %}
                                YAML could not be parsed. Editing as plain text.
                                {% endif %}
                            </span>
                            <div class="d-flex gap-2">
                                {% if can_visual %}
                                <a class="btn btn-sm btn-outline-info" href="?active={{ active_file | urlenc }}&view=visual{{ ("&token=" + access_token) if access_token else "" }}">✨ Back to Visual</a>
                                {% endif %}
                                <button type="submit" class="btn btn-sm btn-primary px-4 fw-bold">💾 Write File</button>
                            </div>
                        </div>
                    </form>
                    {% endif %}
                {% else %}
                    <div class="p-5 text-center text-muted small">Select a file from the sidebar to begin editing.</div>
                {% endif %}
            </div>
        </div>
    </div>
</div>

<!-- =====================================================================
     AI CONSULT MODAL: select hiera keys + a puppet file to send to AI
     ===================================================================== -->
<div class="modal fade" id="aiConsultModal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered modal-xl modal-dialog-scrollable">
        <div class="modal-content bg-dark text-white border-secondary">
            <div class="modal-header border-secondary">
                <h6 class="modal-title fw-bold">🤖 AI Consult — Hiera Class <span class="text-muted small">↔</span> Puppet File</h6>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body small">
                <div class="alert alert-warning py-2 px-3 mb-3 d-flex align-items-start gap-2">
                    <span style="font-size:18px;">⚠️</span>
                    <div>
                        <strong>Privacy notice:</strong> This will send to the AI backend:
                        <ul class="mb-1 mt-1">
                            <li>The <strong>NAMES</strong> of the hiera classes/parameters you select below.</li>
                            <li>The <strong>contents</strong> of the puppet file you select on the right.</li>
                        </ul>
                        <strong>No</strong> hiera values, no revealed secrets, and no encrypted ENC[...] blobs are sent. Only the structure and the puppet code.
                    </div>
                </div>

                <div class="row g-3">
                    <div class="col-12 col-lg-6">
                        <div class="d-flex justify-content-between align-items-center mb-2">
                            <label class="text-info fw-bold mb-0">Hiera Classes / Parameters (from <span id="aiHieraFileLabel" class="text-warning font-monospace">…</span>)</label>
                            <div>
                                <button type="button" class="btn btn-xs btn-outline-info py-0 px-2" onclick="aiSelectAllKeys(true)">All</button>
                                <button type="button" class="btn btn-xs btn-outline-secondary py-0 px-2" onclick="aiSelectAllKeys(false)">None</button>
                            </div>
                        </div>
                        <div id="aiHieraKeyList" class="ai-key-list border border-secondary rounded p-2"></div>
                    </div>
                    <div class="col-12 col-lg-6">
                        <label class="text-warning fw-bold d-block mb-2">Puppet / Manifest File (where these classes are used)</label>
                        <input type="text" id="aiPuppetFilter" class="form-control form-control-sm bg-black text-white border-secondary mb-2" placeholder="🔍 filter (init.pp, profile, etc.)">
                        <div id="aiPuppetTree" class="ai-tree border border-secondary rounded p-2"></div>
                    </div>
                </div>
            </div>
            <div class="modal-footer border-secondary d-flex justify-content-between">
                <span class="text-muted small" id="aiConsultSummary">0 keys selected • no puppet file chosen</span>
                <div class="d-flex gap-2">
                    <button type="button" class="btn btn-sm btn-secondary" data-bs-dismiss="modal">Cancel</button>
                    <button type="button" class="btn btn-sm btn-warning fw-bold" onclick="submitAiConsult()">🚀 Send to AI</button>
                </div>
            </div>
        </div>
    </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
    // ---------------------------------------------------------------------
    // Token persistence: read ?token= once and keep it available globally,
    // then auto-inject it into every internal link so clicking around the
    // app never causes an auth drop-off.
    // ---------------------------------------------------------------------
    const TOKEN_STORAGE_KEY = 'hieranano_token';
    function getActiveToken() {
        const fromUrl = new URLSearchParams(window.location.search).get('token');
        if (fromUrl) {
            sessionStorage.setItem(TOKEN_STORAGE_KEY, fromUrl);
            return fromUrl;
        }
        return sessionStorage.getItem(TOKEN_STORAGE_KEY) || '';
    }
    const ACCESS_TOKEN = getActiveToken();

    function withToken(url) {
        if (!ACCESS_TOKEN) return url;
        const u = new URL(url, window.location.origin + window.location.pathname);
        u.searchParams.set('token', ACCESS_TOKEN);
        return u.pathname + '?' + u.searchParams.toString();
    }

    // Rewrite every internal anchor to preserve the token
    document.addEventListener('click', function (e) {
        const a = e.target.closest && e.target.closest('a[href]');
        if (!a) return;
        const href = a.getAttribute('href') || '';
        if (href.startsWith('http') || href.startsWith('mailto:') || href.startsWith('#')) return;
        if (href.includes('token=')) return; // already has it
        if (!ACCESS_TOKEN) return;
        e.preventDefault();
        window.location.href = withToken(href);
    });

    // If we landed here without a token but one is stored, append it now
    if (ACCESS_TOKEN && !new URLSearchParams(window.location.search).get('token')) {
        const newUrl = withToken(window.location.pathname);
        window.history.replaceState({}, '', newUrl);
    }

    // ---------------------------------------------------------------------
    // Resizable sidebar (vertical) and split-pane (horizontal between the
    // two file-tree sections). All state persists in localStorage.
    // ---------------------------------------------------------------------
    (function initResizers() {
        const sidebar = document.querySelector('.sidebar');
        const vResizer = document.getElementById('sidebarResizer');
        const panes = document.querySelectorAll('.sidebar-split-pane');
        const savedW = parseInt(localStorage.getItem('hieranano_sidebar_w') || '340', 10);
        if (!isNaN(savedW)) sidebar.style.width = savedW + 'px';

        let dragging = false;
        vResizer.addEventListener('mousedown', (e) => {
            dragging = true;
            vResizer.classList.add('dragging');
            document.body.style.cursor = 'col-resize';
            e.preventDefault();
        });
        document.addEventListener('mousemove', (e) => {
            if (!dragging) return;
            const w = Math.min(Math.max(e.clientX, 220), Math.min(600, window.innerWidth - 320));
            sidebar.style.width = w + 'px';
        });
        document.addEventListener('mouseup', () => {
            if (!dragging) return;
            dragging = false;
            vResizer.classList.remove('dragging');
            document.body.style.cursor = '';
            localStorage.setItem('hieranano_sidebar_w', parseInt(sidebar.style.width, 10));
        });

        if (panes.length === 2) {
            const hr = document.createElement('div');
            hr.className = 'resizer-h';
            panes[0].parentNode.insertBefore(hr, panes[1]);
            let hDrag = false;
            hr.addEventListener('mousedown', (e) => { hDrag = true; hr.classList.add('dragging'); document.body.style.cursor = 'row-resize'; e.preventDefault(); });
            document.addEventListener('mousemove', (e) => {
                if (!hDrag) return;
                const rect = panes[0].parentNode.getBoundingClientRect();
                const ratio = Math.min(Math.max((e.clientY - rect.top) / rect.height, 0.15), 0.85);
                panes[0].style.flex = `${ratio} 1 0%`;
                panes[1].style.flex = `${1 - ratio} 1 0%`;
            });
            document.addEventListener('mouseup', () => {
                if (!hDrag) return;
                hDrag = false; hr.classList.remove('dragging'); document.body.style.cursor = '';
            });
        }
    })();

    function toggleFolder(event, folderId) {
        event.stopPropagation();
        const element = document.getElementById(folderId);
        if(element) { element.style.display = (element.style.display === "none") ? "block" : "none"; }
    }

    function addNewGridRow() {
        const container = document.getElementById('visualGridContainer');
        const newRow = document.createElement('div');
        newRow.className = 'row g-2 grid-row-item align-items-center';
        newRow.innerHTML = `
            <div class="col-12 col-md-4"><input type="text" name="keys[]" class="form-control form-control-sm bg-dark text-white border-secondary font-monospace" placeholder="profile::service::ensure"></div>
            <div class="col-9 col-md-6"><textarea name="values[]" class="form-control form-control-sm bg-dark text-info border-secondary font-monospace val-field" rows="1" data-raw-state="plaintext" placeholder="running"></textarea></div>
            <div class="col-3 col-md-2 d-flex gap-1 justify-content-end">
                <button type="button" class="btn btn-sm btn-outline-warning fw-bold px-2 py-1 small crypto-toggle-btn" onclick="toggleCryptoState(this)">🔒 Encrypt</button>
                <button type="button" class="btn btn-sm btn-outline-danger p-1 px-2" onclick="this.closest('.row').remove()">✕</button>
            </div>
        `;
        container.appendChild(newRow);
    }

    function toggleCryptoState(button) {
        const row = button.closest('.row');
        const textarea = row.querySelector('.val-field');
        const currentVal = textarea.value.trim();
        const currentState = textarea.getAttribute('data-raw-state');

        if (!currentVal) return;

        if (currentState === "ciphertext") {
            button.innerText = "🔄 Decrypting...";
            fetch(withToken('/api/eyaml/decrypt'), {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ ciphertext: currentVal })
            })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    textarea.value = data.plaintext;
                    textarea.setAttribute('data-raw-state', 'plaintext');
                    row.classList.remove('eyaml-active');
                    button.innerText = "🔒 Encrypt";
                    button.className = "btn btn-sm btn-outline-warning fw-bold px-2 py-1 small crypto-toggle-btn";
                } else {
                    alert("Decryption Engine Failed: Validate local Puppet key permissions.");
                    button.innerText = "🔓 Reveal";
                }
            });
        } else {
            button.innerText = "🔄 Encrypting...";
            fetch(withToken('/api/eyaml/encrypt'), {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ plaintext: currentVal })
            })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    textarea.value = data.ciphertext;
                    textarea.setAttribute('data-raw-state', 'ciphertext');
                    row.classList.add('eyaml-active');
                    button.innerText = "🔓 Reveal";
                    button.className = "btn btn-sm btn-warning text-dark fw-bold px-2 py-1 small crypto-toggle-btn";
                } else {
                    alert("Encryption Engine Failed: Ensure eyaml binary is accessible.");
                    button.innerText = "🔒 Encrypt";
                }
            });
        }
    }

    // ---------------------------------------------------------------------
    // AI Consult modal logic
    // ---------------------------------------------------------------------
    const AI_FULL_TREE = {{ full_tree|tojson }};
    const ACTIVE_HIERA_PATH = {{ (active_file or '')|tojson }};
    const HIERA_KEYS = {{ (key_value_pairs | map(attribute='key') | list)|tojson }};

    function collectAllFiles(nodes, out) {
        for (const n of (nodes || [])) {
            if (n.type === 'file') out.push(n.path);
            else if (n.type === 'directory') collectAllFiles(n.children, out);
        }
    }

    function buildPuppetTreeHTML(nodes) {
        let html = '';
        for (const n of (nodes || [])) {
            if (n.type === 'directory') {
                html += `<div class="tree-folder" onclick="this.nextElementSibling.style.display = (this.nextElementSibling.style.display==='none'?'block':'none')">${escapeHtml(n.name)}</div>`;
                html += `<div class="tree-files">${buildPuppetTreeHTML(n.children)}</div>`;
            } else {
                // Highlight puppet-like files
                const lower = n.name.toLowerCase();
                const isPuppet = lower.endsWith('.pp') || lower.endsWith('.epp') || lower.endsWith('.yaml') || lower.endsWith('.yml') || lower.endsWith('.json');
                html += `<a href="#" class="ai-file ${isPuppet ? '' : 'text-muted'}" data-path="${escapeHtml(n.path)}" onclick="event.preventDefault(); selectPuppetFile(this)">📄 ${escapeHtml(n.name)}<span class="ppath">${escapeHtml(n.path)}</span></a>`;
            }
        }
        return html;
    }

    function escapeHtml(s) {
        return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    }

    function openAiConsult() {
        if (!ACTIVE_HIERA_PATH) { alert("No active hiera file."); return; }
        document.getElementById('aiHieraFileLabel').textContent = ACTIVE_HIERA_PATH;
        // Populate keys
        const keyList = document.getElementById('aiHieraKeyList');
        keyList.innerHTML = '';
        if (!HIERA_KEYS.length) {
            keyList.innerHTML = '<div class="text-muted small p-2">No hiera classes/keys found in this file.</div>';
        } else {
            for (const k of HIERA_KEYS) {
                const row = document.createElement('label');
                row.className = 'ai-key-row';
                row.innerHTML = `<input type="checkbox" class="form-check-input mt-0" checked value="${escapeHtml(k)}"> <span class="ai-key-name">${escapeHtml(k)}</span>`;
                keyList.appendChild(row);
            }
        }
        // Populate puppet tree
        document.getElementById('aiPuppetTree').innerHTML = buildPuppetTreeHTML(AI_FULL_TREE);
        document.getElementById('aiPuppetFilter').value = '';
        updateAiConsultSummary();
        const modal = new bootstrap.Modal(document.getElementById('aiConsultModal'));
        modal.show();
    }

    function aiSelectAllKeys(checked) {
        document.querySelectorAll('#aiHieraKeyList input[type=checkbox]').forEach(cb => cb.checked = checked);
        updateAiConsultSummary();
    }

    function selectPuppetFile(el) {
        document.querySelectorAll('#aiPuppetTree .ai-file').forEach(a => a.classList.remove('selected'));
        el.classList.add('selected');
        updateAiConsultSummary();
    }

    function updateAiConsultSummary() {
        const keyCount = document.querySelectorAll('#aiHieraKeyList input[type=checkbox]:checked').length;
        const sel = document.querySelector('#aiPuppetTree .ai-file.selected');
        const puppet = sel ? sel.getAttribute('data-path') : null;
        document.getElementById('aiConsultSummary').textContent =
            `${keyCount} key${keyCount===1?'':'s'} selected • puppet file: ${puppet || 'none chosen'}`;
    }

    document.addEventListener('change', (e) => {
        if (e.target && e.target.matches('#aiHieraKeyList input[type=checkbox]')) updateAiConsultSummary();
    });

    document.addEventListener('input', (e) => {
        if (e.target && e.target.id === 'aiPuppetFilter') {
            const q = e.target.value.toLowerCase();
            document.querySelectorAll('#aiPuppetTree .ai-file').forEach(a => {
                const txt = (a.getAttribute('data-path') || '').toLowerCase();
                a.style.display = (q === '' || txt.includes(q)) ? '' : 'none';
            });
        }
    });

    function submitAiConsult() {
        const selectedKeys = Array.from(document.querySelectorAll('#aiHieraKeyList input[type=checkbox]:checked')).map(cb => cb.value);
        const sel = document.querySelector('#aiPuppetTree .ai-file.selected');
        const puppetPath = sel ? sel.getAttribute('data-path') : null;
        if (!selectedKeys.length) { alert("Select at least one hiera class/parameter."); return; }
        if (!puppetPath) { alert("Select the puppet file where these classes are used."); return; }

        // Close modal, open tray
        bootstrap.Modal.getInstance(document.getElementById('aiConsultModal')).hide();
        const tray = document.getElementById('aiTray');
        const output = document.getElementById('aiStreamOutput');
        tray.style.display = 'flex';
        output.innerText = '🔄 Sending hiera class names + puppet file to AI (no values)…';
        document.getElementById('aiContextBadge').innerText = `${selectedKeys.length} keys ↔ ${puppetPath}`;

        fetch(withToken('/api/ai-consult'), {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
                hiera_path: ACTIVE_HIERA_PATH,
                hiera_keys: selectedKeys,
                puppet_path: puppetPath
            })
        })
        .then(response => {
            if (!response.ok) {
                return response.text().then(t => { throw new Error('HTTP ' + response.status + ': ' + t); });
            }
            if (!response.body) throw new Error('No response body (streaming unsupported by browser).');
            output.innerText = '';
            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            let acc = '';
            function read() {
                return reader.read().then(({ done, value }) => {
                    if (done) return;
                    acc += decoder.decode(value, { stream: true });
                    // Server now sends raw text chunks (not SSE). Render acc
                    // and keep the latest viewport in view.
                    output.innerText = acc;
                    output.scrollTop = output.scrollHeight;
                    return read();
                }).catch(err => {
                    output.innerText += `\n💥 Stream error: ${err}`;
                });
            }
            return read();
        })
        .catch(err => {
            output.innerText = `💥 ${err}`;
        });
    }

    // (openRawForActive removed: visual / raw switching is now a server-side
    //  decision driven by ?view= and rendered as tab links.)
</script>

    function triggerGitSync() {
        const status = document.getElementById('gitSyncStatus');
        const message = prompt("Commit message:", "hieranano: auto-sync via web UI");
        if (message === null) return;

        status.style.display = "inline-flex";
        status.className = "git-sync-status pending";
        status.innerText = "● Syncing…";

        fetch(withToken('/api/git/sync'), {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ message: message })
        })
        .then(res => res.json())
        .then(data => {
            if (data.success) {
                const parts = [];
                parts.push("staged");
                parts.push(data.committed ? "committed" : "nothing-to-commit");
                parts.push(data.pushed ? "pushed" : "push-failed");
                status.className = "git-sync-status" + (data.pushed ? "" : " error");
                status.innerText = "● " + parts.join(" • ");
                if (!data.pushed && data.push_error) {
                    console.warn("Git push error:", data.push_error);
                }
            } else {
                status.className = "git-sync-status error";
                status.innerText = "● " + (data.error || "Sync failed");
                alert("Git sync failed: " + (data.error || "unknown error") + (data.details ? "\n\n" + data.details : ""));
            }
        })
        .catch(err => {
            status.className = "git-sync-status error";
            status.innerText = "● Network error";
            alert("Git sync network error: " + err);
        });
    }
</script>
</body>
</html>
EOF

# ==============================================================================
# 🗄️ STEP 5: DB PROVISIONING & CRYPTO SEEDING (Enforced Configuration)
# ==============================================================================
echo "💾 Synchronizing database configurations..."

# Ensure tables exist
sqlite3 "$DATA_PERSIST_DIR/hieranano.db" <<SQL_EOF
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS file_visibility (filepath TEXT PRIMARY KEY, is_hidden INTEGER DEFAULT 0);
SQL_EOF

# 1. ALWAYS force-update the critical infrastructure paths
sqlite3 "$DATA_PERSIST_DIR/hieranano.db" <<SQL_EOF
INSERT OR REPLACE INTO settings (key, value) VALUES ('control_repo_dir', '${CONTROL_REPO_DIR}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('eyaml_public_key', '${EYAML_PUB_KEY}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('eyaml_private_key', '${EYAML_PRIV_KEY}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('ai_endpoint', '${AI_ENDPOINT}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('ai_model', '${AI_MODEL}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('ai_token', '${AI_TOKEN}');
SQL_EOF

# ai_prompt may contain newlines / apostrophes; store it separately using a
# parameterised sqlite3 invocation to avoid shell escaping issues.
#  Safe, seekable disk sequence
TEMP_SEED_FILE=$(mktemp)
printf "%s" "$AI_PROMPT" > "$TEMP_SEED_FILE"

sqlite3 "$DATA_PERSIST_DIR/hieranano.db" "INSERT OR REPLACE INTO settings (key, value) VALUES ('ai_prompt', readfile('$TEMP_SEED_FILE'));"

# Clean up the temp asset
rm -f "$TEMP_SEED_FILE"

# 2. Only seed the Auth Tokens if they do not exist
TOKEN_CHECK=$(sqlite3 "$DATA_PERSIST_DIR/hieranano.db" "SELECT value FROM settings WHERE key='secure_install_token';")

if [ -z "$TOKEN_CHECK" ]; then
    echo "🔒 Seeding initial cryptographic handshake tokens..."
    if [ "$NEEDS_SUDO" -eq 1 ] && [ "$RUNNING_UID" -ne 0 ]; then
      INITIAL_ENC_TOKEN=$(sudo "$FINAL_EYAML" encrypt --pkcs7-public-key "$EYAML_PUB_KEY" --stdin <<< "$INSTALL_SECRET")
    else
      INITIAL_ENC_TOKEN=$("$FINAL_EYAML" encrypt --pkcs7-public-key "$EYAML_PUB_KEY" --stdin <<< "$INSTALL_SECRET")
    fi

    CLEAN_TOKEN=$(echo "$INITIAL_ENC_TOKEN" | tr -d '\n' | tr -d ' ' | tr -d '\r')
    CLEAN_SECRET=$(echo "$INSTALL_SECRET" | tr -d '\n' | tr -d ' ' | tr -d '\r')

    sqlite3 "$DATA_PERSIST_DIR/hieranano.db" <<SQL_EOF
INSERT OR REPLACE INTO settings (key, value) VALUES ('plaintext_install_token', '${CLEAN_SECRET}');
INSERT OR REPLACE INTO settings (key, value) VALUES ('secure_install_token', '${CLEAN_TOKEN}');
SQL_EOF
else
    echo "✅ Authentication tokens already present. Skipping token re-seed."
fi

# ==============================================================================
# STEP 6: BACKWARD COMPATIBLE SERVICE STARTUP
# ==============================================================================
echo "⚙  Spawning workspace engine microservice..."

find_pid=$(lsof -t -i:$PORT || true)
if [ -n "$find_pid" ]; then kill -9 $find_pid; fi
pkill -f "gunicorn.*app:app" || true

nohup "$APP_DIR/venv/bin/python" -m gunicorn --workers 1 --bind "$HOST:$PORT" --chdir "$APP_DIR" app:app > "$APP_DIR/runtime.log" 2>&1 &

echo "----------------------------------------------------------------------"
echo "🎉 DEPLOY SUCCESSFUL: Hieranano Workspace Canvas Configured!"
echo "----------------------------------------------------------------------"
echo "👉 Entry Interface URL: http://127.0.0.1:5525/?token=${INSTALL_SECRET}"
echo "----------------------------------------------------------------------"
