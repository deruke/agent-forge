#!/usr/bin/env bash
# =============================================================================
# hermes-switch — flip the Hermes agent between local and cloud models
#
#   hermes-switch local      # host llama.cpp / llama-swap (default model below)
#   hermes-switch spark       # DGX Spark vLLM over Tailscale (DGX_VLLM_URL); needs the tailscale overlay
#   hermes-switch nim         # NVIDIA NIM / build.nvidia.com (free tier)
#   hermes-switch gpt         # OpenAI GPT-5.5
#   hermes-switch gemini      # Google Gemini (AI Studio direct)
#   hermes-switch opus        # Anthropic Claude Opus 4.8   (1M context)
#   hermes-switch sonnet      # Anthropic Claude Sonnet 4.6 (1M context)
#   hermes-switch local my-model-id   # override the local model id
#   hermes-switch nim meta/llama-3.3-70b-instruct   # override the NIM model id
#   hermes-switch gemini gemini-3.1-pro-preview      # override the Gemini model id
#
# Rewrites the `model:` block in ~/.hermes/config.yaml (other settings untouched).
# Takes effect on the next `hermes` launch. Keys live in ~/.hermes/.env:
#   ANTHROPIC_API_KEY=...  OPENAI_API_KEY=...  NVIDIA_API_KEY=...  GEMINI_API_KEY=...  (local needs none)
# =============================================================================
set -uo pipefail

CFG="$HOME/.hermes/config.yaml"
TARGET="${1:-}"
LOCAL_MODEL="${2:-${HERMES_LOCAL_MODEL:-qwen3.6-27b}}"   # your llama-swap model id
LOCAL_URL="${HERMES_LOCAL_URL:-http://host.docker.internal:8000/v1}"
# DGX Spark vLLM over Tailscale. Endpoint + model come from .env (set by the tailscale overlay).
# Falls back to the host-local URL so a missing DGX_VLLM_URL doesn't write a broken empty base_url.
SPARK_URL="${DGX_VLLM_URL:-${HERMES_SPARK_URL:-http://host.docker.internal:8000/v1}}"
SPARK_MODEL="${2:-${DGX_VLLM_MODEL:-Qwen/Qwen3.6-27B-FP8}}"
# NVIDIA NIM model id — override with arg2 or $HERMES_NIM_MODEL. Pick any model from
# build.nvidia.com; Nemotron Super is the default (NVIDIA-native, agentic/tool-calling optimized).
# Alternatives: mistralai/mistral-nemotron, nvidia/nemotron-3-super-120b-a12b, meta/llama-3.3-70b-instruct.
NIM_MODEL="${2:-${HERMES_NIM_MODEL:-nvidia/llama-3.3-nemotron-super-49b-v1.5}}"
# Gemini model id — override with arg2 or $HERMES_GEMINI_MODEL. Gemini ids churn fast;
# confirm the current one at ai.google.dev/gemini-api/docs/models.
GEMINI_MODEL="${2:-${HERMES_GEMINI_MODEL:-gemini-3.5-flash}}"

usage() { echo "Usage: hermes-switch <local|spark|nim|gpt|gemini|opus|sonnet> [model-id]" >&2; exit 2; }
[ -z "$TARGET" ] && usage
case "$TARGET" in local|spark|nim|gpt|gemini|opus|sonnet) ;; *) echo "Unknown target: $TARGET" >&2; usage ;; esac

if [ ! -f "$CFG" ]; then
    echo "ERROR: $CFG not found. Is Hermes installed (INSTALL_HERMES=true) and seeded?" >&2
    echo "       Start the container once so entrypoint.sh seeds it, or copy the template." >&2
    exit 1
fi

# Warn (don't block) if the needed API key is absent from ~/.hermes/.env or the env.
key_present() {  # $1 = VAR name
    local v; v="$(printenv "$1" 2>/dev/null)"
    [ "${#v}" -gt 0 ] && return 0
    [ -f "$HOME/.hermes/.env" ] && grep -qE "^\s*$1\s*=\s*\S" "$HOME/.hermes/.env" && return 0
    return 1
}
case "$TARGET" in
    spark)  [ "${#DGX_VLLM_URL}" -gt 0 ] || echo "⚠  DGX_VLLM_URL not set, falling back to $SPARK_URL. Set it in .env (e.g. http://100.x.x.x:8000/v1) and bring up the tailscale overlay." >&2 ;;
    gpt)    key_present OPENAI_API_KEY    || echo "⚠  OPENAI_API_KEY not set in ~/.hermes/.env" >&2 ;;
    nim)    key_present NVIDIA_API_KEY    || echo "⚠  NVIDIA_API_KEY not set in ~/.hermes/.env" >&2 ;;
    gemini) key_present GEMINI_API_KEY || key_present GOOGLE_API_KEY || echo "⚠  GEMINI_API_KEY (or GOOGLE_API_KEY) not set in ~/.hermes/.env" >&2 ;;
    opus|sonnet) key_present ANTHROPIC_API_KEY || echo "⚠  ANTHROPIC_API_KEY not set in ~/.hermes/.env" >&2 ;;
esac

# Rewrite only the model: block; preserve everything else. PyYAML is present in the image.
TARGET="$TARGET" LOCAL_MODEL="$LOCAL_MODEL" LOCAL_URL="$LOCAL_URL" SPARK_MODEL="$SPARK_MODEL" SPARK_URL="$SPARK_URL" NIM_MODEL="$NIM_MODEL" GEMINI_MODEL="$GEMINI_MODEL" CFG="$CFG" python3 - <<'PY'
import os, yaml
cfg_path = os.environ["CFG"]
with open(cfg_path) as f:
    cfg = yaml.safe_load(f) or {}

t = os.environ["TARGET"]
# 1M context is native to Opus 4.8 / Sonnet 4.6 — no beta header, no model-id variant.
# Set context_length explicitly so Hermes uses the full window instead of a conservative guess.
blocks = {
    "local":  {"default": os.environ["LOCAL_MODEL"], "provider": "custom",
               "base_url": os.environ["LOCAL_URL"], "api_key": "no-key-needed"},
    "spark":  {"default": os.environ["SPARK_MODEL"], "provider": "custom",
               "base_url": os.environ["SPARK_URL"], "api_key": "no-key-needed"},  # DGX vLLM over Tailscale
    "nim":    {"default": os.environ["NIM_MODEL"], "provider": "nvidia"},  # build.nvidia.com; uses NVIDIA_API_KEY
    "gemini": {"default": os.environ["GEMINI_MODEL"], "provider": "gemini"},  # Google AI Studio; uses GEMINI_API_KEY/GOOGLE_API_KEY
    "gpt":    {"default": "gpt-5.5", "provider": "custom",
               "base_url": "https://api.openai.com/v1"},               # api_key falls back to OPENAI_API_KEY
    "opus":   {"default": "claude-opus-4-8", "provider": "anthropic",
               "context_length": 1000000},                            # uses ANTHROPIC_API_KEY
    "sonnet": {"default": "claude-sonnet-4-6", "provider": "anthropic",
               "context_length": 1000000},
}
cfg["model"] = blocks[t]
with open(cfg_path, "w") as f:
    yaml.safe_dump(cfg, f, sort_keys=False, default_flow_style=False)
PY

echo "✓ Hermes set to '$TARGET'. Active model block:"
sed -n '/^model:/,/^[^[:space:]]/p' "$CFG" | sed '$d' | sed 's/^/    /'
echo "  (start or restart 'hermes' to use it)"
