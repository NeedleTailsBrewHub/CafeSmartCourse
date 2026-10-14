## CafeSmart API

Vapor (Swift) API for cafe operations: orders, menu, inventory, reservations, recipes, loyalty, realtime, metrics, and ML predictions.

### Prerequisites

- Swift 6.0+
- macOS 14+ or Ubuntu Noble
- MongoDB 6+
- Docker (optional)

### Setup in 60 seconds

1) Clone
```bash
git clone <your-repo>
cd cafe-smart-api
```
2) Configure env
```bash
cp env.example .env
source .env
```
3) Run
```bash
swift run cafe-smart-api serve --env development --hostname 0.0.0.0 --port 8080
```
Server: http://localhost:8080

### Environment variables

Create a `.env` file in the project root (copy from `env.example`). The following variables are required:

**Required:**
- `MONGO_URL`: MongoDB connection URI, e.g. `mongodb://localhost:27017/cafesmart`. If unset and `USE_TEST_STORE=true`, uses in-memory store.
- `MLDSA_SEED`: Post-quantum JWT (MLDSA87) seed — **exactly 32 bytes**, or 64 hex characters. `HMAC_SECRET` is accepted as a temporary fallback with the same length rule.
- `CORS_ALLOWED_ORIGIN`: Required in production (e.g. `https://app.example.com`). Development allows all origins.
- `ADMIN_USERNAMES`: Comma-separated admin email addresses for admin access.

**Optional:**
- `USE_TEST_STORE`: Set to `true` to use in-memory store (no MongoDB required). Useful for testing.
- `LOG_LEVEL`: Logging level (e.g., `debug`, `info`, `warning`, `error`).

**Prepaid / Stripe (optional):**
- `PAYMENTS_ENABLED`: Ops kill switch (`1`/`true`/`yes`). Off by default.
- `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`: All required for `prepaidAvailable`.
- `STRIPE_CURRENCY` (default `usd`), `STRIPE_MERCHANT_COUNTRY` (default `US`).
- `STRIPE_EPHEMERAL_KEY_API_VERSION`: Must match skip-stripe / stripe-ios (default `2020-08-27`).
- **Stripe Tax:** `STRIPE_TAX_ENABLED` (default on). Set `STRIPE_TAX_ADDRESS_*` (café/pickup location) and enable Tax + registrations in the Stripe Dashboard. Prepare runs Tax Calculations and charges `amount_total`; tax transaction is recorded on fulfill.
- Merchant must also set `BusinessConfig.prepaidPaymentsEnabled = true` (admin config upsert).
- Pay at pickup defaults on; set `BusinessConfig.payAtPickupEnabled = false` to require in-app Pay now (`POST /orders` → 403).
- Effective gate: `PaymentsPolicy.prepaidEnabled` = ops + keys + webhook secret + merchant toggle.
- Routes: `GET /api/auth/checkout/capabilities`, `POST …/checkout/prepare`, `POST …/checkout/confirm`, public `POST /api/webhooks/stripe`.
- Fulfill is atomic (`pending`→`fulfilling`→`fulfilled`); confirm + webhook share one path; fulfill failure refunds PI and marks session `failed`.
- Cancel of a pending **paid** prepaid order refunds the PaymentIntent.
- `POST /api/auth/orders` is **pay-at-pickup only** (`paymentMode=prepaid` → 400).
- Docker run image installs `libcurl4` for Stripe `URLSession` on Linux.
- Tests: `swift test --filter PaymentTests` (FakeStripe; no live Stripe in CI).

**Reports / demand (admin):**
- `GET /api/auth/reports/summary?from=&to=` — net sales = **completed + paid** − loyalty; COGS from recipes on **completed** tickets; labor from approved hours; contribution = net − COGS − labor. Completing a pay-at-pickup order marks it paid.
- `GET /api/auth/reports/orders?from=&to=` — order-level finance rows (UI drill-down; capped).
- `GET /api/auth/reports/export?from=&to=&dataset=` — accounting CSV (`summary` | `byDay` | `orders` | `salesByItem` | `cogsBySku` | `labor`). Money columns are decimal currency (not cents). Export is uncapped for the range.
- `GET /api/auth/reports/demand?days=` — busyness heatmap/peaks + **staffingByDay** (people + person-hours by day/hour) + stock outlook $.
- Inventory `costPerUnitCents` and team `hourlyRateCents` feed COGS/labor; prepaid fulfill persists `Order.taxCents`.
- Tests: `swift test --filter ReportsInsightsTests` and `DemandMLTests`.

