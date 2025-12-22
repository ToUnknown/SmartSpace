import Foundation

extension BlockType {
    var title: String {
        switch self {
        case .summary: return "Summary"
        case .flashcards: return "Flashcards"
        case .quiz: return "Quiz"
        case .keyTerms: return "Key Terms"
        case .mainQuestion: return "Main Question"
        case .insights: return "Insights"
        case .argumentCounterargument: return "Argument & Counterargument"
        case .contentOutline: return "Content Outline"
        }
    }
}


