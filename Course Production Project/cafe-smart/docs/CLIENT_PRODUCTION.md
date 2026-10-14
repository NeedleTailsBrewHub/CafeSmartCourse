# CafeSmart client — production readiness

Runbook for the Skip dual-platform client (macOS + iOS + Android) against `cafe-smart-api`.

## API host matrix

| Target | DEBUG host (default) | Notes |
|--------|----------------------|--------|
| Mac / iOS Simulator | `127.0.0.1` | HTTP `:8080`, WS `:8081` (cleartext unless `CAFE_API_TLS=1`) |
| Android emulator | `10.0.2.2` | Maps to host loopback; cleartext allowed via `network_security_config` in DEBUG |
| Physical device | **set `CAFE_API_HOST`** | LAN IP or DNS of the API machine |
| Release | **require `CAFE_API_HOST`** | No silent loopback; unset → `api.invalid.local` + console warning; **HTTPS + WSS required** |

Override via process environment or Info.plist key `CAFE_API_HOST`. Optional: `CAFE_API_HTTP_PORT`, `CAFE_API_WS_PORT`, `CAFE_API_TLS=1` (DEBUG only — use a trusted/dev cert on the API).

API production TLS: mount PEMs and set `API_LOCAL_FULL_CHAIN` / `API_LOCAL_PRIV_KEY` (see API `scripts/gen-dev-certs.sh` and README).

## Shell matrix (signed-in)

| Device | Admin | Shell |
|--------|-------|-------|
| Mac | yes | `BusinessHomeView` NavigationSplitView |
| iPad (`UIUserInterfaceIdiom.pad`) | yes | `BusinessHomeView` NavigationSplitView |
| iPhone / other | yes | `HomeView` + Merchant tools section |
| Any | no | `HomeView` customer chrome |

Gating: `BusinessShellPolicy.usesSplitShell(isAdmin:idiom:)` (unit-tested).

## Auth & admin bootstrap

- Client registration always sends `isAdmin: false`.
- Server grants admin when the email is listed in API `ADMIN_USERNAMES`.
- Cold start restores session from Keychain refresh token → `didSignIn` → merchant WebSocket **only if** `user.isAdmin`.
- Sign-out clears tokens, disconnects merchant WS, and resets in-app banners.
- Profile **Delete account** calls `DELETE api/auth/account` (not local-only).

## Menu CMS (source of truth)

Admin **Menu** screen supports create / edit / delete (name, description, category, price, availability, sizes, allergens, prep).
Empty Mongo is valid — publish a catalog from the CMS.

**Demo UI (server-driven):** after login the client calls `GET api/auth/runtime`. Admin “Load demo café data” appears **only when `demoMode` is true** (DEBUG API + `SEED_TEST_DATA=true`). Release API always returns `demoMode: false`, so production clients never show demo affordances. Seed action hits `POST api/auth/debug/seed` (DEBUG API only).

## Catalog version + image cache

| Concern | Client behavior |
|---------|-----------------|
| Menu list | In-memory paged `MenuViewModel.items` only (not a full offline catalog dump) |
| `catalogVersion` | Persisted as `lastCatalogVersion`; compare on WS `.catalogVersion`, app resume, and list fetch |
| Stale UX | Banner **“Menu updated — Tap to refresh”** on Menu CMS; guest Order flow auto-refreshes when stale |
| After refresh | `fetchMenu(reset: true)` adopts `PaginatedMenuItems.catalogVersion` |
| Admin mutations | Upload/clear/save adopt latest server version so the editor is not interrupted by its own bump |
| Images | Opaque `imageURL` (HTTPS media host or local `/menu-images/…`); never build R2 URLs; never send Bearer on image GET |
| Image cache | `AsyncImage` + shared `URLCache` (32MB memory / 256MB disk); keyed by full URL — new upload → new URL → fetch |
| Admin photo | Edit existing item → PhotosPicker / file import → `POST …/menu/:id/image`; Clear → `DELETE …/image` |

Staging check: change a photo on one device → other client sees stale banner (or auto-refresh on Order) → new image loads under the new URL.

## Ordering loop

| Role | Capability |
|------|------------|
| Customer | Browse menu → Add to order / Order now → cart with sizes → ASAP or pickup time → **pay at pickup** place order → My orders (cancel pending) |
| Customer | Reserve a table (wired to reservation API) |
| Merchant | **Orders board** — pending → preparing → ready → completed; cancel |
| Merchant | Inventory, Menu CMS, Reservations list, server train / Mac Models |

Orders are scoped: non-admins see only their orders (`customerUserId`). Status PUT allows admin any transition; customers may cancel **own pending** only.
API publishes `MessagePacket.order` on create/update to merchant WS.

## Mac vs mobile ML

| Capability | macOS | iOS / Android |
|------------|-------|----------------|
| Server train (`POST …/predictor/train`) | Yes | Yes (Home “Train on server”, gated by `GET …/predictor/capabilities`) |
| Local Create ML → CoreML upload | Yes (Models admin / toolbar) | No |
| Models admin console | Yes (`ModelsAdminView`) | Hidden (Mac-only) |
| Restock decisions | Inventory row hints + summary toast (WS `.restockDecisions`) | Same |

`AIService` compiles without CoreML so Android can call train/list/activate/delete/restock/capabilities.

## Support tickets

