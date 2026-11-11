import UIKit

final class KeyboardViewController: UIInputViewController {
    private let bar = SuggestionBar()
    private let keyboardView = KeyboardView()
    private let store = DictionaryStore.shared
    private let predictor = Predictor.shared

    private var shift: ShiftState = .off
    private var page: KeyboardPage = .letters
    private var heightConstraint: NSLayoutConstraint?

    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast
    /// Po wybraniu podpowiedzi dodajemy spację; znak interpunkcyjny ją „zjada”.
    private var pendingAutoSpace = false
    private var lastAutoFix: AutoFix?
    private var dictationTimer: Timer?
    private var didShowAccessHint = false

    private struct AutoFix {
        let original: String
        let replacement: String
        let terminator: String
    }

    private static let barHeight: CGFloat = 44
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
    private static let spaceEatingPunctuation: Set<String> = [".", ",", "?", "!", ":", ";"]

    // MARK: - Cykl życia

    override func viewDidLoad() {
        super.viewDidLoad()

        bar.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        view.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
            keyboardView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let height = view.heightAnchor.constraint(equalToConstant: desiredHeight())
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        keyboardView.onKey = { [weak self] in self?.handle($0) }
        keyboardView.onAlternate = { [weak self] in self?.insertCharacter($0) }
        keyboardView.onBackspace = { [weak self] in self?.handleBackspace() }
        keyboardView.configureGlobe = { [weak self] control in
            guard let self else { return }
            control.addTarget(self, action: #selector(self.handleInputModeList(from:with:)),
                              for: .allTouchEvents)
        }
        bar.onSelect = { [weak self] in self?.pick($0) }
        bar.onBlock = { [weak self] in
            self?.store.block($0.text)
            self?.updateSuggestions()
        }

        predictor.loadIfNeeded { [weak self] in self?.updateSuggestions() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.reload()
        page = startPage()
        keyboardView.configure(page: page, showGlobe: needsInputModeSwitchKey)
        updateAutoShift()
        updateSuggestions()
        insertPendingDictation()
        // Tekst podyktowany w aplikacji może pojawić się chwilę po powrocie.
        dictationTimer?.invalidate()
        dictationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.insertPendingDictation()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dictationTimer?.invalidate()
        dictationTimer = nil
        store.save()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let wanted = desiredHeight()
        if let heightConstraint, heightConstraint.constant != wanted {
            heightConstraint.constant = wanted
        }
        keyboardView.configure(page: page, showGlobe: needsInputModeSwitchKey)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAutoShift()
        updateSuggestions()
    }

    /// Wysokość zależna od urządzenia i orientacji (iPhone / iPad).
    private func desiredHeight() -> CGFloat {
        let rowHeight: CGFloat
        if traitCollection.userInterfaceIdiom == .pad {
            rowHeight = traitCollection.verticalSizeClass == .compact ? 52 : 66
        } else {
            rowHeight = traitCollection.verticalSizeClass == .compact ? 38 : 54
        }
        return Self.barHeight + rowHeight * 4
    }

    private func startPage() -> KeyboardPage {
        switch textDocumentProxy.keyboardType ?? .default {
        case .numberPad, .decimalPad, .phonePad, .numbersAndPunctuation, .asciiCapableNumberPad:
            return .symbols
        default:
            return .letters
        }
    }

    /// W polach e-mail / adresów nie poprawiamy i nie uczymy się słów.
    private var isPlainTextField: Bool {
        switch textDocumentProxy.keyboardType ?? .default {
        case .emailAddress, .URL, .webSearch, .numberPad, .decimalPad, .phonePad,
             .numbersAndPunctuation, .asciiCapableNumberPad:
            return false
        default:
            return true
        }
    }

    // MARK: - Kontekst tekstu

    private var contextBefore: String {
        textDocumentProxy.documentContextBeforeInput ?? ""
    }

    /// Litery bezpośrednio przed kursorem.
    private func currentWord() -> String {
        var chars: [Character] = []
        for ch in contextBefore.reversed() {
            guard ch.isLetter else { break }
            chars.append(ch)
        }
        return String(chars.reversed())
    }

    /// Słowo poprzedzające `text` (oddzielone samymi spacjami) — do podpowiedzi następnego słowa.
    private func lastWord(in text: Substring) -> String? {
        var rest = text
        var sawSpace = false
        while rest.last == " " {
            rest = rest.dropLast()
            sawSpace = true
        }
        guard sawSpace else { return nil }
        var chars: [Character] = []
        for ch in rest.reversed() {
            guard ch.isLetter else { break }
            chars.append(ch)
        }
        return chars.isEmpty ? nil : String(chars.reversed())
    }

    private func isSentenceStart(_ text: Substring) -> Bool {
        var rest = text
        while rest.last == " " { rest = rest.dropLast() }
        guard let last = rest.last else { return true }
        return last.isNewline || Self.sentenceEnders.contains(last)
    }

    private func updateAutoShift() {
        guard shift != .locked else { return }
        let context = contextBefore
        var shouldCapitalize = false
        if isPlainTextField {
            switch textDocumentProxy.autocapitalizationType ?? .sentences {
            case .none:
                shouldCapitalize = false
            case .allCharacters:
                shouldCapitalize = true
            case .words:
                shouldCapitalize = context.isEmpty || (context.last?.isWhitespace ?? true)
            case .sentences:
                let endsWithGap = context.isEmpty || (context.last?.isWhitespace ?? true)
                shouldCapitalize = endsWithGap && isSentenceStart(Substring(context))
            @unknown default:
                shouldCapitalize = false
            }
        }
        setShift(shouldCapitalize ? .on : .off)
    }

    private func setShift(_ state: ShiftState) {
        shift = state
        keyboardView.setShift(state)
    }

    // MARK: - Podpowiedzi

    private func updateSuggestions() {
        guard predictor.isLoaded else { return }
        let typed = currentWord()
        let before = Substring(contextBefore).dropLast(typed.count)
        let list = predictor.suggestions(
            typed: typed,
            previous: lastWord(in: before),
            user: store.data,
            capitalizeNext: shift != .off)
        if list.isEmpty, !hasFullAccess, !didShowAccessHint {
            didShowAccessHint = true
            bar.showMessage("Włącz „Pełny dostęp” w Ustawieniach, aby zapamiętywać słowa i dyktować")
        } else {
            bar.show(list)
        }
    }

    /// Zapis słowa do nauki: na początku zdania wielka litera to nie cecha słowa.
    private func normalized(_ word: String, atSentenceStart: Bool) -> String {
        guard atSentenceStart, let first = word.first, first.isUppercase else { return word }
        let rest = word.dropFirst()
        return rest == rest.lowercased() ? word.lowercased() : word
    }

    private func learn(_ word: String, before: Substring, explicit: Bool) {
        guard isPlainTextField, word.count >= 2, word.allSatisfy({ $0.isLetter }) else { return }
        let normalizedWord = normalized(word, atSentenceStart: isSentenceStart(before))
        store.learn(normalizedWord, explicit: explicit)
        if let previous = lastWord(in: before) {
            store.recordBigram(previous: previous, next: normalizedWord)
        }
    }

    private func pick(_ suggestion: Suggestion) {
        let typed = currentWord()
        let before = Substring(contextBefore).dropLast(typed.count)
        for _ in 0..<typed.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(suggestion.text + " ")
        learn(suggestion.text, before: before,
              explicit: suggestion.kind == .verbatim && !suggestion.isKnown)
        pendingAutoSpace = true
        lastAutoFix = nil
        afterEdit()
    }

    /// Zatwierdza wpisywane słowo: autokorekta polskich znaków + nauka słowa.
    private func commitCurrentWord(terminator: String) {
        lastAutoFix = nil
        let typed = currentWord()
        guard !typed.isEmpty else { return }
        let before = Substring(contextBefore).dropLast(typed.count)
        var finalWord = typed
        if isPlainTextField, SharedSettings.autocorrectEnabled, predictor.isLoaded,
           let fix = predictor.autocorrection(for: typed, user: store.data), fix != typed {
            for _ in 0..<typed.count { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(fix)
            lastAutoFix = AutoFix(original: typed, replacement: fix, terminator: terminator)
            finalWord = fix
        }
        learn(finalWord, before: before, explicit: false)
    }

    // MARK: - Obsługa klawiszy

    private func handle(_ key: Key) {
        switch key.action {
        case .character(let c):
            insertCharacter(c)
        case .space:
            handleSpace()
        case .enter:
            commitCurrentWord(terminator: "\n")
            textDocumentProxy.insertText("\n")
            pendingAutoSpace = false
            afterEdit()
        case .shift:
            handleShift()
        case .page(let target):
            page = target
            keyboardView.configure(page: page, showGlobe: needsInputModeSwitchKey)
            keyboardView.setShift(shift)
        case .dictation:
            startDictation()
        case .backspace, .globe:
            break
        }
    }

    private func insertCharacter(_ c: String) {
        let isLetter = c.allSatisfy { $0.isLetter }
        if isLetter {
            lastAutoFix = nil
            pendingAutoSpace = false
            let alreadyUpper = c != c.lowercased()
            textDocumentProxy.insertText(shift != .off && !alreadyUpper ? c.uppercased() : c)
        } else if pendingAutoSpace, Self.spaceEatingPunctuation.contains(c), contextBefore.hasSuffix(" ") {
            // „słowo ” + „.” → „słowo. ”
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(c + " ")
            pendingAutoSpace = false
            lastAutoFix = nil
        } else {
            commitCurrentWord(terminator: c)
            textDocumentProxy.insertText(c)
            pendingAutoSpace = false
        }
        afterEdit()
    }

    private func handleSpace() {
        let now = Date()
        let context = contextBefore
        let isDoubleTap = now.timeIntervalSince(lastSpaceTap) < 0.7
        lastSpaceTap = now

        // Podwójna spacja → kropka.
        if isDoubleTap, isPlainTextField, context.hasSuffix(" "),
           let beforeSpace = context.dropLast().last, beforeSpace.isLetter || beforeSpace.isNumber {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastAutoFix = nil
            lastSpaceTap = .distantPast
        } else {
            commitCurrentWord(terminator: " ")
            textDocumentProxy.insertText(" ")
        }
        pendingAutoSpace = false
        if page != .letters {
            page = .letters
            keyboardView.configure(page: page, showGlobe: needsInputModeSwitchKey)
        }
        afterEdit()
    }

    private func handleBackspace() {
        // Backspace tuż po autokorekcie przywraca to, co wpisał użytkownik.
        if let fix = lastAutoFix, contextBefore.hasSuffix(fix.replacement + fix.terminator) {
            for _ in 0..<(fix.replacement.count + fix.terminator.count) {
                textDocumentProxy.deleteBackward()
            }
            textDocumentProxy.insertText(fix.original + fix.terminator)
            lastAutoFix = nil
            store.learn(fix.original, explicit: true)
        } else {
            lastAutoFix = nil
            textDocumentProxy.deleteBackward()
        }
        pendingAutoSpace = false
        afterEdit()
    }

    private func handleShift() {
        let now = Date()
        if shift == .locked {
            setShift(.off)
        } else if now.timeIntervalSince(lastShiftTap) < 0.35 {
            setShift(.locked)
        } else {
            setShift(shift == .off ? .on : .off)
        }
        lastShiftTap = now
        updateSuggestions()
    }

    private func afterEdit() {
        updateAutoShift()
        updateSuggestions()
    }

    // MARK: - Dyktowanie

    /// Rozszerzenie klawiatury nie ma dostępu do mikrofonu (ograniczenie iOS),
    /// więc dyktowanie odbywa się w aplikacji, a gotowy tekst wraca przez App Group.
    private func startDictation() {
        guard hasFullAccess else {
            bar.showMessage("Dyktowanie wymaga „Pełnego dostępu” (Ustawienia › Klawiatury)")
            return
        }
        guard let url = URL(string: "\(AppGroup.urlScheme)://dictate") else { return }
        store.save()
        if !openViaResponderChain(url) {
            extensionContext?.open(url, completionHandler: nil)
        }
    }

    /// Rozszerzenia nie mogą wprost wywołać UIApplication.open, dlatego szukamy
    /// obiektu aplikacji w łańcuchu responderów i wołamy metodę dynamicznie.
    private func openViaResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        guard let applicationClass = NSClassFromString("UIApplication") else { return false }
        var responder: UIResponder? = self
        while let current = responder {
            if current.isKind(of: applicationClass), current.responds(to: selector),
               let implementation = current.method(for: selector) {
                typealias OpenFunction = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(implementation, to: OpenFunction.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func insertPendingDictation() {
        guard hasFullAccess, let text = SharedSettings.pendingDictation, !text.isEmpty else { return }
        SharedSettings.pendingDictation = nil
        let context = contextBefore
        let needsLeadingSpace = !context.isEmpty && !(context.last?.isWhitespace ?? true)
        textDocumentProxy.insertText((needsLeadingSpace ? " " : "") + text + " ")
        afterEdit()
    }
}
