//
//  ContentView.swift
//  civicsflash
//
//  Created by Richard Stokes on 11/22/25.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Data models and loader
struct QuestionBank: Codable { let categories: [QuestionCategory] }
struct QuestionCategory: Codable, Hashable, Identifiable {
  let name: String
  let questions: [Question]
  var id: String { name }
}
struct Question: Codable, Identifiable, Hashable {
  let id: Int
  let question: String
  let answers: [String]
}
struct Card: Identifiable, Hashable {
  let id: Int
  let category: String
  let question: String
  let answers: [String]
}

// MARK: - Settings / Overrides
struct SettingsManager {
  static let governorKey = "setting_governor"
  static let capitalKey = "setting_capital"
  static let senatorKey = "setting_senator"
  static let representativeKey = "setting_representative"
  static let overrideIDs: Set<Int> = [23, 29, 61, 62]
  static let defaultVaryMessage = "Answers will vary by location. Please add via settings."

  static func currentOverrides() -> [Int: String] {
    let defaults = UserDefaults.standard
    var map: [Int: String] = [:]
    if let s = defaults.string(forKey: senatorKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !s.isEmpty
    {
      map[23] = s
    }
    if let r = defaults.string(forKey: representativeKey)?.trimmingCharacters(
      in: .whitespacesAndNewlines), !r.isEmpty
    {
      map[29] = r
    }
    if let g = defaults.string(forKey: governorKey)?.trimmingCharacters(
      in: .whitespacesAndNewlines), !g.isEmpty
    {
      map[61] = g
    }
    if let c = defaults.string(forKey: capitalKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !c.isEmpty
    {
      map[62] = c
    }
    return map
  }

  static func value(for id: Int) -> String? {
    return currentOverrides()[id]
  }

  static func save(governor: String, capital: String, senator: String, representative: String) {
    let d = UserDefaults.standard
    d.set(governor, forKey: governorKey)
    d.set(capital, forKey: capitalKey)
    d.set(senator, forKey: senatorKey)
    d.set(representative, forKey: representativeKey)
  }
}

enum DataLoader {
  static func loadCards() -> [Card] {
    guard let url = Bundle.main.url(forResource: "questions", withExtension: "json") else {
      print("❌ Error: Could not find questions.json in bundle")
      return []
    }
    do {
      let data = try Data(contentsOf: url)
      let decoded = try JSONDecoder().decode(QuestionBank.self, from: data)
      let flat = decoded.categories.flatMap { cat in
        cat.questions.map { q in
          Card(id: q.id, category: cat.name, question: q.question, answers: q.answers)
        }
      }
      // Apply settings overrides for certain question IDs
      let overrides = SettingsManager.currentOverrides()
      let adjusted = flat.map { card -> Card in
        if SettingsManager.overrideIDs.contains(card.id) {
          if let v = overrides[card.id], !v.isEmpty {
            return Card(id: card.id, category: card.category, question: card.question, answers: [v])
          } else {
            return Card(
              id: card.id, category: card.category, question: card.question,
              answers: [SettingsManager.defaultVaryMessage])
          }
        }
        return card
      }
      return adjusted
    } catch {
      print("❌ Error loading questions: \(error)")
      return []
    }
  }
}

// MARK: - View model
final class FlashcardViewModel: ObservableObject {
  @Published private(set) var allCards: [Card] = []
  @Published private(set) var deck: [Card] = []  // unseen, shuffled
  @Published private(set) var current: Card?
  @Published var isRevealed: Bool = false
  @Published var deckComplete: Bool = false
  @Published private(set) var transitionDirection: TransitionDirection = .forward

  private var history: [Card] = []  // cards we've seen
  private var currentIndex: Int = -1  // position in history

  let autoRevealDelay: TimeInterval = 30.0
  private var autoRevealWorkItem: DispatchWorkItem?

  var totalCount: Int? { allCards.isEmpty ? nil : allCards.count }
  var remainingCount: Int { deck.count + (current == nil ? 0 : 1) }
  var canGoBack: Bool { currentIndex > 0 }
  var canGoForward: Bool { currentIndex < history.count - 1 }

  enum TransitionDirection {
    case forward, backward
  }

  init() { reload() }

  func reload() {
    allCards = DataLoader.loadCards()
    resetDeck()
  }

  func resetDeck() {
    cancelAutoReveal()
    deckComplete = false
    isRevealed = false
    deck = allCards.shuffled()
    history = []
    currentIndex = -1
    nextCard()
  }

  func nextCard() {
    isRevealed = false
    cancelAutoReveal()
    transitionDirection = .forward

    // If we're in the middle of history, move forward in history
    if canGoForward {
      currentIndex += 1
      current = history[currentIndex]
    } else {
      // Get a new card from the deck
      if deck.isEmpty {
        // Completed the deck
        current = nil
        deckComplete = true
        return
      }
      let newCard = deck.popLast()

      // Add to history
      if let card = newCard {
        // If we're at the end of history, append
        if currentIndex == history.count - 1 {
          history.append(card)
          currentIndex = history.count - 1
        } else {
          // We were in the middle, so truncate forward history and add new card
          history = Array(history[0...currentIndex])
          history.append(card)
          currentIndex = history.count - 1
        }
      }

      current = newCard
    }

    scheduleAutoReveal()
  }

  func previousCard() {
    guard canGoBack else { return }
    isRevealed = false
    cancelAutoReveal()
    transitionDirection = .backward
    currentIndex -= 1
    current = history[currentIndex]
    scheduleAutoReveal()
  }

  func toggleReveal() {
    if isRevealed {
      nextCard()
    } else {
      isRevealed = true
      cancelAutoReveal()
    }
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

  @State private var showSettings = false

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [.indigo, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(spacing: 16) {
        header
        Spacer(minLength: 8)
        card
          .allowsHitTesting(!vm.deckComplete)
        Spacer(minLength: 16)
        footer
      }
      .padding()

      if vm.deckComplete {
        completionOverlay
          .transition(.opacity.combined(with: .scale))
      }
    }
    .sheet(isPresented: $showSettings) {
      SettingsView {
        vm.reload()  // re-read overrides and rebuild deck
      }
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("Civics Flash")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(.white)
        if let total = vm.totalCount {
          if vm.deckComplete {
            Text("Deck complete • \(total) total")
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.9))
          } else {
            Text("\(vm.remainingCount) left in deck • \(total) total")
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.8))
          }
        }
      }
      Spacer()
      HStack(spacing: 12) {
        Button {
          vm.resetDeck()
        } label: {
          Label(vm.deckComplete ? "Start Again" : "Reset", systemImage: "arrow.counterclockwise")
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .controlSize(.regular)

        Button {
          showSettings = true
        } label: {
          Label("Settings", systemImage: "gearshape.fill")
            .font(.subheadline.weight(.medium))
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .controlSize(.regular)
      }
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
              let isSwipeRight = value.translation.width > 0
              let isSwipeLeft = value.translation.width < 0

              if shouldSwipe {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                  let direction: CGFloat = isSwipeRight ? 1 : -1
                  dragOffset = CGSize(width: direction * 600, height: 0)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                  if isSwipeRight && vm.canGoBack {
                    vm.previousCard()
                  } else if isSwipeLeft {
                    vm.nextCard()
                  }
                  dragOffset = .zero
                }
              } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                  dragOffset = .zero
                }
              }
            }
        )
        .animation(.easeInOut, value: vm.isRevealed)
        .id(card.id)
      } else {
        ProgressView().tint(.white)
      }
    }
  }

  private func categoryChip(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.accentColor.opacity(0.9), in: Capsule())
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Image(systemName: "hand.tap")
        .foregroundStyle(.white.opacity(0.9))
      Text("Tap to reveal • Swipe left for next • Swipe right to go back")
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.9))
    }
    .padding(.vertical, 4)
  }
  // End-of-deck overlay
  private var completionOverlay: some View {
    VStack(spacing: 20) {
      Text("🎉")
        .font(.system(size: 96))
      Text("All cards complete!")
        .font(.title.weight(.bold))
        .foregroundStyle(.white)
      HStack(spacing: 12) {
        Button {
          vm.resetDeck()
        } label: {
          Text("Start Again")
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
      }
    }
    .padding(28)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 12)
    .padding()
  }
}

