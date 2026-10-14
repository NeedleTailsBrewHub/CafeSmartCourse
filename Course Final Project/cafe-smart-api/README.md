# CafeSmartApi

💧 A project built with the Vapor web framework.

## Getting Started

### Prerequisites

- Swift 6.0+
- macOS 14+ or Ubuntu Noble
- MongoDB 6+ (optional, can use in-memory store for testing)

### Setup

1. **Configure environment variables**

   Create a `.env` file in the project root:
   ```bash
   cp env.example .env
   ```

   Edit `.env` and set the required variables (see [Environment Variables](#environment-variables) below).

2. **Build the project**

   Using Swift Package Manager from the project root:
   ```bash
   swift build
   ```

3. **Run the server**

   From the project root:
   ```bash
   swift run CafeSmartApi serve --env development --hostname 0.0.0.0 --port 8080
   ```

   Server will be available at: http://localhost:8080

4. **Run tests**

   ```bash
   swift test
   ```

### Environment Variables

Create a `.env` file in the project root with the following variables:

**Required:**
- `MONGO_URL`: MongoDB connection URI, e.g. `mongodb://localhost:27017/cafesmart`. If unset and `USE_TEST_STORE=true`, uses in-memory store.
- `MLDSA_SEED`: Post-quantum JWT (MLDSA87) seed — **exactly 32 bytes**, or 64 hex characters. `HMAC_SECRET` is accepted as a temporary fallback with the same length rule.
- `ADMIN_USERNAMES`: Comma-separated admin email addresses for admin access.

**Optional:**
- `USE_TEST_STORE`: Set to `true` to use in-memory store (no MongoDB required). Useful for testing.
- `LOG_LEVEL`: Logging level (e.g., `debug`, `info`, `warning`, `error`).
- `TRAINER_PYTHON` / `TRAINER_SCRIPT`: Server-side sklearn → ONNX training.
- `MODEL_RETENTION_COUNT`: Max artifacts kept per kind+runtime (default `5`).

**Note:** The `.env` file is ignored by git (see `.gitignore`). Never commit sensitive credentials.

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

Build and run with Docker:
```bash
docker build -t cafesmart-api:latest .
docker run --rm -p 8080:8080 \
  -e MONGO_URL="mongodb://host.docker.internal:27017/cafesmart" \
  -e MLDSA_SEED="0123456789abcdef0123456789abcdef" \
  -e ADMIN_USERNAMES="admin@example.com" \
  cafesmart-api:latest
```

### ML (CoreML / ONNX)

- **macOS (Apple Silicon):** CoreML (`.mlmodel`) and ONNX via `Vendor/swift-onnx-runtime` (CONNX + dylib); upload or server-train `.onnx`
- **Linux:** ONNX via CONNX + `.so`; same trainer
- Server train: `POST /api/auth/predictor/train` (admin); script in `Trainer/train_restock.py`
- Env: `TRAINER_PYTHON`, `TRAINER_SCRIPT`, `LD_LIBRARY_PATH` (Docker) / `DYLD_LIBRARY_PATH` if needed on Mac
- Refresh ORT binaries: `Vendor/swift-onnx-runtime/scripts/fetch-ort.sh`
- Symlink/copy local `swift-onnx-runtime` to `Vendor/swift-onnx-runtime` before building
- Docker images are **linux/amd64** for the bundled ONNX Runtime `.so`
- Trainer tests: `pytest Trainer/tests`

### See more

- [Vapor Website](https://vapor.codes)
- [Vapor Documentation](https://docs.vapor.codes)
- [Vapor GitHub](https://github.com/vapor)
- [Vapor Community](https://github.com/vapor-community)
