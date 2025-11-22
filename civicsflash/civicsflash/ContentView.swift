//
//  ContentView.swift
//  civicsflash
//
//  Created by Richard Stokes on 11/22/25.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Data models and loader (kept in this file to avoid Xcode target linking issues)
struct QuestionBank: Codable { let categories: [QuestionCategory] }
struct QuestionCategory: Codable, Hashable, Identifiable { let name: String; let questions: [Question]; var id: String { name } }
struct Question: Codable, Identifiable, Hashable { let id: Int; let question: String; let answers: [String] }
struct Card: Identifiable, Hashable { let id: Int; let category: String; let question: String; let answers: [String] }

enum DataLoader {
    static func loadCards() -> [Card] {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json") else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(QuestionBank.self, from: data)
            return decoded.categories.flatMap { cat in
                cat.questions.map { q in Card(id: q.id, category: cat.name, question: q.question, answers: q.answers) }
            }
        } catch {
            return []
        }
    }
}

// MARK: - View model
final class FlashcardViewModel: ObservableObject {
    @Published private(set) var allCards: [Card] = []
    @Published private(set) var deck: [Card] = [] // unseen, shuffled
    @Published private(set) var current: Card?
    @Published var isRevealed: Bool = false

    let autoRevealDelay: TimeInterval = 10.0
    private var autoRevealWorkItem: DispatchWorkItem?

    var totalCount: Int? { allCards.isEmpty ? nil : allCards.count }
    var remainingCount: Int { deck.count + (current == nil ? 0 : 1) }

    init() { reload() }

    func reload() {
        allCards = DataLoader.loadCards()
        resetDeck()
    }

    func resetDeck() {
        deck = allCards.shuffled()
        nextCard()
    }

    func nextCard() {
        isRevealed = false
        cancelAutoReveal()
        if deck.isEmpty { deck = allCards.shuffled() }
        current = deck.popLast()
        scheduleAutoReveal()
    }

    func toggleReveal() {
        if isRevealed { isRevealed = false; scheduleAutoReveal() }
        else { isRevealed = true; cancelAutoReveal() }
    }

    private func scheduleAutoReveal() {
        cancelAutoReveal()
        guard current != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.isRevealed = true }
        autoRevealWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoRevealDelay, execute: work)
    }

    private func cancelAutoReveal() {
        autoRevealWorkItem?.cancel()
        autoRevealWorkItem = nil
    }
}

struct ContentView: View {
    @StateObject private var vm = FlashcardViewModel()
    @State private var dragOffset: CGSize = .zero
    private let swipeThreshold: CGFloat = 80

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                Spacer(minLength: 8)
                card
                Spacer(minLength: 16)
                footer
            }
            .padding()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Civics Flash")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                if let total = vm.totalCount {
                    Text("\(vm.remainingCount) left in deck • \(total) total")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer()
            Button("Reset") { vm.resetDeck() }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
        }
    }

    private var card: some View {
        Group {
            if let card = vm.current {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 12)

                    VStack(alignment: .leading, spacing: 16) {
                        categoryChip(card.category)
                        Text(card.question)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if vm.isRevealed {
                            VStack(alignment: .leading, spacing: 8) {
ForEach(card.answers, id: \.self) { ans in
                                    HStack(alignment: .top, spacing: 8) {
Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                            .padding(.top, 8)
                                        Text(ans)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            Text("Tap card to reveal…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: 480)
                .onTapGesture { withAnimation(.spring()) { vm.toggleReveal() } }
                .offset(dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = CGSize(width: value.translation.width, height: 0)
                        }
                        .onEnded { value in
                            let shouldSwipe = abs(value.translation.width) > swipeThreshold
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if shouldSwipe {
                                    let direction: CGFloat = value.translation.width >= 0 ? 1 : -1
                                    dragOffset = CGSize(width: direction * 600, height: 0)
                                } else {
                                    dragOffset = .zero
                                }
                            }

                            if shouldSwipe {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    dragOffset = .zero
                                    vm.nextCard()
                                }
                            }
                        }
                )
                .animation(.easeInOut, value: vm.isRevealed)
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    private func categoryChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
 .background(Color.accentColor.opacity(0.9), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .foregroundStyle(.white.opacity(0.9))
            Text("Tap to reveal • Swipe left/right for next")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
