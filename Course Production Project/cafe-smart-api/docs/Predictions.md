## CafeSmart API Guide

Base URL: http://localhost:8080  
All paths below are relative to `/api`.

### Authentication

Headers
- Use `Authorization: Bearer <JWT>` for protected endpoints.

Public
- POST `/auth/register`
  - Body: { email, password, name?, isAdmin: Bool }
  - Returns: UserPublic
- POST `/auth/login`
  - Body: { email, password }
  - Returns: { token, refreshToken, expiresAt, user }
- POST `/auth/refresh-token`
  - Header: Authorization: Bearer <JWT>
  - Returns: refreshed token bundle

Authenticated
- POST `/auth/logout`
- POST `/auth/update-password`
  - Body: { oldPassword, newPassword }
- DELETE `/auth/account`

Notes
- Admin authorization is enforced by `AdminMiddleware`. A user is admin if their `isAdmin` is true or their email is included in env `ADMIN_USERNAMES` (comma-separated).

### Menu

- GET `/menu` → MenuItemsWrapper
- GET `/menu/:id` → MenuItem
- POST `/menu` (admin) → MenuItemCreate → MenuItem
- PUT `/menu/:id` (admin) → MenuItemUpdate → MenuItem
- DELETE `/menu/:id` (admin)

### Orders

- GET `/orders` → OrdersWrapper
- POST `/orders` → CreateOrderRequest → Order
- GET `/orders/:id` → Order
- PATCH `/orders/:id/status` (admin) → UpdateOrderStatusRequest → Order
- DELETE `/orders/:id` (admin)

Notes
- Creating/updating orders emits domain metrics used for dataset exports.

### Reservations

- GET `/reservations` → ReservationsWrapper
- POST `/reservations` → { name, partySize, startTime, phone?, notes? } → Reservation
- GET `/reservations/:id` → Reservation
- DELETE `/reservations/:id` (admin)

### Inventory

- GET `/inventory` (admin) → InventoryItemsWrapper
- GET `/inventory/:id` (admin) → InventoryItem
- POST `/inventory` (admin) → InventoryItemCreate → InventoryItem
- PUT `/inventory/:id` (admin) → InventoryItemUpdate → InventoryItem
- DELETE `/inventory/:id` (admin)

### Loyalty

- GET `/loyalty/:id` → LoyaltyAccountPublic
- POST `/loyalty/enroll` (admin) → { userId } → LoyaltyAccountPublic
- POST `/loyalty/accrue` → { userId, points } → LoyaltyAccountPublic
- POST `/loyalty/redeem` → { userId, points } → LoyaltyAccountPublic

### Seating

Areas (admin)
- GET `/seating/areas` → SeatingAreasWrapper
- POST `/seating/areas` → { name, defaultTurnMinutes, active } → SeatingArea
- GET `/seating/areas/:id` → SeatingArea
- PUT `/seating/areas/:id` → partial update → SeatingArea
- DELETE `/seating/areas/:id`

Tables (admin)
- GET `/seating/tables` → TablesWrapper
- GET `/seating/areas/:id/tables` → TablesWrapper
- POST `/seating/tables` → { areaId, name, capacity, accessible, highTop?, outside?, active } → Table
- GET `/seating/tables/:id` → Table
- PUT `/seating/tables/:id` → partial update → Table
- DELETE `/seating/tables/:id`

### Business Config (admin)

- GET `/config` → BusinessConfig
- PUT `/config` → BusinessConfig → BusinessConfig

### Predictor (ML, admin)

Dual training (same feature CSV for both paths)
- **Server:** `POST /predictor/train` `{ "kind": "restockDaily"|"workloadHourly"|"reservationsHourly" }` → Python → ONNX
- **Local (Mac app):** export CSV → Create ML → `POST /predictor/models/upload?runtime=coreml&kind=…`
- `reservationDuration` train → `400` (not wired)
- Create ML CoreML and sklearn ONNX are **not bit-identical**; one active runtime per kind

Dataset export (CSV)
- GET `/predictor/export?dataset=...` → CSV download
  - `ingredientDaily` → `target_usage` (SKU × day; optional `sku=`)
  - `ordersHourly` → `target_orders` (cafe × hour)
  - `reservationsHourly` → `target_covers` (covers × hour)

Model management
- POST `/predictor/models/upload` (octet-stream) query `name?`, `runtime?` (onnx|coreml), `kind?`
- GET `/predictor/models`, POST activate/delete, POST instantiate, GET capabilities

Server trainers (by kind)
- `restockDaily` → `Trainer/train_restock.py`
- `workloadHourly` → `Trainer/train_busy_hour.py`
- `reservationsHourly` → `Trainer/train_reservations_hour.py`
- Env: `TRAINER_PYTHON`, optional `TRAINER_SCRIPT` override (restock default), `MODEL_RETENTION_COUNT`
- Active predictors reloaded on boot; ONNX Runtime (CONNX) required for server train/infer on Linux

Restock decision
- POST `/predictor/restock/decide` → { sku, daysAhead? } → needRestock, reorderQty, reorderPoint, leadTimeDays, onHand, forecastSumNextLeadTime, predictedSpendCents?, busynessScale?, unitCostCents?
- Forecast series uses **rolling** lag features (recursive one-step)
- Usage derived from orders × recipes (not a separate ledger)

Reports (admin)
- GET `/reports/summary?from&to` — finance: net sales = completed+paid − loyalty; COGS on completed; labor; contribution = net − COGS − labor
- GET `/reports/orders?from&to` — order drill-down rows
- GET `/reports/export?from&to&dataset=` — accounting CSV (`summary` | `byDay` | `orders` | `salesByItem` | `cogsBySku` | `labor`); money as decimal currency
- GET `/reports/demand?days=` — busyness + staffing + stock $ via **live** `workloadHourly` `predictMultiple` when loaded (`source=model`); else weekday×hour historical prior
- Stock outlook `busynessScale` = predicted avg orders over lead window ÷ historical baseline (clamped 0.75…1.75)

Reservations availability
- Slot `busynessIndex` / `recommended` prefer combined workload + reservations hourly forecasts when predictors are loaded; else historical order counts

Restock `busynessScale`
- `POST /predictor/restock/decide` multiplies lead-time SKU demand by cafe-wide workload scale before ROP / reorder qty

### Realtime WebSockets

- Admin: `/api/ws/merchant`
- Customer: `/api/ws/customer`

### Create ML tips

- Deselect Date/Datetime columns (`date`/`datetime`) or pre-remove them before training.
- Use regression (numeric targets):
  - restockDaily: `target_qty_<menuItemId>`
  - ingredientDaily: `target_usage`
  - workload/reservations hourly: `target_...`
- Ensure enough rows (dozens to hundreds).

### Seeding and Test Data

In-memory test store:
- Enable test store: `USE_TEST_STORE=true`
- Seed data: `SEED_TEST_DATA=true` (must be literal "true")
- Volume controls (optional):
  - `DUMMY_DAYS_BACK`: default 90
  - `DUMMY_BASE_ORDERS_MIN`: default 2
  - `DUMMY_BASE_ORDERS_MAX`: default 5
  - `DUMMY_MAX_ITEMS_PER_ORDER`: default 3

Example run:
```bash
USE_TEST_STORE=true \
SEED_TEST_DATA=true \
DUMMY_DAYS_BACK=270 \
DUMMY_BASE_ORDERS_MIN=6 \
DUMMY_BASE_ORDERS_MAX=14 \
DUMMY_MAX_ITEMS_PER_ORDER=4 \
swift run
```

Admin env
- `ADMIN_USERNAMES="admin@cafesmart.test,other@domain.com"`