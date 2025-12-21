//
//  QuizQuestion.swift
//  SmartSpace
//
//  v0.11: Quiz question model (non-SwiftData)
//

import Foundation

struct QuizQuestion: Codable, Equatable {
    let question: String
    let options: [String]
    let correctIndex: Int
}


