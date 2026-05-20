//
//  ContentView.swift
//  civicsflash
//
//  Created by Richard Stokes on 11/22/25.
//

import AVFoundation
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

// MARK: - Flag Manager
struct FlagManager {
  static let flaggedCardsKey = "flagged_cards"
  static let showFlaggedOnlyKey = "show_flagged_only"

  static func loadFlaggedCards() -> Set<Int> {
    let defaults = UserDefaults.standard
    if let array = defaults.array(forKey: flaggedCardsKey) as? [Int] {
      return Set(array)
    }
    return []
  }

  static func saveFlaggedCards(_ ids: Set<Int>) {
    let defaults = UserDefaults.standard
    defaults.set(Array(ids), forKey: flaggedCardsKey)
  }

  static func loadShowFlaggedOnly() -> Bool {
    return UserDefaults.standard.bool(forKey: showFlaggedOnlyKey)
  }

  static func saveShowFlaggedOnly(_ value: Bool) {
    UserDefaults.standard.set(value, forKey: showFlaggedOnlyKey)
  }
}

// MARK: - Theme Manager
enum AppAppearance: String, CaseIterable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

final class ThemeManager: ObservableObject {
  static let appearanceKey = "app_appearance"
  static let patriotModeKey = "patriot_mode"

  @Published var appearance: AppAppearance {
    didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
  }
  @Published var patriotMode: Bool {
    didSet { UserDefaults.standard.set(patriotMode, forKey: Self.patriotModeKey) }
  }

  init() {
    let raw = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? AppAppearance.system.rawValue
    self.appearance = AppAppearance(rawValue: raw) ?? .system
    self.patriotMode = UserDefaults.standard.bool(forKey: Self.patriotModeKey)
  }
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

// MARK: - Speech Settings
struct SpeechSettingsManager {
  static let voiceIdentifierKey = "speech_voice_identifier"
  static let speechRateKey = "speech_rate"
  static let randomVoiceKey = "speech_random_voice"
  static let answerDelayKey = "speech_answer_delay"
  static let defaultRate: Float = 0.46
  static let defaultAnswerDelay: TimeInterval = 1.0
  static let minAnswerDelay: TimeInterval = 0.0
  static let maxAnswerDelay: TimeInterval = 6.0

  static func loadVoiceIdentifier() -> String? {
    UserDefaults.standard.string(forKey: voiceIdentifierKey)
  }

  static func saveVoiceIdentifier(_ id: String?) {
    UserDefaults.standard.set(id, forKey: voiceIdentifierKey)
  }

  static func loadSpeechRate() -> Float {
    let rate = UserDefaults.standard.float(forKey: speechRateKey)
    return rate > 0 ? rate : defaultRate
  }

  static func saveSpeechRate(_ rate: Float) {
    UserDefaults.standard.set(rate, forKey: speechRateKey)
  }

  static func loadRandomVoice() -> Bool {
    UserDefaults.standard.bool(forKey: randomVoiceKey)
  }

  static func saveRandomVoice(_ value: Bool) {
    UserDefaults.standard.set(value, forKey: randomVoiceKey)
  }

  static func loadAnswerDelay() -> TimeInterval {
    guard UserDefaults.standard.object(forKey: answerDelayKey) != nil else {
      return defaultAnswerDelay
    }
    let delay = UserDefaults.standard.double(forKey: answerDelayKey)
    return min(max(delay, minAnswerDelay), maxAnswerDelay)
  }

