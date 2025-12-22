//
//  TemplateBlockMap.swift
//  SmartSpace
//
//  v1.1 (Part A): Central source of truth for TemplateType → BlockType mapping
//

import Foundation

enum TemplateBlockMap {
    static func blockTypes(for template: TemplateType) -> [BlockType] {
        switch template {
        case .languageLearning:
            return [.summary, .keyTerms, .flashcards, .quiz]

        case .lectureNotes:
            return [.summary, .mainQuestion, .insights, .keyTerms, .contentOutline]

        case .examPrep:
            return [.summary, .mainQuestion, .flashcards, .quiz, .keyTerms]

        case .researchReview:
            return [.summary, .argumentCounterargument, .insights, .contentOutline, .keyTerms]

        case .meetingMinutes:
            return [.summary, .insights, .keyTerms, .contentOutline]

        case .projectBrief:
            return [.summary, .mainQuestion, .insights, .contentOutline, .keyTerms]

        case .writingAssistant:
            return [.summary, .mainQuestion, .argumentCounterargument, .contentOutline, .keyTerms]

        case .quickStudy:
            return [.summary, .keyTerms, .quiz]
        }
    }
}


