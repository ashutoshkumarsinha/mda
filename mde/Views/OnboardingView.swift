//
//  OnboardingView.swift
//  MDE
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var step = 0

    private let steps: [(title: String, message: String, icon: String)] = [
        ("Write in markdown", "Use headings, lists, and **bold** text. Tags like #inbox organize notes in the sidebar.", "text.alignleft"),
        ("Link your notes", "Type [[Note Title]] to link notes. Tap a link to open it or create a new note.", "link"),
        ("Search everything", "Press ⌘F in the note list to search all note content instantly.", "magnifyingglass"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: steps[step].icon)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text(steps[step].title)
                    .font(.title2.weight(.semibold))
                Text(steps[step].message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            HStack {
                Button("Skip") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if step < steps.count - 1 {
                    Button("Next") {
                        step += 1
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 440)
    }

    private func dismiss() {
        UserDefaults.standard.set(true, forKey: OnboardingKeys.hasSeenOnboarding)
        isPresented = false
    }
}

enum OnboardingKeys {
    static let hasSeenOnboarding = "mde.hasSeenOnboarding"
}
