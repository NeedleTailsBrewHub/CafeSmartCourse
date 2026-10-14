//
//  UnitOfMeasure.swift
//  CafeSmartAPI
//
//  Shared unit catalog for recipe ↔ inventory conversion helpers.
//

import Foundation

enum UnitFamily: String, Sendable {
    case mass, volume, count, pack
}

enum UnitOfMeasure: String, CaseIterable, Sendable {
    case mg, g, kg, oz, lb
    case ml, l, tsp, tbsp, cup, floz
    case ea, piece, slice, scoop, shot
    case bag, carton, bottle, can, box, case_, unit

    var storageCode: String {
        self == .case_ ? "case" : rawValue
    }

    var family: UnitFamily {
        switch self {
        case .mg, .g, .kg, .oz, .lb: return .mass
        case .ml, .l, .tsp, .tbsp, .cup, .floz: return .volume
        case .ea, .piece, .slice, .scoop, .shot: return .count
        case .bag, .carton, .bottle, .can, .box, .case_, .unit: return .pack
        }
    }

    var toBase: Double {
        switch self {
        case .mg: return 0.001
        case .g: return 1
        case .kg: return 1000
        case .oz: return 28.349523125
        case .lb: return 453.59237
        case .ml: return 1
        case .l: return 1000
        case .tsp: return 4.92892159375
        case .tbsp: return 14.78676478125
        case .cup: return 240
        case .floz: return 29.5735295625
        default: return 1
        }
    }

    /// Smallest amount allowed when entering recipes in this unit.
    var minAmount: Double {
        switch self {
        case .mg: return 1
        case .g: return 0.1
        case .kg: return 0.001
        case .oz: return 0.01
        case .lb: return 0.001
        case .ml: return 0.5
        case .l: return 0.001
        case .tsp, .tbsp: return 0.25
        case .cup: return 0.125
        case .floz: return 0.1
        case .ea, .piece, .slice, .scoop, .shot: return 1
        case .bag, .carton, .bottle, .can, .box, .case_, .unit: return 0.001
        }
    }

    var preferredRecipeUnit: UnitOfMeasure {
        switch self {
        case .kg: return .g
        case .l: return .ml
        case .lb: return .oz
        default: return self
        }
    }

    static func parse(_ raw: String?) -> UnitOfMeasure? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return nil }
        if t == "case" { return .case_ }
        if t == "liter" || t == "litre" || t == "lt" { return .l }
        if t == "gram" || t == "grams" { return .g }
        if t == "millilitre" || t == "milliliter" || t == "mls" { return .ml }
        if t == "each" || t == "pc" || t == "pcs" { return .ea }
        if t == "fl oz" || t == "fl.oz" { return .floz }
        return UnitOfMeasure(rawValue: t)
    }

    static func convert(_ amount: Double, from: UnitOfMeasure, to: UnitOfMeasure) -> Double? {
        guard amount >= 0 else { return nil }
        if from == to { return amount }
        if from.family == .pack || to.family == .pack {
            return from == to ? amount : nil
        }
        guard from.family == to.family else { return nil }
        return amount * from.toBase / to.toBase
    }
}
