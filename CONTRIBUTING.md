# Contributing to agent-forge

agent-forge is a teaching platform for the "Agentic AI for Security Operators" course. Contributions
that improve clarity, safety, or the lab experience are welcome.

## Ground rules

- **Never commit secrets or engagement data.** `.env`, `skills/`, and `workspace/` are gitignored
  for a reason — they can hold API keys and real client data. Do not force-add them. CI runs a
  secret scan (see `.github/workflows/secret-scan.yml`) on every push and PR.
- **Keep the image lean.** The base image targets a few GB. Heavy or niche tools belong in a
  compose overlay (see `docker-compose.*.yml`), not the base `Dockerfile`.
- **Pin for reproducibility, track latest for detections.** Runtimes, language tools, and the AI
  CLIs are version-pinned. Detection-content tools (chainsaw, hayabusa, PEASS, nuclei templates) are
  intentionally on latest — keep it that way unless you have an audit reason to pin.

## Workflow

1. Branch from `main`.
2. Make your change. If you touch the `Dockerfile`, build it: `docker build -t agent-forge .`
3. If you add a tool, document it in `README.md` and confirm it responds to `--version`/`--help`
   inside the container.
4. Open a PR with a short description of what changed and why.

## Local setup

```bash
git clone <your-fork-url> && cd agent-forge
cp .env.example .env        # fill in any API keys you want (all optional)
docker compose up -d --build
docker compose exec forge bash
```

## Reporting issues

Open a GitHub issue with the command you ran, the expected result, and what actually happened.
Do not paste real client data, credentials, or scan output from live engagements.