  static func saveAnswerDelay(_ delay: TimeInterval) {
    let clamped = min(max(delay, minAnswerDelay), maxAnswerDelay)
    UserDefaults.standard.set(clamped, forKey: answerDelayKey)
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

// MARK: - Speech Manager
final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  @Published private(set) var isActive = false
  @Published private(set) var isPaused = false
  @Published private(set) var currentPhase: SpeechPhase = .idle

  enum SpeechPhase: Equatable {
    case idle
    case speakingQuestion
    case pauseBeforeAnswer
    case speakingAnswer
    case pauseBeforeNext
  }

  private enum PauseReason: Hashable {
    case manual
    case holdingCard
    case appLifecycle
  }

  private enum UtteranceKind: Equatable {
    case question(cardID: Int)
    case answer(cardID: Int)
  }

  private let synthesizer = AVSpeechSynthesizer()
  private weak var viewModel: FlashcardViewModel?
  private var currentCard: Card?
  private var activeUtterance: AVSpeechUtterance?
  private var activeUtteranceKind: UtteranceKind?
  private var recoveryWorkItem: DispatchWorkItem?
  private var pauseWorkItem: DispatchWorkItem?
  private var pendingDelayAction: (() -> Void)?
  private var pendingDelayDeadline: Date?
  private var pendingDelayRemaining: TimeInterval?
  private var pauseReasons: Set<PauseReason> = []
  private var shuffledVoices: [AVSpeechSynthesisVoice] = []
  private var voiceIndex: Int = 0
  private let nextCardDelay: TimeInterval = 2.5
  private let recoveryDelay: TimeInterval = 0.7

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func toggle(with vm: FlashcardViewModel) {
    if isActive {
      toggleManualPause()
    } else {
      start(with: vm)
    }
  }

  func start(with vm: FlashcardViewModel) {
    stop()
    viewModel = vm
    isActive = true
    // Pre-shuffle voices for random cycling
    shuffledVoices = SpeechManager.availableEnglishVoices().shuffled()
    voiceIndex = 0
    vm.resetDeck(prioritizeFlagged: true)
    speakCurrentCard()
  }

  func stop() {
    isActive = false
    isPaused = false
    currentPhase = .idle
    currentCard = nil
    cancelPendingWork()
    pauseReasons.removeAll()
    synthesizer.stopSpeaking(at: .immediate)
  }

  func pauseForCardHold(_ isHolding: Bool) {
    if isHolding {
      addPauseReason(.holdingCard)
    } else {
      removePauseReason(.holdingCard)
    }
  }

  func handleScenePhase(_ phase: ScenePhase) {
    switch phase {
    case .active:
      pauseReasons.remove(.holdingCard)
      removePauseReason(.appLifecycle)
      scheduleStallRecovery()
    case .inactive, .background:
      addPauseReason(.appLifecycle)
    @unknown default:
      break
    }
  }

  private func toggleManualPause() {
    if pauseReasons.contains(.manual) {
      removePauseReason(.manual)
    } else {
      addPauseReason(.manual)
    }
  }

  private func addPauseReason(_ reason: PauseReason) {
    guard isActive else { return }
    let wasPaused = isPaused
    pauseReasons.insert(reason)
    isPaused = true
    if !wasPaused {
      pausePlayback()
    }
  }

  private func removePauseReason(_ reason: PauseReason) {
    guard isActive else { return }
    pauseReasons.remove(reason)
    guard pauseReasons.isEmpty else { return }
    isPaused = false
    resumePlayback()
  }

  private func speakCurrentCard() {
    guard isActive, let vm = viewModel, let card = vm.current else {
      stop()
      return
    }
    currentCard = card
    currentPhase = .speakingQuestion
    vm.isRevealed = false
    speak(card.question, kind: .question(cardID: card.id))
  }

  private func answerText(for card: Card) -> String {
    card.answers.prefix(3).joined(separator: ". ")
  }

  private func speak(_ text: String, kind: UtteranceKind) {
    let cleaned =
      text.replacingOccurrences(
        of: "\\s*\\(\\d+\\)", with: "", options: .regularExpression)
    let utterance = AVSpeechUtterance(string: cleaned)
    if SpeechSettingsManager.loadRandomVoice(), !shuffledVoices.isEmpty {
      utterance.voice = shuffledVoices[voiceIndex % shuffledVoices.count]
    } else {
      let voiceId = SpeechSettingsManager.loadVoiceIdentifier()
      if let id = voiceId, !id.isEmpty,
        let voice = AVSpeechSynthesisVoice(identifier: id)
      {
        utterance.voice = voice
      } else {
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
      }
    }
    utterance.rate = SpeechSettingsManager.loadSpeechRate()
    utterance.pitchMultiplier = 1.0
    activeUtterance = utterance
    activeUtteranceKind = kind
    synthesizer.speak(utterance)
    if isPaused {
      pausePlayback()
    }
  }

  /// Advance to the next random voice for the next card
  private func advanceVoice() {
    voiceIndex += 1
  }

  private func cancelPendingWork() {
    pauseWorkItem?.cancel()
    recoveryWorkItem?.cancel()
    pauseWorkItem = nil
    recoveryWorkItem = nil
    pendingDelayAction = nil
    pendingDelayDeadline = nil
    pendingDelayRemaining = nil
    activeUtterance = nil
    activeUtteranceKind = nil
  }

  private func scheduleAfterDelay(_ delay: TimeInterval, action: @escaping () -> Void) {
    cancelPendingWork()
    pendingDelayAction = action
    if isPaused {
      pendingDelayRemaining = delay
      return
    }
    schedulePendingDelay(after: delay)
  }

  private func schedulePendingDelay(after delay: TimeInterval) {
    let clampedDelay = max(0, delay)
    pendingDelayRemaining = clampedDelay
    pendingDelayDeadline = Date().addingTimeInterval(clampedDelay)
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.isActive, !self.isPaused else { return }
      let action = self.pendingDelayAction
      self.pauseWorkItem = nil
      self.pendingDelayAction = nil
      self.pendingDelayDeadline = nil
      self.pendingDelayRemaining = nil
      action?()
    }
    pauseWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + clampedDelay, execute: work)
  }

