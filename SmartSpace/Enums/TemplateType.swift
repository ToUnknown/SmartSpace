//
//  TemplateType.swift
//  SmartSpace
//
//  v2.0 scaffolding (v0.1): core template enum (no logic yet)
//

import Foundation

enum TemplateType: String, Codable, CaseIterable, Identifiable {
    case languageLearning = "languageLearning"
    case lectureDebrief = "lectureDebrief"
    case testPreparation = "testPreparation"
    case researchAnalysis = "researchAnalysis"

    var id: String { rawValue }
}


