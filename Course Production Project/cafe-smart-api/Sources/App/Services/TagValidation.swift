//
//  TagValidation.swift
//  CafeSmartAPI
//

import Vapor

enum TagValidation {
	static func validateTagIds(
		store: any MongoStore,
		tagIds: [String]?,
		existingTagIds: [String]? = nil
	) async throws -> [String] {
		guard let tagIds else { return existingTagIds ?? [] }
		if tagIds.isEmpty { return [] }

		let existing = Set(existingTagIds ?? [])
		var resolved: [String] = []
		for tagId in tagIds {
			guard let tag = try await store.findTag(by: tagId) else {
				throw Abort(.badRequest, reason: "Unknown tag id: \(tagId)")
			}
			if tag.isArchived && !existing.contains(tagId) {
				throw Abort(.badRequest, reason: "Cannot assign archived tag: \(tag.name)")
			}
			resolved.append(tagId)
		}
		return resolved
	}

	static func groupNameConflict(existing: [TagGroup], name: String, excludingId: String?) -> Bool {
		let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		return existing.contains { group in
			group.id != excludingId
				&& group.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
		}
	}

	static func tagNameConflict(existing: [Tag], groupId: String, name: String, excludingId: String?) -> Bool {
		let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		return existing.contains { tag in
			tag.groupId == groupId
				&& tag.id != excludingId
				&& tag.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
		}
	}
}
