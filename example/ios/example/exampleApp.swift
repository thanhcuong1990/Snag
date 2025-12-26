//
//  exampleApp.swift
//  example
//
//  Created by hv on 21/12/25.
//

import SwiftUI

@main
struct exampleApp: App {
    init() {
        Snag.start()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
