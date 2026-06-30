#!/usr/bin/env bash
# Install offensive security tools (standalone, outside Docker build)
set -euo pipefail

echo "=== Offensive Tools — APT Packages ==="
sudo apt-get update && sudo apt-get install -y --no-install-recommends \
    nmap nikto sqlmap hydra john hashcat

echo "=== Offensive Tools — Go Binaries ==="
go install github.com/OJ/gobuster/v3@latest
go install github.com/ffuf/ffuf/v2@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/owasp-amass/amass/v4/...@master

echo "=== Offensive Tools — Python Packages ==="
pip3 install --no-cache-dir \
    impacket netexec certipy-ad bloodhound enum4linux-ng

echo "=== Offensive Tools — Responder ==="
sudo git clone --depth 1 https://github.com/lgandx/Responder.git /opt/Responder
sudo ln -sf /opt/Responder/Responder.py /usr/local/bin/responder

echo "=== Offensive Tools Installation Complete ==="
