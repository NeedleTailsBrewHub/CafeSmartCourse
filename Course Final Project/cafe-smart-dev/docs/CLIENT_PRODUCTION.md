# CafeSmartDev client — production readiness

Teaching/final client runbook (Skip macOS + iOS + Android) against `Course Final Project/cafe-smart-api`. Mirrors the Production client hardening pass with intentional course cuts noted below.

## API host matrix

| Target | DEBUG host (default) | Notes |
|--------|----------------------|--------|
| Mac / iOS Simulator | `127.0.0.1` | HTTP `:8080`, WS `:8081` |
| Android emulator | `10.0.2.2` | Cleartext DEBUG via `network_security_config` |
| Physical device | **set `CAFE_API_HOST`** | LAN IP or DNS |
| Release | **require `CAFE_API_HOST`** | No silent loopback |

## Auth & admin bootstrap

- Registration sends `isAdmin: false`; server promotes via `ADMIN_USERNAMES`.
- Session restore from refresh token; merchant WS only for admins.
- Sign-out clears tokens, disconnects WS, resets banners.

## Mac vs mobile ML

Same split as Production: server train + Inventory restock on all platforms; Create ML / Models admin stay Mac-only. `AIService` is not gated on CoreML.

## Intentional course cuts

Compared with a full merchant product, this teaching app still omits or hides unfinished surfaces:

- Peak times, Reports, Team, Reservations destinations that were empty stubs
- Reserve / Support flows without real Confirm/Submit backends
- Demo “Top selling” blocks
- Full multi-role RBAC beyond admin vs customer

Students should treat Inventory / Menu / Orders / server Train / Mac Models as the supported path.

## Reliability

- WS drain: FIFO, `continue` on nil data, `defer` clears `isRunning`
- Checkout: one HTTP create + best-effort WS notify
- Order status: **PUT** (not PATCH)

## Verification checklist

- [ ] Android emulator → Mac API via `10.0.2.2`
- [ ] Admin Train on mobile uses server + capabilities
- [ ] Android links ungated `AIService`
- [ ] No blank Home destinations for visible tiles
- [ ] Inventory edit sheet usable; restock hints from WS
- [ ] Signup non-admin unless allowlisted; Mac merchant UI admin-gated
- [ ] Cancel order PUT succeeds for admin