- Customer: Settings → Help & support — composer + optional related orders; **Archive** / **Remove** hide from the guest inbox only (`POST …/archive` or `DELETE`) via `hiddenByCreatorAt` — admin desk still sees the ticket.
- Linked orders: `relatedOrderIds` on create; chips show `#` + first 6 of order id; tap opens order peek sheet.
- Admin: Operations → Support desk — filters include **Guest archived**; trash/delete forever work on guest-archived tickets; order chips open the same peek sheet.
- API tests: `SupportTicketTests`. Client: `BusinessShellPolicyTests`, `SupportTicketLogicTests`.

## Payments (Stripe prepaid + pay-at-pickup)

Unified checkout — one cart encoder, two settle modes:

| Mode | Platforms | Path |
|------|-----------|------|
| Pay at pickup | iOS, Android, Mac | `POST /api/auth/orders` with `paymentMode=payAtPickup` |
| Pay now (prepaid) | iOS + Android only | `prepare` → skip-stripe PaymentSheet → `confirm(sessionId)` |

- Client gates **Pay now** on `GET /api/auth/checkout/capabilities` → `prepaidEnabled` (ops kill switch + Stripe keys + merchant `BusinessConfig.prepaidPaymentsEnabled`).
- Client gates **Pay at pickup** on capabilities → `payAtPickupEnabled` (merchant `BusinessConfig.payAtPickupEnabled`; default on).
- Mac never shows Pay now (PaymentSheet / skip-stripe is mobile). With pay at pickup off, Mac guests cannot check out.
- Publishable key comes only from prepare response; secret key stays on the server.
- Admin toggles: Rewards & payments → **Accept pay at pickup (in person)** and **Accept in-app card & wallet payments** (in-app toggle disabled in UI when `prepaidAvailable` is false).
- Client logic tests: `CheckoutPaymentCoordinatorTests`.

### Apple Pay / Google Pay checklist

1. Stripe Dashboard → Payment methods: enable Cards, Apple Pay, Google Pay.
2. **Apple Pay:** Apple Developer → Merchant ID; Xcode capability **Apple Pay**; register merchant ID in Stripe; add domains if using web (native sheet uses merchant ID in Stripe iOS SDK / PaymentSheet).
3. **Google Pay:** Enable in Stripe Dashboard; Android app needs Play Services; test with Stripe test cards / Google Pay test environment.
4. Env on API: `PAYMENTS_ENABLED=1`, `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_CURRENCY`, `STRIPE_MERCHANT_COUNTRY`.
5. Point Stripe webhook to `POST /api/webhooks/stripe` (same fulfill as confirm).

## Reports (admin)

| Endpoint | Client use |
|----------|------------|
| `GET api/auth/reports/summary?from=&to=` (ISO8601) | Finance KPIs: gross / net / tax / loyalty / COGS / labor / contribution |
| `GET api/auth/reports/demand?days=` | Busyness heatmap/peaks/staffing + stock outlook spend |

UI: Operations → **Reports** — Today / WTD range picker, demand source label, stock outlook rows, compact floor snapshot (open tickets / low stock).

Cost inputs for accurate reports:

- Inventory `costPerUnitCents` (edit sheet) → COGS + predicted restock spend
- Team `hourlyRateCents` (roster edit, dollars in UI) → labor cents

Server train kinds from Models admin / Train menu: `restockDaily`, `workloadHourly`, `reservationsHourly` (local Create ML remains restock-only).

## Hidden / deferred UI

- Tips, Connect, receipts, push — deferred
- Android tablet business split shell (iPad idiom is the gate for this pass)

## Loyalty

Profile shows points/tier when `GET api/auth/loyalty/:userId` returns an account; otherwise a short “ask staff to enroll” note.

## Reliability notes

- WebSocket drain uses FIFO + `continue` on nil binary (never stalls `isRunning`).
- Checkout: pay-at-pickup via `createOrder`; prepaid via prepare/confirm (session snapshot); merchant toast via API `MessagePacket.order`.
- Order status updates use **PUT** `api/auth/orders/:id/status`.

## Verification checklist

- [ ] Empty Mongo + admin CMS: add item → customer sees it → place order → Orders board advances to ready
- [ ] `GET api/auth/runtime` → demo UI only when `demoMode`; DEBUG + `SEED_TEST_DATA=true` shows “Load demo café data”; Release API always `demoMode: false`
- [ ] Customer My orders shows only own orders; cancel pending works; non-pending cancel hidden/fails safely
- [ ] Browse menu “Add to order” opens Order flow with item prefilled
- [ ] Reserve a table Confirm creates a reservation
- [ ] Profile password change + real delete account
- [ ] Android emulator login via `10.0.2.2` + cleartext DEBUG
- [ ] iOS Simulator login; admin Train uses server path; respects capabilities / 503
- [ ] Mac Models activate/delete/train still work after AIService split
- [ ] Merchant WS toast on new/updated order
- [ ] Prepaid off by default: checkout shows only Pay at pickup; prepare returns 503
- [ ] Ops keys + merchant toggle: Pay now on iOS/Android; Mac stays pay-at-pickup
- [ ] Stripe test card PaymentSheet → confirm → order `paymentStatus=paid`
- [ ] Stripe webhook `payment_intent.succeeded` fulfills once (replay safe)
- [ ] Cancel pending prepaid order refunds PaymentIntent
- [ ] Apple Pay / Google Pay on device when Dashboard + merchant ID configured

## VenueSmartKit

CafeSmart consumes `VenueSmartKit` for Core + Realtime + Merchant UI.

- Local bootstrap: `.package(path: "../VenueSmartKit")`
- Production: `.package(url: "https://github.com/needletails/VenueSmartKit.git", from: "0.1.0")`

WebSocket connect/decode/routing lives in `VenueSmartRealtimeClient`. Guest order/reserve/support views remain in this host.
