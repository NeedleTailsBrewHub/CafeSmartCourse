import Vapor
import BSON
import JWT

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
            logger: Logger(label: "[ com.needletails.cafesmart.api ]"))
    case .production:
        break
    default:
        break
    }

    app.routes.defaultMaxBodySize = 200_000_000
    let hmacSecret = Environment.get("HMAC_SECRET") ?? ""
    await app.jwt.keys.add(hmac: HMACKey(stringLiteral: hmacSecret), digestAlgorithm: .sha256)
    
    ContentConfiguration.global.use(encoder: BSONEncoder(), for: .bson)
    ContentConfiguration.global.use(decoder: BSONDecoder(), for: .bson)
    
    
    let useTestStore = Environment.get("USE_TEST_STORE") ?? ""
    
    if useTestStore == "true" {
        app.mongoStore = TestableMongoStore()
    } else {
        //Intitialize Mongo
        let mongoURL = Environment.get("MONGO_URL") ?? ""
        try await app.initializeMongoDB(connectionString: mongoURL)
        app.mongoStore = MongoCacheManager(db: app.mongoDB)
    }
    
    
    app.realtimeHub = RealtimeHub()
    // register routes
    try routes(app)
    print(app.routes.all)
}


