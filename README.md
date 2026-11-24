# كراج خالد (Karaj Khaled)

Arabic/RTL classifieds marketplace demo (cars, phones, car parts, accessories, real estate, plates).

## Architecture

- **Frontend**: a single self-contained `index.html` (vanilla JS, no build step, no framework).
- **Hosting**: GitHub Pages, served from the `main` branch root.
- **Backend**: [Supabase](https://supabase.com) (Postgres + Auth + Storage), project ref `rqailwsjdhsmkajkvkpn`. Client-side `SUPABASE_URL`/`SUPABASE_KEY` constants near the top of the inline `<script>` — the key is the public `anon`/publishable key, safe to expose (access is enforced by Postgres Row Level Security policies, not by hiding the key).
- **Link previews**: a Cloudflare Worker (`karaj-khaled-preview`, deployed separately from this repo — see below) serves Open Graph tags to crawlers (WhatsApp/Telegram/Facebook/etc.) and redirects real visitors to the site.
- **Keep-alive**: `.github/workflows/keep-supabase-alive.yml` pings the Supabase REST API daily so the free-tier project doesn't auto-pause from inactivity.

## Local development

No build step — just open `index.html` in a browser, or serve it locally:

```bash
python3 -m http.server 8000
```

Then visit `http://localhost:8000`.

## Before every push

Two scripts, both run automatically in CI (`.github/workflows/verify.yml`) on every push and pull request — but worth running locally first so a broken push never reaches `main`:

```bash
pip3 install esprima playwright
python3 -m playwright install --with-deps chromium   # once

python3 scripts/verify.py        # static checks: duplicate ids, dangling getElementById(), JS syntax
python3 scripts/smoke_test.py    # functional check: loads the real page in a headless browser,
                                  # opens a listing and the login modal, fails on any console/JS error
```

`smoke_test.py` is a real regression test, not just a linter — it would have caught the `.rpc().catch()` bug that once silently broke the entire listing-detail modal (see the project memory notes from 2026-09-22) before it ever reached production.

## Deploying

Pushing to `main` is a live production deploy — GitHub Pages serves whatever is on `main` directly, with no staging step in front of it yet (see "Known gaps" below).

```bash
git add -A
git commit -m "describe the change"
git push
```

## Staging vs. production (local testing only for now)

`index.html` loads an optional `config.local.js` (gitignored, never committed — see `config.local.js.example`) right before the main script. If present, it overrides `SUPABASE_URL`/`SUPABASE_KEY` for your local copy only; production (GitHub Pages) never has this file, so it always falls back to the real production constants hardcoded in `index.html`.

```bash
cp config.local.js.example config.local.js
# edit config.local.js with the staging project's URL/key
python3 -m http.server   # serve locally — now talking to staging, not production
```

This means local testing can already point at a separate Supabase project instead of touching production data. **The staging Supabase project itself still needs to be created** (requires logging into the Supabase dashboard) — until then, `config.local.js` has nowhere real to point yet.

## Known gaps / next steps

- **Staging Supabase project not created yet** — the config-override mechanism above is ready, but needs an actual second Supabase project to point at.
- **Cloudflare Worker is deployed manually**, not tracked in this repo. Its source should eventually live here too.
- **No hosted staging URL** — staging is local-only (`config.local.js` + `python3 -m http.server`) for now. A real staging deployment (e.g. a second GitHub Pages repo, or Cloudflare Pages preview branches) is future work if that becomes worth the complexity.

## External accounts this project depends on

- **Supabase** — database, auth, storage, RLS policies. Dashboard: https://supabase.com/dashboard/project/rqailwsjdhsmkajkvkpn
- **GitHub Pages** — static hosting for this repo.
- **Cloudflare Workers** — `karaj-khaled-preview` worker for rich link previews.

Whoever owns the production business should hold these accounts; collaborators should get scoped access rather than full ownership.