  private func pausePlayback() {
    if synthesizer.isSpeaking && !synthesizer.isPaused {
      synthesizer.pauseSpeaking(at: .immediate)
    }
    pausePendingDelay()
  }

  private func resumePlayback() {
    var resumedSpeech = false
    if synthesizer.isPaused {
      resumedSpeech = synthesizer.continueSpeaking()
    }
    resumePendingDelay()
    if !resumedSpeech {
      scheduleStallRecovery()
    }
  }

  private func pausePendingDelay() {
    guard pendingDelayAction != nil else { return }
    if let deadline = pendingDelayDeadline {
      pendingDelayRemaining = max(0, deadline.timeIntervalSinceNow)
    }
    pauseWorkItem?.cancel()
    pauseWorkItem = nil
    pendingDelayDeadline = nil
  }

  private func resumePendingDelay() {
    guard pendingDelayAction != nil, let remaining = pendingDelayRemaining else { return }
    schedulePendingDelay(after: remaining)
  }

  private func speakAnswer(for card: Card, vm: FlashcardViewModel) {
    withAnimation(.spring()) { vm.isRevealed = true }
    currentPhase = .speakingAnswer
    let answersText = answerText(for: card)
    guard !answersText.isEmpty else {
      scheduleNextCard()
      return
    }
    speak(answersText, kind: .answer(cardID: card.id))
  }

  private func scheduleAnswer(for card: Card, vm: FlashcardViewModel) {
    currentPhase = .pauseBeforeAnswer
    scheduleAfterDelay(SpeechSettingsManager.loadAnswerDelay()) { [weak self, weak vm] in
      guard let self = self, self.isActive, let vm = vm else { return }
      self.speakAnswer(for: card, vm: vm)
    }
  }

  private func scheduleNextCard() {
    currentPhase = .pauseBeforeNext
    scheduleAfterDelay(nextCardDelay) { [weak self] in
      guard let self = self, self.isActive, let vm = self.viewModel else { return }
      self.currentPhase = .idle
      vm.nextCard(autoReveal: false)
      if vm.deckComplete {
        self.stop()
      } else {
        self.advanceVoice()
        self.speakCurrentCard()
      }
    }
  }

  private func recoverPendingDelayIfNeeded() -> Bool {
    guard pendingDelayAction != nil else { return false }
    if pauseWorkItem == nil {
      schedulePendingDelay(after: pendingDelayRemaining ?? 0)
    }
    return true
  }

