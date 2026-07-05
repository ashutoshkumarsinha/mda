//
//  NoteTemplates.swift
//  MDE
//

import Foundation

enum NoteTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank = "Blank"
    case meeting = "Meeting"
    case daily = "Daily"
    case project = "Project"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .blank: "doc"
        case .meeting: "person.3"
        case .daily: "calendar"
        case .project: "folder"
        }
    }

    var content: String {
        switch self {
        case .blank:
            return ""
        case .meeting:
            return """
            # Meeting

            **Date:**
            **Attendees:**

            ## Agenda

            -

            ## Notes

            -

            ## Action items

            - [ ]
            """
        case .daily:
            return DailyNoteHelper.defaultContent()
        case .project:
            return """
            # Project

            ## Goal

            ## Milestones

            - [ ]

            ## Notes

            """
        }
    }
}
