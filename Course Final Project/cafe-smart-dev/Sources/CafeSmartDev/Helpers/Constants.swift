//
//  Constants.swift
//  cafe-smart-app
//
//  Created by Cole M on 12/22/25.
//

@MainActor
enum Constants {
#if DEBUG
    static let httpHost: String = "http://\(Constants.wsHost):8080/"
    static let wsHost: String = "localhost"
#else
    static let httpHost: String = "https://\(Constants.wsHost):8080/"
    static let wsHost: String = "localhost"
#endif
}
