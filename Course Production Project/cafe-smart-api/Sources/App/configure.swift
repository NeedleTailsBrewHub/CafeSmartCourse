//
//  configure.swift
//  CafeSmartAPI
//
//  Created by NeedleTails on 8/8/25.
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is licensed under the MIT License.
//
//  See the LICENSE file for more information.
//
//  This file is part of the CafeSmartAPI Project

import DotEnv
import JWT
import MongoKitten
import NIOSSL
import Vapor
import VaporSecurityHeaders

public func configure(_ app: Application) async throws {
  // Load local .env for development (does not override existing process env)
  if app.environment != .testing {
    try? DotEnv.load(path: ".env", overwrite: false)
  }

  // HTTP TLS: required in production; optional in development when cert env is set.
  let httpTLS = try ServerTLS.configuration(for: app.environment)
  switch app.environment {
  case .production:
    guard let httpTLS else {
      throw ServerTLSError.missingProductionCertEnv
    }
    app.http.server.configuration = .init(
      hostname: "0.0.0.0",
      port: Environment.get("HTTP_PORT").flatMap(Int.init) ?? 8080,
      backlog: 256,
      reuseAddress: true,
      tcpNoDelay: true,
      responseCompression: .disabled,
      requestDecompression: .disabled,
      supportPipelining: true,
      supportVersions: Set<HTTPVersionMajor>([.one, .two]),
      tlsConfiguration: httpTLS,
      serverName: "CafeSmartAPI",
      logger: Logger(label: "[ com.example.app.api ]"))
    app.logger.info("HTTP TLS 1.3 enabled (production)")

  case .development:
    /// Bind 0.0.0.0 so Docker / reverse proxies can reach the process.
    app.http.server.configuration = .init(
      hostname: "0.0.0.0",
      port: Environment.get("HTTP_PORT").flatMap(Int.init) ?? 8080,
      supportVersions: Set<HTTPVersionMajor>(httpTLS == nil ? [.one] : [.one, .two]),
      tlsConfiguration: httpTLS,
      serverName: "CafeSmartAPI",
      logger: Logger(label: "[ com.example.app.api ]"))
    if httpTLS != nil {
      app.logger.info("HTTP TLS 1.3 enabled (development)")
    }
  default:
    break
  }

  // Initialize data store
  // By default use in-memory TestableMongoStore in testing, or when USE_TEST_STORE=true/1/yes
  let useTestStoreEnv = (Environment.get("USE_TEST_STORE") ?? "").lowercased()
  let useTestStore = app.environment == .testing
    || useTestStoreEnv == "1" || useTestStoreEnv == "true" || useTestStoreEnv == "yes"
  if useTestStore {
    // In tests, never seed to keep counts deterministic; in dev with test store, honor env/default seed
    if app.environment == .testing {
      app.mongoStore = TestableMongoStore(seedDummyData: false)
    } else {
      app.mongoStore = TestableMongoStore()
    }
  } else {
    let mongoURL = Environment.get("MONGO_URL") ?? ""
    try await app.initializeMongoDB(connectionString: mongoURL)
    let cache = MongoCacheManager(database: app.mongoDB)
    app.mongoStore = cache
    await cache.ensureIndexes()
    #if DEBUG
      if DemoModePolicy.isEnabled {
        try await DevDataSeed.ensureMongoSeeded(store: app.mongoStore, logger: app.logger)
      }
    #else
      if (Environment.get("SEED_TEST_DATA") ?? "").lowercased() == "true" {
        app.logger.warning(
          "SEED_TEST_DATA is ignored in Release builds; create the catalog via Menu CMS or DEBUG seed")
      }
    #endif
    try? await AllergenTagMigration.ensureAndMigrate(store: app.mongoStore, logger: app.logger)
  }

  // Default body limit; model upload raises its own collect maxSize under auth
  app.routes.defaultMaxBodySize = "1mb"

  // Configure BinaryCodable encoding/decoding for HTTP wire format
  ContentConfiguration.global.use(encoder: BinaryContentEncoder(), for: .binaryCodable)
  ContentConfiguration.global.use(decoder: BinaryContentDecoder(), for: .binaryCodable)

  // Post-quantum JWTs via JWTKit ML-DSA-87 (`@_spi(PostQuantum)`).
  try await JWTConfiguration.configurePostQuantum(on: app)

  // MARK: Middleware Configuration

  // CORS: allow all in development/testing; restrict via CORS_ALLOWED_ORIGIN in production
  let corsOrigin: CORSMiddleware.AllowOriginSetting = {
    if app.environment == .production {
      if let origin = Environment.get("CORS_ALLOWED_ORIGIN"), !origin.isEmpty {
        return .any([origin])
      }
      return .none
    }
    return .all
  }()
  let corsConfiguration = CORSMiddleware.Configuration(
    allowedOrigin: corsOrigin,
    allowedMethods: [.GET, .POST, .OPTIONS, .PUT, .DELETE, .PATCH],
    allowedHeaders: [
      .accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent,
      .accessControlAllowOrigin, .init("X-Request-ID"),
    ])

  let corsMiddleware = CORSMiddleware(configuration: corsConfiguration)
  let routeLogging = RouteLoggingMiddleware(logLevel: .info)

  // Initialize middleware stack
  app.middleware = .init()

  // Security headers configuration
  let securityHeadersFactory = SecurityHeadersFactory.api()
  securityHeadersFactory.with(contentTypeOptions: .init(option: .nosniff))
  securityHeadersFactory.with(frameOptions: .init(option: .deny))
  securityHeadersFactory.with(referrerPolicy: .init(.noReferrer))

  // Add HSTS in production
  if app.environment == .production {
    securityHeadersFactory.with(strictTransportSecurity: .init())
  }

  // Apply middleware in order
  app.middleware.use(securityHeadersFactory.build())
  app.middleware.use(RequestIDMiddleware())
  app.middleware.use(corsMiddleware)
  app.middleware.use(routeLogging)
  app.middleware.use(ErrorMiddleware.default(environment: app.environment))
  app.middleware.use(app.sessions.middleware)
  // Serve menu product photos from Public/ (local media / sample-data symlink in dev).
  let publicDir = app.directory.publicDirectory
  app.middleware.use(FileMiddleware(publicDirectory: publicDir))

  // Catalog media: R2 in production (required); Local/Fake otherwise.
  // Tests may inject `app.mediaStorage` via `beforeConfigure`.
  let r2Config = R2MediaConfig.fromEnvironment { Environment.get($0) }
  if !app.hasInjectedMediaStorage {
    if app.environment == .production {
      guard let r2Config else {
        throw Abort(
          .internalServerError,
          reason:
            "Production requires R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET, R2_PUBLIC_BASE_URL"
        )
      }
      app.mediaStorage = R2MediaStorage(config: r2Config, http: URLSessionMediaHTTPClient())
      app.logger.info("Catalog media: Cloudflare R2 (\(r2Config.bucket))")
    } else if let r2Config {
      app.mediaStorage = R2MediaStorage(config: r2Config, http: URLSessionMediaHTTPClient())
      app.logger.info("Catalog media: Cloudflare R2 (\(r2Config.bucket))")
    } else if app.environment == .testing {
      app.mediaStorage = FakeMediaStorage()
      app.logger.info("Catalog media: FakeMediaStorage (testing)")
    } else {
      let localRoot = URL(fileURLWithPath: publicDir).appendingPathComponent("menu-images")
      app.mediaStorage = LocalMediaStorage(rootDirectory: localRoot)
      app.logger.info("Catalog media: LocalMediaStorage at \(localRoot.path)")
    }
  }
  if app.mediaAllowedHosts.isEmpty {
    app.mediaAllowedHosts = MediaURLPolicy.allowedHostsFromEnv(
      publicBaseURL: r2Config?.publicBaseURL ?? Environment.get("R2_PUBLIC_BASE_URL"),
      extra: Environment.get("MEDIA_ALLOWED_HOSTS"))
  }

  // Configure logging level based on build configuration
  #if DEBUG
    app.logger.logLevel = .trace
  #else
    app.logger.logLevel = .info
  #endif

  // Local Mac/dev: ensure Trainer/.venv + pip deps (Docker already sets TRAINER_PYTHON)
  await TrainerBootstrap.ensureReady(app: app)

  // Reload active ML predictors from disk after store is ready
  await ModelArtifactLifecycle.reloadActivePredictors(app: app)

  // Monthly auto-train (AUTO_TRAIN_ENABLED); skipped in testing
  TrainScheduleService.start(app: app)

  // Stripe: Fake in testing when keys set for prepaid tests; Live when ops enabled.
  if app.environment == .testing {
    if PaymentsPolicy.prepaidAvailable {
      let fake = FakeStripeClient()
      app.fakeStripe = fake
      app.stripeClient = fake
    } else {
      app.stripeClient = DisabledStripeClient()
    }
  } else if let secret = PaymentsPolicy.stripeSecretKey, PaymentsPolicy.paymentsEnabledEnv {
    app.stripeClient = StripeLiveClient(secretKey: secret)
    app.logger.info("Stripe payments client configured")
  } else {
    app.stripeClient = DisabledStripeClient()
  }

  // CMK WebSocket realtime server + HTTP routes
  app.realtime = RealtimeHub()
  try await app.realtime.start(using: app)
  try routes(app)
  print(app.routes.all)
}