// MARK: - Settings UI
struct SettingsView: View {
  var onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var governor: String =
    UserDefaults.standard.string(forKey: SettingsManager.governorKey) ?? ""
  @State private var capital: String =
    UserDefaults.standard.string(forKey: SettingsManager.capitalKey) ?? ""
  @State private var senator: String =
    UserDefaults.standard.string(forKey: SettingsManager.senatorKey) ?? ""
  @State private var representative: String =
    UserDefaults.standard.string(forKey: SettingsManager.representativeKey) ?? ""

  var body: some View {
    NavigationStack {
      Form {
        Section("State leadership") {
          TextField("Governor", text: $governor)
            .textContentType(.name)
          TextField("One U.S. Senator", text: $senator)
            .textContentType(.name)
        }
        Section("State details") {
          TextField("State capital", text: $capital)
          TextField("U.S. Representative", text: $representative)
            .textContentType(.name)
        }
        Section(
          footer: Text(
            "To find your current representative, visit https://www.house.gov/representatives/find-your-representative"
          )
        ) { EmptyView() }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { saveAndClose() }.bold()
        }
      }
    }
  }

  private func saveAndClose() {
    SettingsManager.save(
      governor: governor.trimmingCharacters(in: .whitespacesAndNewlines),
      capital: capital.trimmingCharacters(in: .whitespacesAndNewlines),
      senator: senator.trimmingCharacters(in: .whitespacesAndNewlines),
      representative: representative.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    onSaved()
    dismiss()
  }
}

#Preview {
  ContentView()
}
