# ============================================================================
# agent-forge — Agentic AI Isolation Platform for Security Operators
# Multi-stage build: go-builder → base → ai-agents → base-tools → final
#
# Modular, opt-in payloads via build args (all default OFF → lean vanilla base):
#   --build-arg INSTALL_HERMES=true     # NousResearch Hermes agent (+~4.3 GB)
#   --build-arg INSTALL_REDTEAM=true    # offensive: web/creds/AD/privesc
#   --build-arg INSTALL_BLUETEAM=true   # DFIR: memory/disk/timeline, malware analysis
# Flags are independent — combine any subset. Examples:
#   docker build -t agent-forge:base .                                      # lean
#   docker build --build-arg INSTALL_REDTEAM=true  -t agent-forge:redteam  .
#   docker build --build-arg INSTALL_BLUETEAM=true -t agent-forge:blueteam .
#   docker build --build-arg INSTALL_REDTEAM=true --build-arg INSTALL_HERMES=true -t agent-forge:red-hermes .
# ============================================================================

# ------------------------------------------------------------------
# Stage 1: Go builder — compile Go-based recon tools (shipped in base)
# ------------------------------------------------------------------
FROM golang:1.24.13-bookworm AS go-builder

ENV CGO_ENABLED=0
ENV GOTOOLCHAIN=auto

# Build all Go recon tools (separate RUN per tool for better error isolation).
# Versions pinned for reproducible builds (bump deliberately). nuclei's value is its
# templates, which self-update at runtime — pinning the binary does not freeze detections.
RUN go install github.com/OJ/gobuster/v3@v3.8.2
RUN go install github.com/ffuf/ffuf/v2@v2.1.0
RUN go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@v3.9.0
RUN go install github.com/projectdiscovery/httpx/cmd/httpx@v1.9.0
RUN go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@v2.14.0
# amass v4 is in maintenance (v5 exists under .../amass/v5); pin newest v4 tag.
RUN go install github.com/owasp-amass/amass/v4/...@v4.2.0

# ------------------------------------------------------------------
# Stage 2: Base — Ubuntu 24.04, system packages, runtimes
# ------------------------------------------------------------------
# Pinned by digest for reproducibility (ubuntu:24.04 LTS, 2026-06).
FROM ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# System packages + runtimes in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    pkg-config \
    libffi-dev \
    libssl-dev \
    # Core utilities
    git \
    curl \
    wget \
    jq \
    unzip \
    zip \
    file \
    sudo \
    ca-certificates \
    gnupg \
    lsb-release \
    # Editors & terminal
    tmux \
    vim \
    nano \
    # DNS & domain lookup
    dnsutils \
    whois \
    # Search & processing
    ripgrep \
    yq \
    httpie \
    # Python 3.12
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # Node.js 20 LTS (via NodeSource)
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y nodejs \
    # Cleanup
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# Stage 3: AI agents (Claude/OpenCode/Gemini/Codex always; Hermes opt-in)
# ------------------------------------------------------------------
FROM base AS ai-agents

# Bun runtime — required for PAI hooks (#!/usr/bin/env bun)
RUN curl -fsSL https://bun.sh/install | bash \
    && cp /root/.bun/bin/bun /usr/local/bin/bun \
    && chmod +x /usr/local/bin/bun \
    && echo "Bun installed to /usr/local/bin/bun"

# Claude Code — installs to /root/.local/bin/claude
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp /root/.local/bin/claude /usr/local/bin/claude \
    && chmod +x /usr/local/bin/claude \
    && echo "Claude Code installed to /usr/local/bin/claude"

# OpenCode — installs to /root/.opencode/bin/opencode
RUN curl -fsSL https://opencode.ai/install | bash \
    && cp /root/.opencode/bin/opencode /usr/local/bin/opencode \
    && chmod +x /usr/local/bin/opencode \
    && echo "OpenCode installed to /usr/local/bin/opencode"

# Codex CLI — npm global package. Pinned; these CLIs move fast — bump often.
RUN npm install -g @openai/codex@0.139.0 \
    && echo "Codex CLI installed"

# OpenAI-compatible SDK — required for OpenCode + Ollama local model support
RUN npm install -g @ai-sdk/openai-compatible@2.0.48 \
    && echo "AI SDK OpenAI-compatible provider installed"

# Hermes Agent (NousResearch) — OPT-IN. Adds ~4.3 GB (auto-provisions Python 3.11 + ffmpeg).
# Enable with --build-arg INSTALL_HERMES=true. Installs to /usr/local/bin/hermes; the provider
# config is seeded later (config/hermes-config.yaml -> ~/.hermes/config.yaml). The `hermes setup`
# wizard is skipped (non-interactive).
ARG INSTALL_HERMES=false
RUN if [ "$INSTALL_HERMES" = "true" ]; then \
        curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash \
        && echo "Hermes Agent installed to /usr/local/bin/hermes"; \
    else \
        echo "Hermes skipped (INSTALL_HERMES=false)"; \
    fi

