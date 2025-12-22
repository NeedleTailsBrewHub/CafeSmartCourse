//
//  TableReservationView.swift
//  CafeSmart
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

import SwiftUI

struct TableReservationView: View {
    @State var name: String = ""
    @State var partySize: String = "2"
    @State var date: String = "Today"
    @State var time: String = "7:00 PM"
    
#if os(Android)
let numberIcon = "android_tag"
let clockIcon = "android_clock"
#else
let numberIcon = "number"
let clockIcon = "clock.fill"
#endif

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                SectionHeader(title: "Reserve a table", subtitle: "Book quickly")
                VStack(spacing: AppSpacing.md) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "person.fill")
                        AppTextField(placeholder: "Name", text: $name)
                    }
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: numberIcon)
                        AppTextField(placeholder: "Party size", text: $partySize)
//                        #if os(iOS)
//                        .keyboardType(.numberPad)
//                        #endif
                    }
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "calendar")
                        AppTextField(placeholder: "Date", text: $date)
                    }
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: clockIcon)
                        AppTextField(placeholder: "Time", text: $time)
                    }
                    PrimaryButton(title: "Confirm reservation", fillWidth: true) {}
                }
            }
            .padding()
        }
        .navigationTitle("Reserve a table")
    }
}


