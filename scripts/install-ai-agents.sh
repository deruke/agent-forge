#!/usr/bin/env bash
# Install all four AI CLI agents
# Used during Docker build (Stage 3) or standalone setup
set -euo pipefail

echo "=== Installing Claude Code ==="
curl -fsSL https://claude.ai/install.sh | bash

echo "=== Installing OpenCode ==="
curl -fsSL https://opencode.ai/install | bash

echo "=== Installing Codex CLI ==="
npm install -g @openai/codex

echo "=== Installing Hermes Agent (NousResearch) ==="
# Non-interactive install. Provider config is pre-seeded via config/hermes-config.yaml
# (-> ~/.hermes/config.yaml); we deliberately skip the interactive `hermes setup` wizard.
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

echo "=== AI Agent Installation Complete ==="
echo "Installed:"
echo "  - Claude Code (claude)"
echo "  - OpenCode (opencode)"
echo "  - Codex CLI (codex)"
echo "  - Hermes Agent (hermes) -> local llama.cpp via host.docker.internal:8080"
