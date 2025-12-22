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
- `HMAC_SECRET`: JWT HMAC signing secret (use a long, random string for production).
- `ADMIN_USERNAMES`: Comma-separated admin email addresses for admin access.

**Optional:**
- `USE_TEST_STORE`: Set to `true` to use in-memory store (no MongoDB required). Useful for testing.
- `LOG_LEVEL`: Logging level (e.g., `debug`, `info`, `warning`, `error`).

**Production (TLS):**
- `API_LOCAL_FULL_CHAIN`: Full chain certificate PEM file path (relative to working directory).
- `API_LOCAL_PRIV_KEY`: Private key PEM file path (relative to working directory).

**Metrics (optional):**
- `CAFE_METRICS_COLLECTION`: MongoDB collection name for metrics (default: `cafe_metrics`).
- `CAFE_METRICS_FLUSH_SECONDS`: Metrics flush interval in seconds (default: `43200`).
- `CAFE_METRICS_MAX_BATCH`: Maximum batch size for metrics (default: `512`).
- `CAFE_METRICS_MAX_WRITE_BYTES`: Maximum write bytes per batch (default: `10000000`).
- `CAFE_METRICS_MAX_WRITE_COUNT`: Maximum write count per batch (default: `1000`).

**Test data (in-memory store only):**
- `SEED_TEST_DATA`: Set to `true` to seed rich dummy data for testing.
- `DUMMY_DAYS_BACK`: Number of days of historical data to generate (default: `180`).
- `DUMMY_BASE_ORDERS_MIN`: Minimum base orders per day (default: `4`).
- `DUMMY_BASE_ORDERS_MAX`: Maximum base orders per day (default: `10`).
- `DUMMY_MAX_ITEMS_PER_ORDER`: Maximum items per order (default: `3`).

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

Build and run:
```bash
docker build -t cafesmart-api:latest .
docker run --rm -p 8080:8080 \
  -e MONGO_URL="mongodb://host.docker.internal:27017/cafesmart" \
  -e HMAC_SECRET="change-me" \
  -e ADMIN_USERNAMES="admin@example.com" \
  cafesmart-api:latest
```

### Tests

```bash
swift test
```

### Endpoints (overview)

- Auth, Menu, Orders, Reservations, Inventory, Recipes
- Predictor: generate/latest/export, model upload/list/activate/delete, forecast, instantiate
- WebSockets: `/api/ws/merchant` (admin), `/api/ws/customer`

See `docs/Predictions.md` for ML details.

### ML models

- Stored on disk under `Models/<runtime>/<kind>/...` after upload
- Tracked in MongoDB `ml_models` (or in-memory in tests)

### License

MIT — see `License.txt`.

