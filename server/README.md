# Expense Manage — isolated self-hosted backend scaffold

This is a **starter**, not a production-ready expense sync API. It only provides
`GET /health` with a PostgreSQL connectivity check. Authentication, migrations,
per-user authorization, expense CRUD, offline sync, backups and TLS remain to be built.

## Isolation from Choudhary & Sons

- Docker Compose project name: `expense-manage`
- Database is **not published** to the host or internet.
- API is bound only to host loopback port `18081`.
- Own named volume and private Docker network.
- No commands to stop, prune, reset or change existing Docker projects.

## Server installation (not yet executed)

Clone the repository to an independent directory, e.g.
`/home/nouman/expense-manage`, then enter its `server` directory.
Copy `.env.example` to `.env` and replace the placeholder with a
cryptographically random password. Do not commit the secret.
Run `docker compose config` to validate before starting, then
`docker compose up -d --build` after confirming port 18081 is free.
Check `curl -fsS http://127.0.0.1:18081/health`.

**Do not connect Flutter to this service yet.** The existing Flutter app uses
Supabase and must keep working until authenticated API endpoints, migration,
and safe client sync are ready. For remote access use an authenticated TLS
reverse proxy or a carefully configured Tailscale path; do not expose the
PostgreSQL port.
