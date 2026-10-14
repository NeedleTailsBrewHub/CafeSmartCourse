//
//  AllergenTagMigration.swift
//  CafeSmartAPI
//
//  Ensures TagGroup "Allergens" exists with tags for former Allergen enum cases,
//  and maps menu item `allergens` → `tagIds`.
//

@preconcurrency import BSON
import Foundation
import Vapor

enum AllergenTagMigration {
    static let groupName = "Allergens"
    static let groupSlug = "allergens"

    /// Creates/updates the Allergens taxonomy and migrates menu items that still use `allergens`.
    static func ensureAndMigrate(store: any MongoStore, logger: Logger) async throws {
        let now = Date()
        var groups = try await store.listTagGroups()
        let group: TagGroup
        if let existing = groups.first(where: {
            $0.slug == groupSlug || $0.name.lowercased() == groupName.lowercased()
        }) {
            group = existing
        } else {
            group = try await store.createTagGroup(
                TagGroup(
                    id: ObjectId().hexString,
                    name: groupName,
                    slug: groupSlug,
                    sortOrder: 0,
                    allowsMultiple: true,
                    createdAt: now,
                    updatedAt: now))
            groups.append(group)
        }

        var tags = try await store.listTags()
        var nameToId: [String: String] = [:]
        for allergen in Allergen.allCases {
            let key = allergen.rawValue.lowercased()
            if let found = tags.first(where: {
                $0.groupId == group.id && $0.name.lowercased() == key
            }) {
                nameToId[key] = found.id
            } else {
                let created = try await store.createTag(
                    Tag(
                        id: ObjectId().hexString,
                        groupId: group.id,
                        name: allergen.rawValue.capitalized,
                        slug: key,
                        sortOrder: 0,
                        createdAt: now,
                        updatedAt: now))
                tags.append(created)
                nameToId[key] = created.id
            }
        }

        let menu = try await store.listMenu()
        var migrated = 0
        for var item in menu {
            guard let allergens = item.allergens, !allergens.isEmpty else { continue }
            var ids = Set(item.tagIds ?? [])
            for a in allergens {
                if let tid = nameToId[a.rawValue.lowercased()] {
                    ids.insert(tid)
                }
            }
            let next = Array(ids).sorted()
            if item.tagIds != next {
                item.tagIds = next
                item.updatedAt = now
                _ = try await store.update(menuItem: item)
                migrated += 1
            }
        }
        if migrated > 0 {
            logger.info("AllergenTagMigration: mapped allergens→tagIds on \(migrated) menu item(s)")
        }
    }
}