**ML training (dual path):**
- Server: `POST /api/auth/predictor/train` `{ kind }` → Python ONNX (`restockDaily` / `workloadHourly` / `reservationsHourly`).
- Local Mac: Create ML from export CSV → upload `runtime=coreml`.
- Export datasets: `ingredientDaily`, `ordersHourly`, `reservationsHourly`.
- Docker copies all `Trainer/*.py`; kind selects script (`train_restock.py`, `train_busy_hour.py`, `train_reservations_hour.py`).

**TLS (HTTP + WebSocket):**
- Required when running `--env production`. Optional in development when both are set.
- `API_LOCAL_FULL_CHAIN`: Full-chain PEM (absolute or relative to working directory).
- `API_LOCAL_PRIV_KEY`: Private key PEM.
- Same certs secure Vapor HTTPS (`HTTP_PORT`, default 8080) and CMK WSS (`WS_PORT`, default 8081).
- Local self-signed: `./scripts/gen-dev-certs.sh` then set the two env vars to `certs/…`.
- Production: use Let's Encrypt (or your CA) fullchain + privkey; mount into the container at `/certs`.

**Metrics (optional):**
- `CAFE_METRICS_COLLECTION`: MongoDB collection name for metrics (default: `cafe_metrics`).
- `CAFE_METRICS_FLUSH_SECONDS`: Metrics flush interval in seconds (default: `43200`).
- `CAFE_METRICS_MAX_BATCH`: Maximum batch size for metrics (default: `512`).
- `CAFE_METRICS_MAX_WRITE_BYTES`: Maximum write bytes per batch (default: `10000000`).
- `CAFE_METRICS_MAX_WRITE_COUNT`: Maximum write count per batch (default: `1000`).

**Catalog media (R2) + catalogVersion:**
- Admin `POST /api/auth/menu/:id/image` uploads bytes → PutObject (R2 in production, Fake/Local in test/dev) → new absolute `imageURL` + `imageMediaKey` on the item. `DELETE …/image` clears and deletes the object.
- Each upload allocates a **new UUID key** so clients cache-bust by URL. PutObject sets `Cache-Control: public, max-age={MEDIA_CACHE_MAX_AGE_SECONDS}` (default `3600`).
- Production boot **requires** `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_PUBLIC_BASE_URL`. Optional: `R2_ENDPOINT`, `R2_REGION`, `MEDIA_ALLOWED_HOSTS`, `MEDIA_MAX_UPLOAD_BYTES`, `MEDIA_MAX_PIXELS`, `MEDIA_CACHE_MAX_AGE_SECONDS`.
- Monotonic **`catalogVersion`** (Mongo `CatalogMeta` id `menu`) bumps on every menu-affecting write: create, update, archive, bulk, CSV import, image upload/clear. Exposed via `GET /api/auth/menu/catalog-version`, `PaginatedMenuItems.catalogVersion`, and WS `MessagePacket.catalogVersion` to customer + merchant topics.

**Demo / test data (DEBUG only):**
- Menu catalog in product use comes from the admin Menu CMS (create/update/delete). Empty Mongo is valid.
- `SEED_TEST_DATA`: When `true` in a **DEBUG** binary, auto-seeds `DemoCafeSeed` if inventory is empty, and `GET /api/auth/runtime` returns `demoMode: true`. **Ignored in Release**. Admin: `POST /api/auth/debug/seed` (empty only) or `POST /api/auth/debug/reseed` (wipe + reload).
- Optional history knobs (defaults match a quieter neighborhood café): `DUMMY_DAYS_BACK` (`90`), `DUMMY_BASE_ORDERS_MIN` (`2`), `DUMMY_BASE_ORDERS_MAX` (`5`), `DUMMY_MAX_ITEMS_PER_ORDER` (`3`).

### Running from Xcode

When running the Vapor server from Xcode, you must configure the working directory:

1. Open the Xcode scheme editor (Product → Scheme → Edit Scheme...)
2. Select the "Run" configuration
3. Go to the "Options" tab
4. Set "Working Directory" to the project root directory (where the `.env` file is located)
5. Alternatively, set "Use Custom Working Directory" and specify the full path to the project root

**Important:** The server uses relative paths for:
- Reading the `.env` file
- Accessing ML model files in `Models/` directory
- TLS certificate files (if configured)

Without the correct working directory, the server may fail to find these resources.

### Docker

Production image expects TLS PEMs. Generate local certs (or mount real ones), then:

```bash
./scripts/gen-dev-certs.sh
export MLDSA_SEED="replace-with-32-byte-or-64-hex-seed!!"
docker compose up --build app
```

Or manually:
```bash
docker build -t cafesmart-api:latest .
docker run --rm -p 8080:8080 -p 8081:8081 \
  -v "$(pwd)/certs:/certs:ro" \
  -e MONGO_URL="mongodb://host.docker.internal:27017/cafesmart" \
  -e MLDSA_SEED="replace-with-32-byte-or-64-hex-seed!!" \
  -e ADMIN_USERNAMES="admin@example.com" \
  -e CORS_ALLOWED_ORIGIN="https://localhost" \
  -e API_LOCAL_FULL_CHAIN="/certs/fullchain.pem" \
  -e API_LOCAL_PRIV_KEY="/certs/privkey.pem" \
  cafesmart-api:latest
```

