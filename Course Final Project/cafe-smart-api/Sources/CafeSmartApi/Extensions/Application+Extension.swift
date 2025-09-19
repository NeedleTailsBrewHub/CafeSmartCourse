//
//  Application+Extension.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//
import Vapor
import MongoKitten

extension Application {

    public struct MongoStoreKey: StorageKey {
        public typealias Value = MongoStore
    }
    
    public var mongoStore: any MongoStore {
        get {
            self.storage[MongoStoreKey.self]!
        }
        set {
            self.storage[MongoStoreKey.self] = newValue
        }
    }
    
    
    private struct MongoDBStorageKey: StorageKey {
        typealias Value = MongoDatabase
    }

    
    public var mongoDB: MongoDatabase {
        get {
            self.storage[MongoDBStorageKey.self]!
        }
        set {
            self.storage[MongoDBStorageKey.self] = newValue
        }
    }
    
    public func initializeMongoDB(connectionString: String) async throws {
        self.mongoDB = try await MongoDatabase.connect(to: connectionString)
    }
    
    
    struct RealtimeKey: StorageKey {
        typealias Value = RealtimeHub
    }
    
    var realtimeHub: RealtimeHub {
        get {
            if let hub = self.storage[RealtimeKey.self] {
                return hub
            } else {
                let hub = RealtimeHub()
                self.storage[RealtimeKey.self] = hub
                return hub
            }
        }
        set {
            self.storage[RealtimeKey.self] = newValue
        }
    }
    
}

extension SymmetricKey: @retroactive @unchecked Sendable {}