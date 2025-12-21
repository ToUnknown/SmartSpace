//
//  SpaceQuestion.swift
//  SmartSpace
//
//  v0.13: One-shot Q&A per Space (persisted)
//

import Foundation
import SwiftData

enum QuestionStatus: String, Codable {
    case pending
    case answering
    case answered
    case failed
}

@Model
final class SpaceQuestion {
    var id: UUID
    var createdAt: Date

    @Relationship var space: Space

    var question: String
    var answer: String?
    var status: QuestionStatus
    var errorMessage: String?

    init(space: Space, question: String) {
        self.id = UUID()
        self.createdAt = .now
        self.space = space
        self.question = question
        self.answer = nil
        self.status = .pending
        self.errorMessage = nil
    }
}