### Tests

```bash
swift test
```

### Endpoints (overview)

- Auth, Menu/Inventory CMS, Orders (scoped list; status with ownership rules), Checkout (prepaid Stripe), Reservations, Recipes, Loyalty
- Tag taxonomy, cursor-paginated lists, bulk/CSV, audit (see below)
- `GET /api/auth/runtime` — `{ demoMode }` for client UI gating (DEBUG + `SEED_TEST_DATA=true` → true; Release → always false)
- DEBUG only: `POST /api/auth/debug/seed` (admin) — demo café bootstrap (+ Allergens tag migration)
- Predictor: export, model upload/list/activate/instantiate, restock decide, capabilities, **train**
- WebSockets: ConnectionManagerKit on `WS_PORT` (merchant topic for order/inventory/ML events)

See `docs/Predictions.md` for ML details.

### List APIs (cursor pagination + search)

All major list GETs return `{ items, page: { nextCursor, hasMore, limit } }` (not unbounded arrays).

| Param | Meaning |
|-------|---------|
| `limit` | 1…100, default 25 |
| `cursor` | Opaque base64url cursor from prior `page.nextCursor` |
| `q` | Case-insensitive contains search on resource fields |

| Resource | Path | Extra filters |
|----------|------|----------------|
| Orders | `GET /api/auth/orders` | `status`, `from`/`to` — customers scoped to own orders |
| Menu | `GET /api/auth/menu` | `category`, `isAvailable`, `tagId`/`tagIds`, `includeDeleted` |
| Inventory | `GET /api/auth/inventory` | `lowStock`, `storage`, `tagId`/`tagIds`, `includeDeleted` (admin) |
| Reservations | `GET /api/auth/reservations` | `status`, `from`/`to` — ownership scoped |
| Tag groups | `GET /api/auth/tag-groups` | `includeArchived` |
| Tags | `GET /api/auth/tags` | `groupId`, `includeArchived` |
| Audit | `GET /api/auth/audit` | `entityType`, `entityId` (admin) |

### Tag taxonomy (replaces hardcoded allergens)

Flexible `TagGroup` → `Tag` hierarchy. Menu and inventory items store `tagIds: [String]`.

| Method | Path | Role |
|--------|------|------|
| GET/POST | `/api/auth/tag-groups` | read: token; write: admin |
| PUT/DELETE | `/api/auth/tag-groups/:id` | admin (DELETE soft-archives group + child tags) |
| GET | `/api/auth/tag-groups/:id/tags` | token |
| GET/POST | `/api/auth/tags` | read: token; write: admin |
| PUT/DELETE | `/api/auth/tags/:id` | admin |

Demo seed creates TagGroup `"Allergens"` and migrates legacy `allergens` enum values → `tagIds`.

### Menu / Inventory CMS ops (admin)

- Soft-delete: `DELETE` sets `deletedAt` (hidden unless `includeDeleted=true`)
- Bulk: `POST /api/auth/menu/bulk`, `POST /api/auth/inventory/bulk`
- CSV: `GET …/export`, `POST …/import`
- Audit trail written on create/update/archive/bulk; query via `GET /api/auth/audit`

### ML models

- Stored on disk under `Models/<runtime>/<kind>/...` after upload or server train
- Tracked in MongoDB `ml_models` (or in-memory in tests)
- **macOS (Apple Silicon):** CoreML inference (local Create ML train) **and** ONNX inference via `Vendor/swift-onnx-runtime` (CONNX + `libonnxruntime.dylib`); server train uses `Trainer/train_restock.py` → real ONNX Runtime load
- **Linux:** ONNX inference via CONNX + `libonnxruntime.so`; same trainer script; Docker sets `LD_LIBRARY_PATH=/app/lib`
- Refresh vendored ORT binaries (linux-x64 + osx-arm64 1.20.1): `Vendor/swift-onnx-runtime/scripts/fetch-ort.sh`
- Symlink or copy `swift-onnx-runtime` to `Vendor/swift-onnx-runtime` before `swift build` / Docker (Docker cannot follow host symlinks outside the build context — use a real copy for `docker build --platform linux/amd64`)
- If `swift run` cannot resolve the dylib, set `DYLD_LIBRARY_PATH` to `Vendor/swift-onnx-runtime/Sources/CONNX/lib`
- Tests: `swift test --filter DualRuntimeTests`; trainer: `pytest Trainer/tests`

### License

MIT — see `License.txt`.

