//
//  BlockType.swift
//  SmartSpace
//
//  v2.0 scaffolding (v0.1): core block enum (no logic yet)
//

import Foundation

enum BlockType: String, Codable, CaseIterable, Identifiable {
    case summary = "summary"
    case flashcards = "flashcards"
    case quiz = "quiz"
    case keyTerms = "keyTerms"
    case mainQuestion = "mainQuestion"
    case insights = "insights"
    case argumentCounterargument = "argumentCounterargument"
    case contentOutline = "contentOutline"

    var id: String { rawValue }
}


