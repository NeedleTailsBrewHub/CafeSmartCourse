//
//  AppImage.swift
//  CafeSmartDev
//

import SwiftUI

/// SF Symbol on Apple platforms; named asset from the module bundle on Android (Skip).
struct AppImage: View {
    let name: String

    var body: some View {
        Group {
            #if os(Android)
            Image(name, bundle: .module)
            #else
            Image(systemName: name)
            #endif
        }
    }

    func resizable(
        capInsets: EdgeInsets = EdgeInsets(),
        resizingMode: Image.ResizingMode = .stretch
    ) -> some View {
        #if os(Android)
        Image(name, bundle: .module)
            .resizable(capInsets: capInsets, resizingMode: resizingMode)
        #else
        Image(systemName: name)
            .resizable(capInsets: capInsets, resizingMode: resizingMode)
        #endif
    }
}
