//
//  Currency+Helpers.swift
//  CafeSmartDev
//
//  Created by NeedleTails on 8/19/25
//
//  Copyright (c) 2025 NeedleTails Organization.
//
//  This project is proprietary and confidential.
//
//  MIT License
//
//  This file is part of the CafeSmart Project
//

#if SKIP
import SkipFoundation
#else
import Foundation
#endif

enum CurrencyHelper {
    static func dollars(fromCents cents: Int) -> Double {
        Double(cents) / 100.0
    }

    static func format(cents: Int, code: String = Locale.current.currency?.identifier ?? "USD") -> String {
        let amount = Double(cents) / 100.0
        return amount.formatted(.currency(code: code))
    }
}

extension Collection where Element == Int {
    var sum: Int {
        reduce(0, +)
    }
}
