import Vapor
@_spi(PostQuantum) import JWT
@_spi(PostQuantum) import JWTKit

// configures your application
public func configure(_ app: Application) async throws {
    
    switch app.environment {
    case .development:
        //
        app.http.server.configuration = .init(
            hostname: "0.0.0.0",
            port: 8080,
            supportVersions: Set<HTTPVersionMajor>([.one]),
            tlsConfiguration: .none,
            serverName: "CafeSmartAPI",
            logger: Logger(label: "[ com.example.app.api ]"))
    case .production:
        break
    default:
        break
    }

    // Default body limit; model upload raises its own collect maxSize under auth
    app.routes.defaultMaxBodySize = "1mb"

    // Configure BinaryCodable encoding/decoding for HTTP wire format
    ContentConfiguration.global.use(encoder: BinaryContentEncoder(), for: .binaryCodable)
    ContentConfiguration.global.use(decoder: BinaryContentDecoder(), for: .binaryCodable)

    // Configure post-quantum JWT (MLDSA87) signing
    let seed = try MLDSASeed.load()
    let privateKey = try MLDSA87PrivateKey(seedRepresentation: seed)
    await app.jwt.keys.add(mldsa: privateKey)
    
    
    let useTestStore = Environment.get("USE_TEST_STORE") ?? ""
    
    if useTestStore == "true" {
        app.mongoStore = TestableMongoStore()
    } else {
        //Intitialize Mongo
        let mongoURL = Environment.get("MONGO_URL") ?? ""
        try await app.initializeMongoDB(connectionString: mongoURL)
        app.mongoStore = MongoCacheManager(db: app.mongoDB)
        if (Environment.get("SEED_TEST_DATA") ?? "").lowercased() == "true" {
            try await DevDataSeed.ensureMongoSeeded(store: app.mongoStore, logger: app.logger)
        }
    }
    
    
    // Local Mac/dev: ensure Trainer/.venv + pip deps (Docker already sets TRAINER_PYTHON)
    await TrainerBootstrap.ensureReady(app: app)

    await ModelArtifactLifecycle.reloadActivePredictors(app: app)

    app.realtimeHub = RealtimeHub()
    try await app.realtimeHub.start(using: app)
    try routes(app)
    print(app.routes.all)
}