  private func scheduleStallRecovery() {
    recoveryWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.recoveryWorkItem = nil
      self.recoverIfStalled()
    }
    recoveryWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + recoveryDelay, execute: work)
  }

  private func recoverIfStalled() {
    guard isActive, !isPaused else { return }
    if synthesizer.isPaused {
      if synthesizer.continueSpeaking() {
        return
      }
    }
    if synthesizer.isSpeaking { return }
    if recoverPendingDelayIfNeeded() { return }

    guard let vm = viewModel else {
      stop()
      return
    }

    switch currentPhase {
    case .speakingQuestion:
      if let card = currentCard ?? vm.current {
        currentCard = card
        speak(card.question, kind: .question(cardID: card.id))
      } else {
        stop()
      }
    case .pauseBeforeAnswer:
      if let card = currentCard ?? vm.current {
        currentCard = card
        scheduleAnswer(for: card, vm: vm)
      } else {
        stop()
      }
    case .speakingAnswer:
      if let card = currentCard ?? vm.current {
        currentCard = card
        speakAnswer(for: card, vm: vm)
      } else {
        stop()
      }
    case .pauseBeforeNext:
      scheduleNextCard()
    case .idle:
      if vm.deckComplete {
        stop()
      } else if let _ = vm.current {
        speakCurrentCard()
      } else {
        stop()
      }
    }
  }

  // MARK: AVSpeechSynthesizerDelegate
  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    guard isActive, utterance === activeUtterance,
      let utteranceKind = activeUtteranceKind,
      let card = currentCard,
      let vm = viewModel
    else { return }

    activeUtterance = nil
    activeUtteranceKind = nil

    switch utteranceKind {
    case .question(let cardID) where currentPhase == .speakingQuestion && card.id == cardID:
      scheduleAnswer(for: card, vm: vm)
    case .answer(let cardID) where currentPhase == .speakingAnswer && card.id == cardID:
      scheduleNextCard()
    default:
      break
    }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    guard utterance === activeUtterance else { return }
    activeUtterance = nil
    activeUtteranceKind = nil
    guard isActive, !isPaused else { return }
    DispatchQueue.main.async { [weak self] in
      self?.scheduleStallRecovery()
    }
  }

  /// Known novelty / non-human voice names bundled with iOS/macOS
  private static let noveltyVoiceNames: Set<String> = [
    "Bells", "Boing", "Bubbles", "Cellos", "Trinoids",
    "Whisper", "Wobble", "Zarvox", "Albert", "Bad News",
    "Bahh", "Good News", "Jester", "Organ", "Superstar",
    "Ralph", "Kathy", "Junior", "Fred", "Hysterical",
    "Deranged", "Pipe Organ",
  ]

  static func availableEnglishVoices() -> [AVSpeechSynthesisVoice] {
    let filtered =
      AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix("en") && !noveltyVoiceNames.contains($0.name) }
    // Deduplicate by name, keeping the highest quality variant
    var bestByName: [String: AVSpeechSynthesisVoice] = [:]
    for voice in filtered {
      if let existing = bestByName[voice.name] {
        if voice.quality.rawValue > existing.quality.rawValue {
          bestByName[voice.name] = voice
        }
      } else {
        bestByName[voice.name] = voice
      }
    }
    return bestByName.values.sorted { $0.name < $1.name }
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
  @Published var flaggedCardIDs: Set<Int> = []
  @Published var showFlaggedOnly: Bool = false

  private var history: [Card] = []  // cards we've seen
  private var currentIndex: Int = -1  // position in history

  let autoRevealDelay: TimeInterval = 30.0
  private var autoRevealWorkItem: DispatchWorkItem?

  var totalCount: Int? { allCards.isEmpty ? nil : allCards.count }
  var remainingCount: Int { deck.count + (current == nil ? 0 : 1) }
  var canGoBack: Bool { currentIndex > 0 }
  var canGoForward: Bool { currentIndex < history.count - 1 }
  var hasFlaggedCards: Bool { !flaggedCardIDs.isEmpty }

  enum TransitionDirection {
    case forward, backward
  }

  init() {
    loadFlaggedCards()
    loadShowFlaggedOnly()
    reload()
  }

  func reload() {
    allCards = DataLoader.loadCards()
    resetDeck()
  }

  func resetDeck(prioritizeFlagged: Bool = false) {
    cancelAutoReveal()
    deckComplete = false
    isRevealed = false

    // Filter cards based on showFlaggedOnly setting
    let cardsToUse =
      showFlaggedOnly
      ? allCards.filter { flaggedCardIDs.contains($0.id) }
      : allCards

    if prioritizeFlagged && !showFlaggedOnly && !flaggedCardIDs.isEmpty {
      // Flagged cards at end of array so they are popped first by popLast()
      let rest = cardsToUse.filter { !flaggedCardIDs.contains($0.id) }.shuffled()
      let flagged = cardsToUse.filter { flaggedCardIDs.contains($0.id) }.shuffled()
      deck = rest + flagged
    } else {
      deck = cardsToUse.shuffled()
    }
    history = []
    currentIndex = -1
    nextCard()
  }

  func toggleFlag(for cardID: Int) {
    if flaggedCardIDs.contains(cardID) {
      flaggedCardIDs.remove(cardID)
    } else {
      flaggedCardIDs.insert(cardID)
    }
    saveFlaggedCards()
  }

  func isFlagged(_ cardID: Int) -> Bool {
    return flaggedCardIDs.contains(cardID)
  }

  func toggleShowFlaggedOnly() {
    showFlaggedOnly.toggle()
    saveShowFlaggedOnly()
    resetDeck()
  }

  func clearAllFlags() {
    flaggedCardIDs.removeAll()
    saveFlaggedCards()
    if showFlaggedOnly {
      showFlaggedOnly = false
      saveShowFlaggedOnly()
      resetDeck()
    }
  }

  private func loadFlaggedCards() {
    flaggedCardIDs = FlagManager.loadFlaggedCards()
  }

  private func saveFlaggedCards() {
    FlagManager.saveFlaggedCards(flaggedCardIDs)
  }

  private func loadShowFlaggedOnly() {
    showFlaggedOnly = FlagManager.loadShowFlaggedOnly()
  }

  private func saveShowFlaggedOnly() {
    FlagManager.saveShowFlaggedOnly(showFlaggedOnly)
  }

  func nextCard(autoReveal: Bool = true) {
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

    if autoReveal { scheduleAutoReveal() }
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

// MARK: - Patriot Background
struct PatriotBackgroundView: View {
  // Authentic US flag colors
  private let oldGloryRed = Color(red: 0.698, green: 0.132, blue: 0.203)
  private let oldGloryBlue = Color(red: 0.234, green: 0.234, blue: 0.430)

  var body: some View {
    GeometryReader { geo in
      // Render the flag at true 1.9:1 aspect ratio, positioned to cover background naturally.
      // Using a fixed flag aspect and letting it overflow keeps proportions correct.
      let flagHeight = geo.size.height
      let flagWidth = flagHeight * 1.9  // official US flag proportion
      TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
        Canvas { ctx, size in
          let time = context.date.timeIntervalSinceReferenceDate
          let timePhase: Double = time * 0.5
          drawFlag(ctx: ctx, size: size, time: timePhase)
        }
        .frame(width: flagWidth, height: flagHeight)
        .offset(x: (geo.size.width - flagWidth) / 2)
      }
    }
    .opacity(0.45)
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }

  private func drawFlag(ctx: GraphicsContext, size: CGSize, time: Double) {
    let stripeH: CGFloat = size.height / 13.0
    let twoPi: Double = 2.0 * .pi
    let waveAmplitude: CGFloat = size.height * 0.018
    let waveFreq: Double = 1.5  // waves per flag width

    // Draw stripes
    for i in 0..<13 {
      let y: CGFloat = CGFloat(i) * stripeH
      let iOffset: Double = Double(i) * 0.08
      var path = Path()
      let steps = 60
      // top edge
      for s in 0...steps {
        let x: CGFloat = size.width * CGFloat(s) / CGFloat(steps)
        let xNorm: Double = Double(x / size.width)
        let angle: Double = xNorm * twoPi * waveFreq + time + iOffset
        let wave: CGFloat = CGFloat(sin(angle)) * waveAmplitude
        let pt = CGPoint(x: x, y: y + wave)
        if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
      }
      // bottom edge
      let iNext: Double = Double(i + 1) * 0.08
      for s in stride(from: steps, through: 0, by: -1) {
        let x: CGFloat = size.width * CGFloat(s) / CGFloat(steps)
        let xNorm: Double = Double(x / size.width)
        let angle: Double = xNorm * twoPi * waveFreq + time + iNext
        let wave: CGFloat = CGFloat(sin(angle)) * waveAmplitude
        path.addLine(to: CGPoint(x: x, y: y + stripeH + wave))
      }
      path.closeSubpath()
      let isRed = i % 2 == 0
      ctx.fill(path, with: .color(isRed ? oldGloryRed : .white))
    }

    // Canton: 0.76 of hoist side (height of 7 stripes) × 0.4 of width
    let cantonW: CGFloat = size.width * 0.4
    let cantonH: CGFloat = stripeH * 7

    // Build canton path that follows the wave
    var cantonPath = Path()
    let steps = 40
    // top edge of canton
    for s in 0...steps {
      let x: CGFloat = cantonW * CGFloat(s) / CGFloat(steps)
      let xNorm: Double = Double(x / size.width)
      let angle: Double = xNorm * twoPi * waveFreq + time
      let wave: CGFloat = CGFloat(sin(angle)) * waveAmplitude
      let pt = CGPoint(x: x, y: wave)
      if s == 0 { cantonPath.move(to: pt) } else { cantonPath.addLine(to: pt) }
    }
    // bottom edge of canton
    let bottomOffset: Double = 7 * 0.08
    for s in stride(from: steps, through: 0, by: -1) {
      let x: CGFloat = cantonW * CGFloat(s) / CGFloat(steps)
      let xNorm: Double = Double(x / size.width)
      let angle: Double = xNorm * twoPi * waveFreq + time + bottomOffset
      let wave: CGFloat = CGFloat(sin(angle)) * waveAmplitude
      cantonPath.addLine(to: CGPoint(x: x, y: cantonH + wave))
    }
    cantonPath.closeSubpath()
    ctx.fill(cantonPath, with: .color(oldGloryBlue))

    // 50 stars in 9 rows: 6-5-6-5-6-5-6-5-6
    // Horizontal spacing: 6-star rows use 12 equal parts, 5-star rows use 10 equal parts
    // Vertical: 9 rows + padding, use 10 equal parts of canton height
    let starRadius: CGFloat = min(cantonW, cantonH) * 0.035
    let vStep = cantonH / 10.0
    for rowIdx in 0..<9 {
      let isLongRow = rowIdx % 2 == 0  // rows 0,2,4,6,8 have 6 stars
      let count = isLongRow ? 6 : 5
      let hStep = cantonW / CGFloat(isLongRow ? 12 : 10)
      let startX: CGFloat = isLongRow ? hStep : hStep
      let y: CGFloat = vStep * CGFloat(rowIdx + 1)
      for col in 0..<count {
        let x: CGFloat = startX + hStep * 2.0 * CGFloat(col)
        let xNorm: Double = Double(x / size.width)
        let angle: Double = xNorm * twoPi * waveFreq + time + Double(rowIdx) * 0.04
        let wave: CGFloat = CGFloat(sin(angle)) * waveAmplitude
        let starPath = starShape(
          center: CGPoint(x: x, y: y + wave),
          points: 5,
          innerRadius: starRadius * 0.4,
          outerRadius: starRadius
        )
        ctx.fill(starPath, with: .color(.white))
      }
    }
  }

  private func starShape(center: CGPoint, points: Int, innerRadius: CGFloat, outerRadius: CGFloat)
    -> Path
  {
    var path = Path()
    let angleStep: CGFloat = .pi / CGFloat(points)
    for i in 0..<(points * 2) {
      let angle: CGFloat = CGFloat(i) * angleStep - .pi / 2
      let radius: CGFloat = i % 2 == 0 ? outerRadius : innerRadius
      let point = CGPoint(
        x: center.x + cos(angle) * radius,
        y: center.y + sin(angle) * radius
      )
      if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }
}

// MARK: - Themed Background
struct ThemedBackground: View {
  @ObservedObject var theme: ThemeManager
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      if theme.patriotMode {
        // Dark base so the flag reads well and whites don't blow out
        Color(red: 0.12, green: 0.12, blue: 0.18)
          .ignoresSafeArea()
        PatriotBackgroundView()
        // Contrast scrims so overlaid text stays legible over any flag region
        LinearGradient(
          colors: [
            Color.black.opacity(0.55),
            Color.black.opacity(0.15),
            Color.black.opacity(0.0),
            Color.black.opacity(0.15),
            Color.black.opacity(0.55),
          ],
          startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
      } else {
        if colorScheme == .dark {
          LinearGradient(
            colors: [Color(red: 0.08, green: 0.05, blue: 0.2),
                     Color(red: 0.05, green: 0.1, blue: 0.2),
                     Color(red: 0.05, green: 0.15, blue: 0.15)],
            startPoint: .topLeading, endPoint: .bottomTrailing
          )
          .ignoresSafeArea()
        } else {
          LinearGradient(
            colors: [.indigo, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing
          )
          .ignoresSafeArea()
        }
      }
    }
  }
}

struct ContentView: View {
  @StateObject private var vm = FlashcardViewModel()
  @StateObject private var speechManager = SpeechManager()
  @StateObject private var theme = ThemeManager()
  @Environment(\.scenePhase) private var scenePhase
  @State private var dragOffset: CGSize = .zero
  private let swipeThreshold: CGFloat = 80

  @State private var showSettings = false

  var body: some View {
    ZStack {
      ThemedBackground(theme: theme)

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
    .preferredColorScheme(theme.appearance.colorScheme)
    .onChange(of: scenePhase) { _, phase in
      speechManager.handleScenePhase(phase)
    }
    .sheet(isPresented: $showSettings) {
      SettingsView(
        onSaved: {
          vm.reload()  // re-read overrides and rebuild deck
        }, viewModel: vm, theme: theme)
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
            if vm.showFlaggedOnly {
              Text("\(vm.remainingCount) left • \(vm.flaggedCardIDs.count) flagged")
                .font(.subheadline)
                .foregroundStyle(.orange)
            } else {
              Text("\(vm.remainingCount) left in deck • \(total) total")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            }
          }
        }
      }
      Spacer()
      HStack(spacing: 8) {
        Button {
          speechManager.toggle(with: vm)
        } label: {
          Image(systemName: readAloudIconName)
            .font(.subheadline.weight(.medium))
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .tint(readAloudTint)
        .controlSize(.regular)
        .accessibilityLabel(readAloudAccessibilityLabel)

        Button {
          speechManager.stop()
          vm.resetDeck()
        } label: {
          Image(systemName: "arrow.counterclockwise")
            .font(.subheadline.weight(.medium))
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .controlSize(.regular)
        .accessibilityLabel(vm.deckComplete ? "Start Again" : "Reset")

        Button {
          speechManager.stop()
          showSettings = true
        } label: {
          Image(systemName: "gearshape.fill")
            .font(.subheadline.weight(.medium))
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .controlSize(.regular)
        .accessibilityLabel("Settings")
      }
    }
  }

  private var readAloudIconName: String {
    if !speechManager.isActive { return "speaker.wave.2.fill" }
    return speechManager.isPaused ? "play.fill" : "pause.fill"
  }

  private var readAloudTint: Color {
    if !speechManager.isActive { return .white }
    return speechManager.isPaused ? .green : .orange
  }

  private var readAloudAccessibilityLabel: String {
    if !speechManager.isActive { return "Read aloud" }
    return speechManager.isPaused ? "Resume reading" : "Pause reading"
  }

  private var card: some View {
    Group {
      if let card = vm.current {
        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 12)

          VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
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
              }
              .padding(24)
              .padding(.bottom, 8)
            }

            HStack {
              Spacer()
              Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                  vm.toggleFlag(for: card.id)
                }
              } label: {
                Image(systemName: vm.isFlagged(card.id) ? "flag.fill" : "flag")
                  .font(.title2)
                  .foregroundStyle(vm.isFlagged(card.id) ? Color.orange : Color.secondary)
              }
              .buttonStyle(.plain)
              Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: 480)
        .onTapGesture {
          guard !speechManager.isActive else { return }
          withAnimation(.spring()) { vm.toggleReveal() }
        }
        .offset(dragOffset)
        .gesture(
          DragGesture()
            .onChanged { value in
              guard !speechManager.isActive else { return }
              dragOffset = CGSize(width: value.translation.width, height: 0)
            }
            .onEnded { value in
              guard !speechManager.isActive else {
                dragOffset = .zero
                return
              }
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
        .onLongPressGesture(
          minimumDuration: 0.1,
          maximumDistance: 50,
          pressing: { isPressing in
            guard speechManager.isActive else { return }
            speechManager.pauseForCardHold(isPressing)
          },
          perform: {}
        )
        .onDisappear {
          speechManager.pauseForCardHold(false)
        }
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
    Group {
      if speechManager.isActive {
        HStack(spacing: 12) {
          Image(systemName: speechManager.isPaused ? "pause.fill" : "speaker.wave.2.fill")
            .foregroundStyle(speechManager.isPaused ? .green : .orange)
          Text(speechManager.isPaused ? "Read aloud paused" : "Reading aloud\u{2026} hold card to pause")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.vertical, 4)
      } else {
        HStack(spacing: 12) {
          Image(systemName: "hand.tap")
            .foregroundStyle(.white.opacity(0.9))
          Text("Tap to reveal • Swipe left for next • Swipe right to go back")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.vertical, 4)
      }
    }
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
  @ObservedObject var viewModel: FlashcardViewModel
  @ObservedObject var theme: ThemeManager
  @Environment(\.dismiss) private var dismiss
  @State private var governor: String =
    UserDefaults.standard.string(forKey: SettingsManager.governorKey) ?? ""
  @State private var capital: String =
    UserDefaults.standard.string(forKey: SettingsManager.capitalKey) ?? ""
  @State private var senator: String =
    UserDefaults.standard.string(forKey: SettingsManager.senatorKey) ?? ""
  @State private var representative: String =
    UserDefaults.standard.string(forKey: SettingsManager.representativeKey) ?? ""
  @State private var showResetConfirmation = false
  @State private var selectedVoiceIdentifier: String =
    SpeechSettingsManager.loadVoiceIdentifier() ?? ""
  @State private var speechRate: Float = SpeechSettingsManager.loadSpeechRate()
  @State private var answerDelay: TimeInterval = SpeechSettingsManager.loadAnswerDelay()
  @State private var randomVoice: Bool = SpeechSettingsManager.loadRandomVoice()
  private let availableVoices = SpeechManager.availableEnglishVoices()

  var body: some View {
    NavigationStack {
      Form {
        Section("Appearance") {
          Picker("Theme", selection: $theme.appearance) {
            ForEach(AppAppearance.allCases, id: \.self) { option in
              Text(option.rawValue).tag(option)
            }
          }
          .pickerStyle(.segmented)

          Toggle(isOn: $theme.patriotMode) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Patriot Theme")
                .font(.body)
              Text("Star-spangled banner background")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        Section("Flagged Cards") {
          Toggle(
            isOn: Binding(
              get: { viewModel.showFlaggedOnly },
              set: { _ in viewModel.toggleShowFlaggedOnly() }
            )
          ) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Show Flagged Only")
                .font(.body)
              Text("Only show cards you've flagged")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          .disabled(!viewModel.hasFlaggedCards)

          Button(role: .destructive) {
            showResetConfirmation = true
          } label: {
            HStack {
              Text("Clear Flagged Cards")
              Spacer()
              if viewModel.hasFlaggedCards {
                Text("\(viewModel.flaggedCardIDs.count)")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
          .disabled(!viewModel.hasFlaggedCards)
        }

        Section("Read Aloud") {
          Toggle(isOn: $randomVoice) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Random Voice")
                .font(.body)
              Text("Use a different voice for each card")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }

          if !randomVoice {
            VStack(alignment: .leading, spacing: 4) {
              Text("Voice")
                .font(.caption)
                .foregroundColor(.secondary)
              Picker("Voice", selection: $selectedVoiceIdentifier) {
                Text("System Default").tag("")
                ForEach(availableVoices, id: \.identifier) { voice in
                  Text(voice.name).tag(voice.identifier)
                }
              }
            }
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Reading Speed")
              .font(.caption)
              .foregroundColor(.secondary)
            HStack {
              Image(systemName: "tortoise")
                .foregroundColor(.secondary)
              Slider(value: $speechRate, in: 0.3...0.6, step: 0.02)
              Image(systemName: "hare")
                .foregroundColor(.secondary)
            }
          }

          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text("Answer Delay")
                .font(.caption)
                .foregroundColor(.secondary)
              Spacer()
              Text(formatAnswerDelay(answerDelay))
                .font(.caption)
                .foregroundColor(.secondary)
            }
            HStack {
              Image(systemName: "timer")
                .foregroundColor(.secondary)
              Slider(
                value: $answerDelay,
                in: SpeechSettingsManager.minAnswerDelay...SpeechSettingsManager.maxAnswerDelay,
                step: 0.25
              )
              Image(systemName: "hourglass")
                .foregroundColor(.secondary)
            }
          }
        }

        Section("State leadership") {
          VStack(alignment: .leading, spacing: 4) {
            Text("Governor")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Enter governor name", text: $governor)
              .textContentType(.name)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("U.S. Senator")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Enter senator name", text: $senator)
              .textContentType(.name)
          }
        }

        Section(
          header: Text("State details"),
          footer: Text(
            "To find your current representative, visit https://www.house.gov/representatives/find-your-representative"
          )
        ) {
          VStack(alignment: .leading, spacing: 4) {
            Text("State Capital")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Enter state capital", text: $capital)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("U.S. Representative")
              .font(.caption)
              .foregroundColor(.secondary)
            TextField("Enter representative name", text: $representative)
              .textContentType(.name)
          }
        }.padding(.bottom, 8)

        Section("About") {
          VStack(alignment: .leading, spacing: 8) {
            Text(
              "Civics Flash is completely free for everyone. Donations do not unlock any features or content."
            )
            .font(.footnote)
            .foregroundColor(.secondary)

            Text("If you find the app useful, you can optionally support the developer:")
              .font(.footnote)
              .foregroundColor(.secondary)

            Link(destination: URL(string: "https://buymeacoffee.com/richstokes")!) {
              Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
            }
          }
          .padding(.vertical, 8)
        }
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
      .confirmationDialog(
        "Reset Flagged Cards",
        isPresented: $showResetConfirmation,
        titleVisibility: .visible
      ) {
        Button("Reset All Flags", role: .destructive) {
          viewModel.clearAllFlags()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will remove all flags from cards. This action cannot be undone.")
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
    SpeechSettingsManager.saveVoiceIdentifier(
      selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier)
    SpeechSettingsManager.saveSpeechRate(speechRate)
    SpeechSettingsManager.saveAnswerDelay(answerDelay)
    SpeechSettingsManager.saveRandomVoice(randomVoice)
    onSaved()
    dismiss()
  }

  private func formatAnswerDelay(_ delay: TimeInterval) -> String {
    delay == 1.0 ? "1 second" : String(format: "%.2g seconds", delay)
  }
}

#Preview {
  ContentView()
}
