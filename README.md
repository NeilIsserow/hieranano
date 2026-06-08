***NB! We have not provided any security/https/encryption in this code. We use your pem keys that you provide. Be sure to note this and if you wish to secure the app with https!***

# HieraNano

HieraNano is a high-performance, minimalist architecture assistant built specifically for Puppet Enterprise and Hiera workflow analytics. It provides developers and platform engineers with real-time AI consultations on Hiera keys and parameter definitions against contextually linked Puppet manifests—without ever leaking infrastructure values, node classifications, or secure materials to public or third-party Large Language Model (LLM) providers.

---

## What It Does

When managing dense infrastructure parameters, tracking exactly where a Hiera key map influences a downstream Puppet wrapper class can become difficult. HieraNano safely acts as an interpreter:
1. **Contextual Lookup Mapping:** You select specific Hiera class or parameter names and point to a Puppet manifest (`.pp`, `.epp`).
2. **Deterministic Context Isolation:** The app queries an AI provider (such as OpenAI's `gpt-4o-mini`) to describe the intent, structural constraints, typing requirements, and redundancies within your manifest.
3. **Zero-Leak Security Bounds:** It explicitly reads and exposes **only parameter names**. No Hiera values, node definitions, production secrets, or eyaml blocks are ever scraped or sent upstream.

---

## How It Does It (Under the Hood)

HieraNano features an optimized pipeline engineered to minimize processing costs and prevent serialization exceptions:

### 1. Token-Saving Minification Pipeline
Instead of feeding raw, multi-megabyte source manifests to the LLM, the core engine processes the code structure dynamically before sending it:
* **Comment Stripping:** Drops shell-style (`#`) comments and handles sophisticated quote-aware inline comment removal.
* **Whitespace Compression:** Collapses blank rows and redundant margins, downscaling total input volume by up to 60%.
* **Hard Byte Boundaries:** Automatically enforces strict limits on manifest payloads to guarantee consistent network round-trips.
* **Prompt Caching Optimization:** Decouples user metadata from structural rules. Instructions are systematically structured inside isolated `system` payload maps to leverage prompt caching protocols (e.g., OpenAI, Anthropic), reducing recurring cost structures.

### 2. Deep Serialization & Streaming Layer
To avoid application bottlenecks and memory bloat, HieraNano handles responses via Server-Sent Events (SSE):
* **Type-Safe Filtering:** Implements a strict binary sanitation barrier (`clean_str`) across all database fields (`ai_endpoint`, `ai_token`, `ai_model`). This eliminates Python `TypeError: Object of type bytes is not JSON serializable` crashes caused by raw database blobs.
* **Asynchronous Chunk Reassembly:** Uses non-blocking chunk iterators to decode upstream Server-Sent Events, streaming structural breakdowns to the interface letter-by-letter.

---

## Key Features

* **Strict Privacy Air-Gap:** Built specifically to guarantee zero transmission of parameter values or infrastructure state data.
* **Prompt-Cached Layouts:** Lowers LLM operation fees by utilizing structural prompt separation headers.
* **Universal Stream Delivery:** Built-in support for chunk buffering to ensure stable text rendering even over unreliable network proxies.
* **Robust Error Surfacing:** Traps inner background tracebacks directly within the client output terminal instead of falling back to uninformative `HTTP 500 Internal Server Error` pages.

---

## System Requirements

* **Operating System:** Linux (RHEL/Rock Linux 8+, Ubuntu 20.04+, or similar enterprise platform)
* **Python Runtime:** Python `3.10` or higher
* **Process Manager:** `systemd`
* **Network Context:** HTTPS enabled for secure local proxy termination. Access to `https://api.openai.com` or a localized internal OpenAI-compatible LLM endpoint.

---

## Installation & Deployment

HieraNano uses a master deployment layer script to configure its directory layout, SQLite schema, and WSGI execution engine.

### 1. Provision Virtual Environment and Directory Roots
Run the automated deployment helper script or configure your environment manually:
```bash
# Ensure dependencies are present
sudo apt-get update && sudo apt-get install -y python3-pip python3-venv sqlite3 lsof

# Verify the app path layout matches your service configurations
mkdir -p /root/.hieranano
cd /root/.hieranano
python3 -m venv venv
./venv/bin/pip install flask requests gunicorn
