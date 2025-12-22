//
//  TemplateType.swift
//  SmartSpace
//
//  v2.0 scaffolding (v0.1): core template enum (no logic yet)
//

import Foundation

enum TemplateType: String, Codable, CaseIterable, Identifiable {
    case languageLearning
    case lectureNotes
    case examPrep
    case researchReview
    case meetingMinutes
    case projectBrief
    case writingAssistant
    case quickStudy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .languageLearning: return "Language Learning"
        case .lectureNotes: return "Lecture Notes"
        case .examPrep: return "Exam Prep"
        case .researchReview: return "Research Review"
        case .meetingMinutes: return "Meeting Minutes"
        case .projectBrief: return "Project Brief"
        case .writingAssistant: return "Writing Assistant"
        case .quickStudy: return "Quick Study"
        }
    }

    var description: String {
        switch self {
        case .languageLearning:
            return "Build vocabulary and practice with flashcards and quizzes."
        case .lectureNotes:
            return "Turn notes into questions, insights, key terms, and an outline."
        case .examPrep:
            return "Create study materials and self-test for an upcoming exam."
        case .researchReview:
            return "Review research with arguments, insights, outlines, and key terms."
        case .meetingMinutes:
            return "Summarize meetings into insights, key terms, and an outline."
        case .projectBrief:
            return "Clarify goals with a main question, insights, outline, and key terms."
        case .writingAssistant:
            return "Support writing with a main question, arguments, outline, and key terms."
        case .quickStudy:
            return "Fast review with key terms and a short quiz."
        }
    }

    // Backward compatibility: map legacy stored raw values to new catalog (no migration).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        if let value = TemplateType(rawValue: raw) {
            self = value
            return
        }

        // Legacy v1.0 values
        switch raw {
        case "lectureDebrief":
            self = .lectureNotes
        case "testPreparation":
            self = .examPrep
        case "researchAnalysis":
            self = .researchReview
        default:
            // Safe fallback
            self = .languageLearning
        }
    }
}


