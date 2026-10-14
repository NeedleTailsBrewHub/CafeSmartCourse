//
//  UnitOfMeasureTests.swift
//  ApiTests
//
//  Spec for kitchen ↔ stock unit conversion and minimums.
//

import Foundation
import Testing
@testable import cafe_smart_api

@Suite("UnitOfMeasure")
struct UnitOfMeasureTests {

    @Test func parsesAliasesAndStorageCodes() {
        #expect(UnitOfMeasure.parse("g") == .g)
        #expect(UnitOfMeasure.parse("grams") == .g)
        #expect(UnitOfMeasure.parse("L") == .l)
        #expect(UnitOfMeasure.parse("litre") == .l)
        #expect(UnitOfMeasure.parse("fl oz") == .floz)
        #expect(UnitOfMeasure.parse("case") == .case_)
        #expect(UnitOfMeasure.parse("each") == .ea)
        #expect(UnitOfMeasure.parse("") == nil)
        #expect(UnitOfMeasure.parse(nil) == nil)
    }

    @Test func convertsMassKitchenToStock() {
        let kg = UnitOfMeasure.convert(18, from: .g, to: .kg)
        #expect(kg != nil)
        #expect(abs(kg! - 0.018) < 1e-9)

        let back = UnitOfMeasure.convert(0.018, from: .kg, to: .g)
        #expect(back != nil)
        #expect(abs(back! - 18) < 1e-9)
    }

    @Test func convertsVolumeKitchenToStock() {
        let liters = UnitOfMeasure.convert(160, from: .ml, to: .l)
        #expect(liters != nil)
        #expect(abs(liters! - 0.16) < 1e-9)
    }

    @Test func rejectsCrossFamilyAndPackMismatch() {
        #expect(UnitOfMeasure.convert(10, from: .g, to: .ml) == nil)
        #expect(UnitOfMeasure.convert(0.5, from: .bag, to: .g) == nil)
        #expect(UnitOfMeasure.convert(0.5, from: .bag, to: .carton) == nil)
        #expect(UnitOfMeasure.convert(0.5, from: .bag, to: .bag) == 0.5)
    }

    @Test func rejectsNegativeAmounts() {
        #expect(UnitOfMeasure.convert(-1, from: .g, to: .kg) == nil)
    }

    @Test func preferredRecipeUnitMapsBulkStockToKitchen() {
        #expect(UnitOfMeasure.kg.preferredRecipeUnit == .g)
        #expect(UnitOfMeasure.l.preferredRecipeUnit == .ml)
        #expect(UnitOfMeasure.lb.preferredRecipeUnit == .oz)
        #expect(UnitOfMeasure.g.preferredRecipeUnit == .g)
    }

    @Test func minAmountsAllowEspressoAndRejectZeroCount() {
        #expect(UnitOfMeasure.g.minAmount == 0.1)
        #expect(UnitOfMeasure.ml.minAmount == 0.5)
        #expect(UnitOfMeasure.kg.minAmount == 0.001)
        #expect(UnitOfMeasure.ea.minAmount == 1)
        #expect(18 >= UnitOfMeasure.g.minAmount)
        #expect(0.05 < UnitOfMeasure.g.minAmount)
    }
}
