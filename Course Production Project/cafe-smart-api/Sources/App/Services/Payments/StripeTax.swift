//
//  StripeTax.swift
//  CafeSmartAPI
//

import Foundation

struct StripeTaxAddress: Sendable, Equatable {
    var line1: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var country: String
}

struct StripeTaxCalculation: Sendable, Equatable {
    var id: String
    var amountTotal: Int
    var taxAmountExclusive: Int
    var currency: String
}
