//
//  exampleApp.swift
//  example
//
//  Created by hv on 21/12/25.
//

import SwiftUI
import OSLog

@main
struct exampleApp: App {
    init() {
        Snag.start()
        
        // Test logs
        print("Snag Example: Standard print log")
        NSLog("Snag Example: NSLog message")
        Snag.log("Snag Example: Manual Snag.log call")
        
        let logger = Logger(subsystem: "com.snag.example", category: "Lifecycle")
        logger.info("Snag Example: Logger info message")
        logger.warning("Snag Example: Logger warning message")
        logger.error("Snag Example: Logger error message")
        
        // Test JSON log
        let jsonObject: [String: Any] = [
            "user": [
                "name": "John Doe",
                "email": "john@example.com",
                "age": 30
            ],
            "items": ["apple", "banana", "cherry"],
            "isActive": true,
            "balance": 123.45
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            Snag.log(jsonString, level: "info", tag: "JSON Test")
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
