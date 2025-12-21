//
//  Item.swift
//  SmartSpace
//
//  Created by Максим Гайдук on 11.11.2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
