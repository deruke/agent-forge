#!/usr/bin/env bash
# agent-forge entrypoint — display MOTD and hand off to CMD
set -e

# Show welcome banner
if [ -f /etc/motd ]; then
    cat /etc/motd
fi

# Verify API key presence (warn, don't block)
missing_keys=()
[ -z "$ANTHROPIC_API_KEY" ] && missing_keys+=("ANTHROPIC_API_KEY")
[ -z "$OPENAI_API_KEY" ]    && missing_keys+=("OPENAI_API_KEY")

if [ ${#missing_keys[@]} -gt 0 ]; then
    echo ""
    echo "⚠  Missing API keys: ${missing_keys[*]}"
    echo "   Set them in your .env file and restart the container."
    echo ""
fi

# Seed opencode config (NIM default + Ollama/Spark providers) if absent.
# Global seed so `opencode` finds it from ANY directory (e.g. a lab subdir), not just ~/workspace.
if [ ! -f "$HOME/.config/opencode/opencode.json" ] && [ -f "$HOME/.opencode-template.json" ]; then
    mkdir -p "$HOME/.config/opencode"
    cp "$HOME/.opencode-template.json" "$HOME/.config/opencode/opencode.json"
    echo "  Seeded ~/.config/opencode/opencode.json (NVIDIA NIM default + Ollama/Spark)"
fi
# Workspace copy too, so it's visible/editable next to your lab files.
if [ ! -f "$HOME/workspace/opencode.json" ] && [ -f "$HOME/.opencode-template.json" ]; then
    cp "$HOME/.opencode-template.json" "$HOME/workspace/opencode.json"
    echo "  Seeded workspace/opencode.json (NVIDIA NIM default + Ollama/Spark)"
fi

# Seed Hermes config from template if absent (so it stays editable without a rebuild)
if [ ! -f "$HOME/.hermes/config.yaml" ] && [ -f "$HOME/.hermes-template.yaml" ]; then
    cp "$HOME/.hermes-template.yaml" "$HOME/.hermes/config.yaml"
    echo "  Seeded ~/.hermes/config.yaml (llama.cpp endpoint)"
fi

# Probe a host service (non-blocking). $1=url $2=ready-msg $3=hint-msg
probe_host() {
    if curl -sf --max-time 1 "$1" >/dev/null 2>&1; then
        echo "  $2"
    else
        echo "  $3"
    fi
}

probe_host "http://host.docker.internal:11434/api/tags" \
    "Ollama detected on host — local models available via: oc" \
    "Ollama not detected on host. Start Ollama on your Mac for local model support."

probe_host "http://host.docker.internal:8080/v1/models" \
    "llama.cpp detected on host — Hermes ready via: hm  (hermes)" \
    "llama.cpp not on host:8080. Start: llama-server -m <model.gguf> --host 0.0.0.0 --port 8080"

# Package Age Gate status
_gate_mode="${PACKAGE_AGE_GATE:-enforce}"
case "$_gate_mode" in
    enforce) echo "  Package Age Gate: ENFORCING (blocks packages < ${PACKAGE_AGE_GATE_THRESHOLD:-7} days old)" ;;
    audit)   echo "  Package Age Gate: AUDIT mode (logging only)" ;;
    off)     echo "  Package Age Gate: DISABLED" ;;
esac

exec "$@"