# ------------------------------------------------------------------
# Stage 4: Base tools (recon + dual-use always; red/blue payloads opt-in)
# ------------------------------------------------------------------
FROM ai-agents AS base-tools

# --- Recon + dual-use apt packages (every operator) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Recon & scanning
    nmap \
    nikto \
    # Packet capture (general network visibility)
    tshark \
    tcpdump \
    # Dual-use: forensics / metadata / reverse engineering (used by red AND blue)
    exiftool \
    binwalk \
    yara \
    radare2 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- Go recon binaries from Stage 1 ---
COPY --from=go-builder /go/bin/gobuster   /usr/local/bin/
COPY --from=go-builder /go/bin/ffuf       /usr/local/bin/
COPY --from=go-builder /go/bin/nuclei     /usr/local/bin/
COPY --from=go-builder /go/bin/httpx      /usr/local/bin/
COPY --from=go-builder /go/bin/subfinder  /usr/local/bin/
COPY --from=go-builder /go/bin/amass      /usr/local/bin/

# --- yara-python bindings (dual-use; pairs with the yara CLI above) ---
RUN pip3 install --no-cache-dir --break-system-packages --ignore-installed \
    yara-python \
    && echo "yara-python installed"

# --- RED TEAM tools — OPT-IN (--build-arg INSTALL_REDTEAM=true) ---
# web exploitation, credential attacks, Active Directory, privesc.
# Mandatory tools fail the build; optional ones (NetExec/Responder/PEASS) are fail-soft.
ARG INSTALL_REDTEAM=false
RUN if [ "$INSTALL_REDTEAM" = "true" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            sqlmap hydra john hashcat \
        && apt-get clean && rm -rf /var/lib/apt/lists/* \
        && pip3 install --no-cache-dir --break-system-packages --ignore-installed \
            impacket certipy-ad bloodhound \
        && ( pip3 install --no-cache-dir --break-system-packages --ignore-installed \
                git+https://github.com/Pennyw0rth/NetExec.git \
             || echo "WARN: NetExec install failed (optional; known arm64 build issue)" ) \
        && ( pip3 install --no-cache-dir --break-system-packages --ignore-installed \
                git+https://github.com/cddmp/enum4linux-ng.git \
             || echo "WARN: enum4linux-ng install failed (optional)" ) \
        && ( git clone --depth 1 https://github.com/lgandx/Responder.git /opt/Responder \
                && ln -s /opt/Responder/Responder.py /usr/local/bin/responder \
                && chmod +x /opt/Responder/Responder.py \
             || echo "WARN: Responder clone failed (optional)" ) \
        && ( mkdir -p /opt/PEASS \
                && curl -fsSL https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh -o /opt/PEASS/linpeas.sh \
                && curl -fsSL https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany_ofs.exe -o /opt/PEASS/winpeas.exe \
                && chmod +x /opt/PEASS/linpeas.sh \
                && ln -s /opt/PEASS/linpeas.sh /usr/local/bin/linpeas \
             || echo "WARN: PEASS download failed (optional)" ) \
        && echo "Red team tools installed"; \
    else \
        echo "Red team skipped (INSTALL_REDTEAM=false)"; \
    fi

# --- BLUE TEAM tools — OPT-IN (--build-arg INSTALL_BLUETEAM=true) ---
# memory/disk/timeline forensics, log/event analysis, malware analysis.
# chainsaw/hayabusa intentionally track 'latest' (bundled detection rules).
ARG INSTALL_BLUETEAM=false
RUN if [ "$INSTALL_BLUETEAM" = "true" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            sleuthkit foremost \
        && apt-get clean && rm -rf /var/lib/apt/lists/* \
        && pip3 install --no-cache-dir --break-system-packages --ignore-installed \
            volatility3 oletools sigma-cli \
        && ( pip3 install --no-cache-dir --break-system-packages --ignore-installed pe-tree \
             || echo "WARN: pe-tree install failed (optional)" ) \
        && ( pip3 install --no-cache-dir --break-system-packages --ignore-installed flare-floss \
             || echo "WARN: flare-floss install failed (optional)" ) \
        && ( pip3 install --no-cache-dir --break-system-packages --ignore-installed plaso \
             || echo "WARN: plaso install failed (optional)" ) \
        && printf '#!/bin/bash\npython3 -m volatility3.cli "$@"\n' > /usr/local/bin/vol3 \
        && chmod +x /usr/local/bin/vol3 \
        && ( ARCH=$(dpkg --print-architecture); \
             if [ "$ARCH" = "amd64" ]; then CS_ARCH="x86_64-unknown-linux-gnu"; else CS_ARCH="aarch64-unknown-linux-gnu"; fi; \
             curl -fsSL "https://github.com/WithSecureLabs/chainsaw/releases/latest/download/chainsaw_${CS_ARCH}.tar.gz" \
                | tar xz -C /usr/local/bin/ --strip-components=1 --wildcards '*/chainsaw' \
             || echo "WARN: Chainsaw download failed (optional)" ) \
        && ( ARCH=$(dpkg --print-architecture); \
             case "$ARCH" in amd64) HBPAT="lin-x64-gnu" ;; arm64) HBPAT="lin-aarch64-gnu" ;; *) HBPAT="lin-x64-gnu" ;; esac; \
             URL=$(curl -fsSL https://api.github.com/repos/Yamato-Security/hayabusa/releases/latest | grep -oE "https://github.com/[^\"]+hayabusa-[^\"]*${HBPAT}\.zip" | head -1); \
             if [ -n "$URL" ]; then \
                 mkdir -p /opt/hayabusa && curl -fsSL "$URL" -o /tmp/hb.zip && unzip -o -q /tmp/hb.zip -d /opt/hayabusa \
                 && bin=$(find /opt/hayabusa -type f -name "hayabusa-*-${HBPAT##*-}*" ! -name '*.zip' | head -1) \
                 && chmod +x "$bin" && ln -sf "$bin" /usr/local/bin/hayabusa && rm -f /tmp/hb.zip \
                 && echo "Hayabusa installed -> $bin"; \
             else echo "WARN: could not resolve Hayabusa ${HBPAT} asset (optional)"; fi ) \
        && echo "Blue team tools installed"; \
    else \
        echo "Blue team skipped (INSTALL_BLUETEAM=false)"; \
    fi

# ------------------------------------------------------------------
# Stage 5: Final — non-root user, workspace, entrypoint
# ------------------------------------------------------------------
FROM base-tools AS final

# Create operator user (UID 1000) with passwordless sudo
# Ubuntu 24.04 ships with 'ubuntu' user at UID 1000 — remove it first
RUN userdel -r ubuntu 2>/dev/null; \
    groupdel operator 2>/dev/null; \
    groupadd -g 1000 operator && \
    useradd -m -s /bin/bash -u 1000 -g operator operator && \
    echo "operator ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/operator && \
    chmod 0440 /etc/sudoers.d/operator

# Workspace and agent config directories
RUN mkdir -p /home/operator/workspace /home/operator/.claude/skills /home/operator/.hermes \
    && chown -R operator:operator /home/operator

# Copy config files
COPY config/.bashrc      /home/operator/.bashrc
COPY config/.tmux.conf   /home/operator/.tmux.conf
COPY config/motd.txt     /etc/motd
COPY config/opencode.json /home/operator/.opencode-template.json

# Hermes Agent config template (points at host llama.cpp via host.docker.internal:8080).
# entrypoint.sh seeds ~/.hermes/config.yaml from this if absent (only useful when Hermes
# was installed via INSTALL_HERMES=true). Tiny, so always shipped.
COPY --chown=operator:operator config/hermes-config.yaml /home/operator/.hermes-template.yaml

# Copy and set entrypoint
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Hermes model switcher (local llama.cpp <-> OpenAI GPT-5.5 <-> Anthropic Opus/Sonnet)
COPY scripts/hermes-switch.sh /usr/local/bin/hermes-switch
RUN chmod +x /usr/local/bin/hermes-switch

# --- Package Age Gate (supply chain defense) ---
# Wrapper scripts shadow pip/npm in PATH, checking package publish dates
# against a configurable threshold before allowing installation.
COPY package-age-gate/gate.py      /usr/local/lib/package-age-gate/gate.py
COPY package-age-gate/wrappers/pip /usr/local/lib/package-age-gate/wrappers/pip
COPY package-age-gate/wrappers/npm /usr/local/lib/package-age-gate/wrappers/npm
COPY package-age-gate/allowlist.txt /usr/local/lib/package-age-gate/allowlist.txt
RUN ln -s /usr/local/lib/package-age-gate/wrappers/pip \
          /usr/local/lib/package-age-gate/wrappers/pip3 \
    && chmod +x /usr/local/lib/package-age-gate/wrappers/pip \
                /usr/local/lib/package-age-gate/wrappers/npm \
    && mkdir -p /home/operator/.local/log \
    && chown -R operator:operator /home/operator/.local

# Environment variables for AI agents
ENV DISABLE_AUTOUPDATER=1
ENV TERM=xterm-256color
ENV PATH="/usr/local/lib/package-age-gate/wrappers:/home/operator/.local/bin:${PATH}"

# Labels
LABEL maintainer="Derek Banks"
LABEL description="agent-forge — modular AI security platform (opt-in Hermes / red-team / blue-team payloads)"
LABEL version="3.1"

USER operator
WORKDIR /home/operator/workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
