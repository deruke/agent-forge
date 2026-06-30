# agent-forge

A reproducible Docker **AI security workstation** for operators: three core AI CLI agents (plus an opt-in local-model agent) and curated offensive/DFIR tooling in one environment.

Built for operators who want AI-assisted pentesting, incident response, and forensic analysis with a host-hygiene boundary around the tooling, ready to run. See [Security model](#security-model) for what that boundary does and does not do.

### Build flavors

agent-forge builds from a single, flag-driven Dockerfile: a lean **vanilla base** plus three
independent, opt-in payloads you enable at build time, so you only carry what you need.

| Build | Adds | Use for |
|-------|------|---------|
| **base** (lean default, ~4.1 GB) | 3 AI agents (Claude/OpenCode/Codex), recon (nmap/nuclei/httpx/ffuf/gobuster/subfinder/amass/nikto), packet capture, dual-use forensics/RE (radare2/yara/binwalk/exiftool), the package age gate | A clean AI + recon workstation |
| **`INSTALL_HERMES`** | NousResearch Hermes agent wired to a local llama.cpp / llama-swap server | Local-model agent work |
| **`INSTALL_REDTEAM`** | web exploitation, credential attacks, Active Directory, privesc | Offensive engagements |
| **`INSTALL_BLUETEAM`** | memory/disk/timeline forensics, log/event analysis, malware analysis | DFIR / incident response |

Flags are independent — combine any subset. See [Build Flavors](#build-flavors-vanilla--red--blue) for the full tool breakdown and build commands.

## Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/deruke/agent-forge.git && cd agent-forge
cp .env.example .env
# Edit .env with your API keys

# 2. Run
docker compose up -d
docker compose exec forge bash

# 3. Use any agent
claude "enumerate attack surface for 10.0.0.0/24"
opencode "analyze this memory dump for IOCs"
codex "write a Sigma rule for lateral movement via PsExec"
```

## AI Agents

| Agent | Command | Alias | Provider | Included |
|-------|---------|-------|----------|----------|
| Claude Code | `claude` | `cc` | Anthropic | always |
| OpenCode | `opencode` | `oc` | Open Source (Ollama) | always |
| Codex CLI | `codex` | `cx` | OpenAI | always |
| Hermes Agent | `hermes` | `hm` | Local (llama.cpp / llama-swap) | opt-in (`INSTALL_HERMES=true`) |

The three core agents ship in every build; Hermes is opt-in (it adds ~6 GB). All installed agents have access to every security tool in the container. Point an agent at a target, a log file, or a memory dump and let it work.

## Security model

agent-forge is a **host-hygiene boundary**, not a sandbox for adversarial agents. It reduces the blast radius of running powerful tools and AI agents versus doing so directly on your host:

- **Privilege:** `no-new-privileges:true` blocks sudo/setuid escalation; Linux capabilities are dropped to the minimum (`NET_RAW` for packet tooling, `NET_ADMIN` only on the red-team flavor).
- **Resources:** per-container `mem_limit` / `cpus` / `pids_limit` cap a runaway or hostile process (fork bomb, cryptominer).
- **Supply chain:** the [package age gate](#package-age-gate-supply-chain-defense) blocks installs of packages published in the last 7 days.
- **Data:** `.env`, `skills/`, and `workspace/` are gitignored. Do not put live client/engagement data in an internet-connected agent container.

What it does **not** do (yet): contain a genuinely hostile or prompt-injected agent. That needs a VM-per-container boundary (Apple `container` on macOS, gVisor on Linux) plus key brokering with per-session spend caps, both on the roadmap. Treat the agent as trusted-but-fallible, not adversarial.

Hermes ([NousResearch](https://hermes-agent.nousresearch.com)) ships pre-wired to a **local llama.cpp server on your host** — no cloud API key required. See [Local Models](#local-models-ollama--llamacpp) for the one host-side requirement.

## Package Age Gate (Supply Chain Defense)

A runtime safety feature that blocks agents from installing packages published less than 7 days ago. Combats supply chain attacks — typosquatting, dependency confusion, and malicious new-package campaigns.

### How It Works

Wrapper scripts shadow `pip`, `pip3`, and `npm` via PATH ordering. When an agent runs `pip install <package>`, the wrapper:

1. Detects the `install` subcommand (non-install commands like `pip list` pass through untouched)
2. Extracts package names from arguments (handles version pins, extras, `-r requirements.txt`)
3. Queries the package registry API (PyPI or npm) for the publish date
4. Blocks if the package was published less than the threshold (default: 7 days)
5. Logs every decision (allow/block/warn) as JSON to `~/.local/log/package-age-gate.log`

```
Agent runs: pip install some-new-package
                    |
            [wrapper intercepts]
                    |
        [queries PyPI for publish date]
                    |
          Published 2 days ago? --> BLOCKED
          Published 30 days ago? --> ALLOWED
```

### Configuration

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `PACKAGE_AGE_GATE` | `enforce` / `audit` / `off` | `enforce` | Block, warn-only, or disable |
| `PACKAGE_AGE_GATE_THRESHOLD` | integer (days) | `7` | Minimum age in days |

Set in your `.env` file or pass as environment variables:

```bash
# Audit mode — log warnings but allow all installs
docker compose exec -e PACKAGE_AGE_GATE=audit forge bash

# Custom threshold — require packages to be 14+ days old
docker compose exec -e PACKAGE_AGE_GATE_THRESHOLD=14 forge bash
```

### Startup Banner

On container start, the entrypoint displays the current gate status:

```
  Package Age Gate: ENFORCING (blocks packages < 7 days old)
```

### Log Output

Every gate decision is logged as JSON:

```json
{"package": "requests", "manager": "pip", "age_days": 12, "threshold_days": 7, "action": "ALLOWED"}
{"package": "@angular/core", "manager": "npm", "age_days": 3, "threshold_days": 7, "action": "BLOCKED"}
```

View the log: `cat ~/.local/log/package-age-gate.log`

### Allowlist

To bypass the gate for trusted packages, add them to the allowlist:

```bash
# Inside the container
echo "my-internal-tool" | sudo tee -a /usr/local/lib/package-age-gate/allowlist.txt
```

### Modes

| Mode | Behavior | Use Case |
|------|----------|----------|
| `enforce` | Blocks new packages, prints error, exits 1 | Production / default |
| `audit` | Logs warning, allows install to proceed | Monitoring, demos |
| `off` | No checks, immediate passthrough | Debugging, trusted environments |

### Design Decisions

- **Fail-open on timeout** — if the registry API is unreachable (5s timeout), the install proceeds. Agents shouldn't be bricked by network issues.
- **PATH shadowing over pip.conf** — wrapper scripts are inspectable (`cat /usr/local/lib/package-age-gate/wrappers/pip`), making the defense transparent and teachable.
- **Python stdlib only** — `gate.py` uses only `urllib`, `json`, and `datetime`. No additional dependencies.
- **Build-time installs unaffected** — wrappers are installed in the final Dockerfile stage, after all build-time `pip`/`npm` installs complete.

### Known Limitations

- `python3 -m pip install` bypasses the gate (agents rarely use this form)
- `curl | bash` installs are not gated (arbitrary code execution is out of scope)
- `apt-get` is not gated (Debian repos have no per-package publish date API)
- An agent could call `/usr/bin/pip3` directly to bypass (uncommon)

### Inspecting the Gate

```bash
# See what the wrappers do
cat /usr/local/lib/package-age-gate/wrappers/pip

# Test the gate directly
python3 /usr/local/lib/package-age-gate/gate.py pip requests
python3 /usr/local/lib/package-age-gate/gate.py npm express

# Force a block (set absurd threshold)
PACKAGE_AGE_GATE_THRESHOLD=99999 python3 /usr/local/lib/package-age-gate/gate.py pip requests
```

## Build Flavors (vanilla / red / blue)

agent-forge builds from a single, flag-driven `Dockerfile`. The vanilla base (AI agents + recon +
dual-use) is the default; three **independent, opt-in build flags** layer on extra payloads:

| Build arg | Default | Adds | Approx. size added |
|-----------|---------|------|--------------------|
| `INSTALL_HERMES`   | `false` | NousResearch Hermes agent (local llama.cpp) | ~6 GB |
| `INSTALL_REDTEAM`  | `false` | offensive: web exploit, creds, AD, privesc | ~0.8 GB |
| `INSTALL_BLUETEAM` | `false` | DFIR: memory/disk/timeline forensics, malware analysis | ~0.7 GB |

The lean base is **~4.1 GB**; enabling Hermes roughly triples it (it provisions its own Python 3.11
+ ffmpeg), which is why it's opt-in. The flags are independent — combine any subset (e.g. red **+** Hermes).

```bash
# Vanilla base (lean default — agents + recon + dual-use, no Hermes)
docker compose up -d --build && docker compose exec forge bash

# Red team (offensive)
docker compose -f docker-compose.yml -f docker-compose.redteam.yml up -d --build

# Blue team (DFIR)
docker compose -f docker-compose.yml -f docker-compose.blueteam.yml up -d --build

# Hermes (local llama.cpp / llama-swap agent)
docker compose -f docker-compose.yml -f docker-compose.hermes.yml up -d --build

# Stack overlays to combine payloads (e.g. red team + Hermes)
docker compose -f docker-compose.yml -f docker-compose.redteam.yml -f docker-compose.hermes.yml up -d --build

# …or any custom combination via build args
docker build --build-arg INSTALL_REDTEAM=true --build-arg INSTALL_HERMES=true \
  -t agent-forge:red-hermes .
```

> Overlays just flip the corresponding `INSTALL_*` build arg on the single Dockerfile. When stacking
> multiple `-f` overlays, the image tag is taken from the last one listed.

## Tool Inventory

### 🧰 Vanilla base — recon + dual-use (every flavor)

| Tool | Purpose |
|------|---------|
| nmap | Network discovery and port scanning |
| nikto | Web server vulnerability scanning |
| nuclei | Template-based vulnerability scanning (templates self-update) |
| httpx | HTTP probing and technology detection |
| gobuster | Directory and DNS brute-forcing |
| ffuf | Web fuzzing (dirs, parameters, vhosts) |
| subfinder | Passive subdomain enumeration |
| amass | Attack surface mapping and DNS enumeration |
| tshark / tcpdump | Network packet capture and analysis |
| radare2 (`r2`) | CLI reverse engineering framework (dual-use) |
| yara / yara-python | Pattern matching for malware detection (dual-use) |
| binwalk | Firmware and binary analysis (dual-use) |
| exiftool | File metadata extraction (dual-use) |

### 🗡️ Red team overlay — offensive

| Tool | Purpose |
|------|---------|
| sqlmap | SQL injection detection and exploitation |
| hydra | Online password brute-forcing |
| john | Offline password cracking (John the Ripper) |
| hashcat | GPU-accelerated hash cracking |
| impacket | Windows protocol attacks (SMB, WMI, DCOM, Kerberos) |
| certipy-ad | AD Certificate Services exploitation |
| bloodhound-python | AD relationship mapping and attack path analysis |
| netexec | Network service exploitation (successor to CrackMapExec) |
| enum4linux-ng | SMB/LDAP enumeration |
| responder | LLMNR/NBT-NS/mDNS poisoning |
| linpeas / winpeas | Privilege escalation enumeration |

### 🛡️ Blue team overlay — DFIR

| Tool | Purpose |
|------|---------|
| volatility3 (`vol3`) | Memory forensics and analysis |
| sleuthkit | Disk and filesystem forensics |
| foremost | File carving from disk images |
| plaso (log2timeline) | Automated artifact timeline generation |
| chainsaw | Windows event log hunting (Sigma rules) |
| hayabusa | Fast Windows event log analysis |
| sigma-cli | Sigma rule conversion and management |
| oletools | Microsoft Office document analysis |
| flare-floss | Obfuscated string extraction from malware |
| pe-tree | PE file structure analysis |

### Architecture notes (arm64)

A few tools have no clean arm64 (Apple Silicon) install and are skipped fail-soft there; they work
on amd64 class hardware:

- **netexec** (red) — a dependency (`aardwolf`) currently fails to compile on arm64/cpython-3.12.
- **pe-tree** (blue) — optional; may fail to build on arm64.

All other tools, including **hayabusa** (resolved via the GitHub releases API for the correct
arch asset), build on both architectures.

## Local Models (Ollama & llama.cpp)

Run open-source models locally on your host and drive them from inside the container — no cloud API key required. Two paths are wired in:

### OpenCode + Ollama

1. Install Ollama: https://ollama.com
2. Pull a model: `ollama pull qwen3-coder-next:latest`
3. The container auto-detects Ollama at startup via `host.docker.internal:11434`

```bash
# Inside the container
oc "analyze this binary for vulnerabilities"
```

Edit `workspace/opencode.json` to change models.

### OpenCode + NVIDIA NIM (recommended for the labs)

Cloud inference on a free tier, so students can run the agentic labs without an Anthropic key or a
local GPU. This is the default OpenCode backend in the seeded config.

1. Get a free key at [build.nvidia.com](https://build.nvidia.com) (sign in, "Get API Key"). It looks
   like `nvapi-...`.
2. Put it in `.env` as `NVIDIA_API_KEY=nvapi-...` and restart the container (the value flows in via
   `env_file`; it is never baked into the image and `.env` is gitignored).
3. The seeded `opencode.json` already defines the `nvidia` provider and defaults to a strong
   tool-calling model:

```bash
# Inside the container, from any lab directory
oc "analyze examples/suspicious.sh for malicious behavior and extract IOCs"
oc /models                 # switch models interactively
oc -m nvidia/meta/llama-3.3-70b-instruct "..."   # or pick one per run
```

Default model: `nvidia/llama-3.3-nemotron-super-49b-v1.5` (agentic/reasoning-tuned). Alternatives in
the menu: Nemotron Super 49B v1, `meta/llama-3.3-70b-instruct` (very reliable tool calls), and
`nvidia/llama-3.1-nemotron-nano-8b-v1` (fast/cheap). Browse 100+ models at build.nvidia.com.

> Verify your key is valid for **inference**, not just the catalog: `/v1/models` is public and
> returns 200 for anyone, so a 200 there proves nothing. A bad/expired key fails only at the first
> `oc` run with `403 Forbidden: Authorization failed`. Mint a fresh key if you see that.

### Hermes + llama.cpp

[Hermes](https://hermes-agent.nousresearch.com) is pre-configured (`~/.hermes/config.yaml`) to talk to a llama.cpp server on your host via `host.docker.internal:8080/v1`.

1. Start `llama-server` on the host so the container can reach it. The default `127.0.0.1` bind is
   **not** reachable from the container, but `0.0.0.0` exposes your model server to the whole local
   network (a real risk on untrusted/coffee-shop WiFi). Bind as narrowly as your platform allows:

   ```bash
   # Linux — bind to the Docker bridge gateway: container-reachable, NOT exposed to the LAN
   llama-server -m /path/to/model.gguf --host 172.17.0.1 --port 8080

   # macOS / Docker Desktop — 0.0.0.0 is required (no host-bindable bridge IP). Mitigate by keeping
   # the macOS firewall ON (System Settings > Network > Firewall blocks unsolicited inbound) and not
   # running on untrusted networks. Or front it with an SSH/socat tunnel.
   llama-server -m /path/to/model.gguf --host 0.0.0.0 --port 8080
   ```

2. The container probes `host.docker.internal:8080/v1/models` at startup and reports whether Hermes is ready.

3. Use it:

   ```bash
   # Inside the container
   hm "write a YARA rule for this sample"      # hm == hermes
   ```

To change the model name, context size, or endpoint, edit `~/.hermes/config.yaml` (template: `config/hermes-config.yaml`). The model name needs **no provider prefix** for a custom endpoint.

#### Switching Hermes between local and cloud models

`hermes-switch` flips Hermes between the host's local server and cloud APIs (it rewrites the
`model:` block in `~/.hermes/config.yaml`; everything else is left alone). Put `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `NVIDIA_API_KEY`, and `GEMINI_API_KEY` in `~/.hermes/.env`; the local target needs no key.

```bash
hermes-switch local            # host llama.cpp / llama-swap (default model id: qwen3.6-27b)
hermes-switch local my-model   # ...or override the local model id
hermes-switch spark            # DGX (or any) vLLM box over Tailscale (needs the tailscale overlay + DGX_VLLM_URL)
hermes-switch nim              # NVIDIA NIM / build.nvidia.com (free tier)
hermes-switch nim meta/llama-3.3-70b-instruct   # ...or override the NIM model id
hermes-switch gpt              # OpenAI GPT-5.5
hermes-switch gemini           # Google Gemini (AI Studio direct)
hermes-switch gemini gemini-3.1-pro-preview     # ...or override the Gemini model id
hermes-switch opus             # Anthropic Claude Opus 4.8   (1M context)
hermes-switch sonnet           # Anthropic Claude Sonnet 4.6 (1M context)
```

> Gemini model IDs change often (the Gemini 3 Pro Preview was already retired) — the default is the
> GA `gemini-3.5-flash`; confirm/pick a current id at
> [ai.google.dev/gemini-api/docs/models](https://ai.google.dev/gemini-api/docs/models) and pass it
> as the 2nd arg or set `HERMES_GEMINI_MODEL`.

Notes: **NVIDIA NIM** ([build.nvidia.com](https://build.nvidia.com)) offers 100+ models on a free
tier — good for running the labs without burning cloud credits. The default is the small/fast
`nvidia/llama-3.1-nemotron-nano-8b-v1`; for stronger agentic performance pass a larger model (e.g. a
Llama Nemotron Super) or set `HERMES_NIM_MODEL`. 1M context is native to Opus 4.8 / Sonnet 4.6 — no
beta header or special model ID needed; the switcher sets `context_length: 1000000`. The local model
id/URL override via `HERMES_LOCAL_MODEL` / `HERMES_LOCAL_URL`. Changes take effect on the next
`hermes` launch.

## Skills

Skills are **not** shipped in this repo. To use your host PAI / Claude Code skills inside the container, add your own bind mount in `docker-compose.yml` (e.g. `~/.claude/skills:/home/operator/.claude/skills:ro`), or `docker cp` them into a running container.

## Compose Overlays

The base image covers most operations. Overlays add specialized capabilities without bloating the default image.

### Metasploit Framework

```bash
docker compose -f docker-compose.yml -f docker-compose.msf.yml up -d
docker compose exec msf msfconsole
```

### Cloud Security (AWS / Azure / GCP)

Adds cloud provider CLIs (aws, az, gcloud) plus ScoutSuite and Prowler for cloud security assessments.

```bash
docker compose -f docker-compose.yml -f docker-compose.cloud.yml up -d

# Mount your cloud credentials via .env or host config directories
# See .env.example for configuration options
```

### Remote Models over Tailscale

Reach a model server that lives on your [Tailscale](https://tailscale.com) tailnet (e.g. a
workstation or DGX running vLLM) from inside the container, **from anywhere**, including when your
laptop is off the home/lab LAN.

A `tailscale` **sidecar** joins `forge`'s network namespace (`network_mode: service:forge`, the same
pattern as the MSF/cloud overlays). `forge` stays the namespace owner, so it keeps its bridge
network, `host.docker.internal`, and ports (host-local Ollama/llama.cpp keep working) **and** gains
tailnet reachability. The `NET_ADMIN` + TUN privilege lives only on the throwaway sidecar; `forge`
keeps `cap_drop:[ALL]`.

Crucially, this keeps Tailscale **off your host**, so a managed host VPN (e.g. **Cloudflare WARP**)
is left untouched. The sidecar's WireGuard traffic simply egresses through your host's existing
default route. (Your WARP egress policy must allow Tailscale's coordination/DERP: outbound UDP 41641
and 443.)

**On the model server first** (the tailnet peer, e.g. your DGX):

- It must be joined to the same tailnet. `tailscale ip -4` on that box prints its `100.x` address.
- The inference server must listen on the tailnet interface, not just loopback. For vLLM:
  `vllm serve <model> --host 0.0.0.0 --port 8000`. A server bound to `127.0.0.1` is unreachable from
  the tailnet, so the container won't see it.

**Bring up the overlay:**

```bash
# 1. Mint an auth key (ephemeral + tagged recommended): https://login.tailscale.com/admin/settings/keys
# 2. Fill these into .env:
#      TS_AUTHKEY=tskey-auth-...
#      DGX_VLLM_URL=http://<peer-tailnet-ip>:8000/v1      # the peer's 100.x ip, NOT its LAN ip
#      DGX_VLLM_MODEL=Qwen/Qwen3.6-27B-FP8                # optional; the model id the server serves
docker compose -f docker-compose.yml -f docker-compose.tailscale.yml up -d
```

**Verify the link:**

```bash
# the tailscale CLI lives in the SIDECAR. Confirm the mesh is up and the peer is listed:
docker compose -f docker-compose.yml -f docker-compose.tailscale.yml exec tailscale tailscale status

# drop into the workstation and confirm the model endpoint is reachable from forge:
docker compose -f docker-compose.yml -f docker-compose.tailscale.yml exec forge bash
curl -s "$DGX_VLLM_URL/models"     # (inside forge) should return the served model list
```

**Point the agents at it** (inside the `forge` shell):

```bash
hermes-switch spark                # Hermes:  uses $DGX_VLLM_URL / $DGX_VLLM_MODEL, then run: hermes
opencode                           # OpenCode: run /models and pick "DGX Spark vLLM"
```

> **Order matters, and it resets on rebuild.** `hermes-switch` rewrites the per-container
> `~/.hermes/config.yaml`, which is NOT a persistent volume. Any `up --build` (or other recreate)
> starts a fresh container whose `entrypoint.sh` re-seeds that file from the bundled **llama.cpp**
> template (`default: local-llamacpp`, `base_url: host.docker.internal:8080`). So always run
> `hermes-switch spark` **after** the rebuild, in the new container, **before** launching `hermes`.
> Running it on the old container and then rebuilding silently discards the switch.

**Knobs** (all via `.env`): override the endpoint/model with `DGX_VLLM_URL` / `DGX_VLLM_MODEL`, the
tailnet node name with `TS_HOSTNAME`, and extra `tailscale up` flags with `TS_EXTRA_ARGS` (for
example `--advertise-tags=tag:agent-forge`, once that tag is defined in your tailnet ACLs). Node
identity persists in the `tailscale-state` volume across restarts. Stack with other overlays as
usual, e.g. add `-f docker-compose.hermes.yml` to also install the Hermes agent. That overlay sets
the `INSTALL_HERMES=true` **build arg**, so it only takes effect with `--build`: a plain `up` that
adds the overlay to an already-built image will NOT install the `hermes` binary. Full Hermes stack:

```bash
docker compose -f docker-compose.yml -f docker-compose.hermes.yml -f docker-compose.tailscale.yml up -d --build
```

**Troubleshooting:**

- `curl` hangs or connection refused: the server isn't bound to the tailnet (`--host 0.0.0.0`), the
  port is wrong, or the peer is offline.
- `tailscale status` shows an auth error or no peer: a bad/expired `TS_AUTHKEY`, or `TS_EXTRA_ARGS`
  advertised a tag not defined in your ACLs (clear it and re-run `up`).
- Works at home but not remote: confirm your host VPN (e.g. Cloudflare WARP) permits Tailscale egress
  (outbound UDP 41641 and 443).
- `hermes: command not found`: the `hermes` binary is opt-in and was never built into this image. Add
  `-f docker-compose.hermes.yml` AND `--build` (see above). Note `hermes-switch` ships in every image
  regardless, so a working `hermes-switch` does NOT mean `hermes` is installed.
- Hermes launches but the banner reads `local-llamacpp` and you get `APIConnectionError on custom`:
  the config was reseeded to the llama.cpp template by a rebuild. Re-run `hermes-switch spark` in the
  current container, then verify with `grep -A4 '^model:' ~/.hermes/config.yaml` (the `base_url` must
  be your peer's `100.x:8000`, not `host.docker.internal:8080`), then launch `hermes`. To make the
  Spark config survive rebuilds, mount a named volume at `/home/operator/.hermes` or change the
  template default in `config/hermes-config.yaml`.

### Combining Overlays

```bash
# Full stack: base + MSF + cloud
docker compose \
  -f docker-compose.yml \
  -f docker-compose.msf.yml \
  -f docker-compose.cloud.yml \
  up -d
```

## Architecture

- **Base:** Ubuntu 24.04 (noble)
- **Runtimes:** Node.js 20 LTS, Python 3.12, Go tools (compiled in build)
- **User:** `operator` (UID 1000, passwordless sudo)
- **Multi-arch:** x86_64 + arm64
- **Networking:** Bridge mode by default, `host.docker.internal` for Ollama access
- **Workspace:** `./workspace` mounted at `~/workspace` — shared between host and container

### Build Stages

A single `Dockerfile` builds every flavor; the opt-in payloads are gated `RUN` blocks controlled by
the `INSTALL_HERMES` / `INSTALL_REDTEAM` / `INSTALL_BLUETEAM` build args.

1. **go-builder** — Compiles Go recon tools (gobuster, ffuf, nuclei, httpx, subfinder, amass)
2. **base** — Ubuntu 24.04 with system packages and runtimes
3. **ai-agents** — Claude, OpenCode, Codex (always); Hermes if `INSTALL_HERMES=true`
4. **base-tools** — Recon + dual-use (nmap, nikto, radare2, yara, binwalk, exiftool, Go binaries); red/blue payloads if their flags are set
5. **final** — Non-root user setup, package age gate, workspace, entrypoint

> **Image size note (measured):** the lean vanilla base is **4.14 GB**. The Hermes agent is the
> single biggest payload (~6 GB — it provisions its own Python 3.11 + ffmpeg), which is why it's
> opt-in; red adds ~0.8 GB and blue ~0.7 GB. Build only the flags you need.

### Versioning & Reproducibility

Pinning is deliberate, not blanket:

- **Pinned** for reproducible builds: base images (by digest/patch tag), the Go security tools, the
  AI CLI agents (`codex`, `ai-sdk`). Bump these
  intentionally.
- **Tracks latest** on purpose: `chainsaw`, `hayabusa`, and `PEASS-ng` bundle detection rules /
  privesc checks that you want current, and `nuclei`'s templates self-update at runtime (the binary
  is pinned). Freezing these would silently weaken coverage. Pin them only if you need
  audit-grade reproducibility, and bump on a schedule.

## Pull from Docker Hub

```bash
docker pull deruke/agent-forge:latest
```

## Build Locally

```bash
# Vanilla base (lean default)
docker build -t agent-forge:base .

# Flavored builds via opt-in flags (combine any subset)
docker build --build-arg INSTALL_REDTEAM=true  -t agent-forge:redteam  .
docker build --build-arg INSTALL_BLUETEAM=true -t agent-forge:blueteam .
docker build --build-arg INSTALL_HERMES=true   -t agent-forge:hermes   .
docker build --build-arg INSTALL_BLUETEAM=true --build-arg INSTALL_HERMES=true \
  -t agent-forge:blue-hermes .

# Multi-arch base (push to registry)
docker buildx create --name forge-builder --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t deruke/agent-forge:base \
  --push .
```

## License

Released under the [MIT License](LICENSE) — free to use, modify, and redistribute, including for
your own training and engagements. See [CONTRIBUTING.md](CONTRIBUTING.md) to contribute.
