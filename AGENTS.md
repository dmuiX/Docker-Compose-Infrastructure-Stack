# AGENTS.md

Repository guidance for AI/code assistants.

## Project

Docker Compose homelab stack — infrastructure services running on a single host managed by OpenMediaVault.

Main technologies:

- Docker Compose (one stack per service folder)
- SWAG (reverse proxy + Let's Encrypt via Cloudflare DNS)
- Authelia (SSO / OIDC, backed by Samba-DC)
- Samba-DC (Active Directory domain controller on macvlan)
- Pi-hole + Unbound (local DNS)
- Docker socket proxy (dockerproxy)

## File Structure

```
<service>/
  <service>.yml     – Docker Compose file
  <service>.env     – Env vars (gitignored, never commit)
  .env              – Additional env vars (gitignored)
  config/           – Service-specific config files (where applicable)
  secrets/          – Secret files mounted into containers (gitignored)

1-swag/
  custom-proxies/   – Custom nginx proxy configs
  cloudflare.ini    – Cloudflare API credentials (gitignored)

authelia/
  config/configuration.yml  – Authelia config (example, adjust domain.org references)
  secrets/                  – Secret files (gitignored, generate with openssl)
  add-client.sh             – Register a new OIDC client
  inspect-oidc-userinfo.sh  – Debug OIDC user info

samba-dc/
  dns-records               – DNS entries to import
  import-dns-records.sh     – Import script
  samba_admin_pass          – Docker secret file (gitignored, generate with openssl)
```

## General Principles

- Prefer editing existing files over creating new ones.
- Keep Compose files clean — one service concern per file.
- No new dependencies without a clear reason.

## Rules

- **Never read, edit, or commit `.env` files** — they are gitignored and contain secrets.
- Never hardcode IPs, tokens, or passwords in committed files.
- All secrets go into dedicated secret files (e.g. `authelia/secrets/`) — never inline them.
- `authelia/config/configuration.yml` uses `domain.org` as placeholder — that is intentional.
- External Docker networks (`swag`, `dockerproxy`, `macvlan0`) must exist on the host — do not define them inline.
- `TZ`, `PUID`, `PGID` are injected globally by OMV — do not add them to `.env` files.

## Gitignored Files (never force-add)

- All `*.env` / `.env` files
- `1-swag/cloudflare.ini`
- `samba-dc/samba_admin_pass`
- `authelia/secrets/**`

## What Not To Do

- No broad rewrites — small focused edits only.
- No `--no-verify` on git commits.
- No hardcoded secrets in any committed file.
- Do not touch `.env` files — ignore them entirely.
