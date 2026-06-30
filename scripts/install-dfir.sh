#!/usr/bin/env bash
# Install DFIR tools (standalone, outside Docker build)
set -euo pipefail

echo "=== DFIR Tools — APT Packages ==="
sudo apt-get update && sudo apt-get install -y --no-install-recommends \
    exiftool binwalk foremost sleuthkit tshark tcpdump yara

echo "=== DFIR Tools — Python Packages ==="
pip3 install --no-cache-dir \
    volatility3 oletools yara-python pe-tree sigma-cli floss

echo "=== DFIR Tools — Chainsaw ==="
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then CS_ARCH="x86_64-unknown-linux-gnu"
else CS_ARCH="aarch64-unknown-linux-gnu"; fi
curl -fsSL "https://github.com/WithSecureLabs/chainsaw/releases/latest/download/chainsaw_${CS_ARCH}.tar.gz" \
    | sudo tar xz -C /usr/local/bin/ --strip-components=1 --wildcards '*/chainsaw'

echo "=== DFIR Tools — Hayabusa ==="
if [ "$ARCH" = "amd64" ]; then HB_ARCH="x86_64-unknown-linux-gnu"
else HB_ARCH="aarch64-unknown-linux-gnu"; fi
curl -fsSL "https://github.com/Yamato-Security/hayabusa/releases/latest/download/hayabusa-linux-${HB_ARCH}.zip" \
    -o /tmp/hayabusa.zip
unzip -o /tmp/hayabusa.zip -d /tmp/hayabusa
sudo find /tmp/hayabusa -name 'hayabusa*' -type f -exec mv {} /usr/local/bin/hayabusa \;
sudo chmod +x /usr/local/bin/hayabusa
rm -rf /tmp/hayabusa /tmp/hayabusa.zip

echo "=== DFIR Tools Installation Complete ==="
