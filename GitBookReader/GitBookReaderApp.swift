//
//  GitBookReaderApp.swift
//  GitBookReader
//
//  Created by Sơn Nguyễn on 20/2/26.
//

import SwiftUI

@main
struct GitBookReaderApp: App {
    @StateObject private var settings = BookSettings()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .preferredColorScheme(settings.preferredColorScheme)
        }
    }
}
