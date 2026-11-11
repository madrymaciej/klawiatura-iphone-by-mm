import UIKit

enum ShiftState {
    case off, on, locked
}

enum KeyColors {
    static let letter = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.42, alpha: 1) : .white }
    static let special = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.75, alpha: 1) }
    static let pressed = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.60, alpha: 1) : UIColor(white: 0.80, alpha: 1) }
    static let active = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.85, alpha: 1) : .white }
    static let text = UIColor.label
    static let activeText = UIColor { $0.userInterfaceStyle == .dark ? .black : .label }
}

// MARK: - Pojedynczy klawisz

final class KeyButton: UIControl {
    let key: Key
    private let background = UIView()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    /// Dodatkowy martwy obszar po bokach (klawisze skrajne w krótszym wierszu
    /// łapią dotyk aż do krawędzi ekranu, ale wyglądają normalnie).
    var extraLeft: CGFloat = 0
    var extraRight: CGFloat = 0

    /// Podświetlenie stanu (np. aktywny Shift).
    var isActive = false { didSet { updateColors() } }

    init(key: Key) {
        self.key = key
        super.init(frame: .zero)

        background.isUserInteractionEnabled = false
        background.layer.cornerRadius = 5
        background.layer.shadowColor = UIColor.black.cgColor
        background.layer.shadowOpacity = 0.3
        background.layer.shadowRadius = 0
        background.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(background)

        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.textColor = KeyColors.text
        background.addSubview(titleLabel)

        iconView.contentMode = .center
        iconView.tintColor = KeyColors.text
        background.addSubview(iconView)

        if let name = key.symbolName {
            setSymbol(name)
        } else {
            titleLabel.text = key.label
        }
        let isCharacter: Bool
        if case .character = key.action { isCharacter = true } else { isCharacter = false }
        titleLabel.font = .systemFont(ofSize: isCharacter ? 23 : 16)
        accessibilityLabel = key.label ?? key.symbolName
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ name: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        iconView.image = UIImage(systemName: name, withConfiguration: config)
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
    }

    override var isHighlighted: Bool { didSet { updateColors() } }

    private func updateColors() {
        if isHighlighted {
            background.backgroundColor = KeyColors.pressed
        } else if isActive {
            background.backgroundColor = KeyColors.active
        } else {
            background.backgroundColor = key.isSpecial ? KeyColors.special : KeyColors.letter
        }
        iconView.tintColor = isActive ? KeyColors.activeText : KeyColors.text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let area = CGRect(x: extraLeft, y: 0,
                          width: bounds.width - extraLeft - extraRight, height: bounds.height)
        background.frame = area.insetBy(dx: 3, dy: 4)
        titleLabel.frame = background.bounds.insetBy(dx: 2, dy: 0)
        iconView.frame = background.bounds
    }
}

// MARK: - Dymek ze znakami alternatywnymi

final class AlternatesPopup: UIView {
    let options: [String]
    private var labels: [UILabel] = []
    private(set) var selectedIndex = 0
    static let cellSize = CGSize(width: 42, height: 48)

    init(options: [String]) {
        self.options = options
        super.init(frame: CGRect(x: 0, y: 0,
                                 width: Self.cellSize.width * CGFloat(options.count) + 8,
                                 height: Self.cellSize.height + 8))
        backgroundColor = KeyColors.letter
        layer.cornerRadius = 9
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        isUserInteractionEnabled = false

        for (i, option) in options.enumerated() {
            let label = UILabel(frame: CGRect(x: 4 + CGFloat(i) * Self.cellSize.width, y: 4,
                                              width: Self.cellSize.width, height: Self.cellSize.height))
            label.text = option
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 24)
            label.layer.cornerRadius = 6
            label.layer.masksToBounds = true
            addSubview(label)
            labels.append(label)
        }
        select(0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ index: Int) {
        selectedIndex = min(max(index, 0), options.count - 1)
        for (i, label) in labels.enumerated() {
            let selected = i == selectedIndex
            label.backgroundColor = selected ? .systemBlue : .clear
            label.textColor = selected ? .white : KeyColors.text
        }
    }

    /// Wybór na podstawie położenia palca (x w układzie dymka).
    func select(atX x: CGFloat) {
        select(Int(floor((x - 4) / Self.cellSize.width)))
    }
}

// MARK: - Widok klawiatury

final class KeyboardView: UIView {
    var onKey: ((Key) -> Void)?
    var onAlternate: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    /// Klawisz „globus” musi zostać podpięty przez kontroler do systemowej akcji zmiany klawiatury.
    var configureGlobe: ((UIControl) -> Void)?

    private(set) var page: KeyboardPage = .letters
    private var showGlobe = false
    private var shift: ShiftState = .off
    private var buttonRows: [[KeyButton]] = []
    private var popup: AlternatesPopup?
    private var backspaceTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { backspaceTimer?.invalidate() }

    func configure(page: KeyboardPage, showGlobe: Bool) {
        guard page != self.page || showGlobe != self.showGlobe || buttonRows.isEmpty else { return }
        self.page = page
        self.showGlobe = showGlobe
        rebuild()
    }

    func setShift(_ state: ShiftState) {
        shift = state
        applyShift()
    }

    private func rebuild() {
        stopBackspaceRepeat()
        popup?.removeFromSuperview()
        popup = nil
        buttonRows.flatMap { $0 }.forEach { $0.removeFromSuperview() }

        buttonRows = KeyboardLayout.rows(page: page, showGlobe: showGlobe).map { row in
            row.map { key in
                let button = KeyButton(key: key)
                addSubview(button)
                wire(button)
                return button
            }
        }
        applyShift()
        setNeedsLayout()
    }

    private func wire(_ button: KeyButton) {
        switch button.key.action {
        case .backspace:
            button.addTarget(self, action: #selector(backspaceDown), for: .touchDown)
            button.addTarget(self, action: #selector(backspaceUp),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
        case .globe:
            configureGlobe?(button)
        default:
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        }
        if !button.key.alternates.isEmpty {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
            press.minimumPressDuration = 0.35
            button.addGestureRecognizer(press)
        }
    }

    private func applyShift() {
        let upper = shift != .off
        for button in buttonRows.flatMap({ $0 }) {
            switch button.key.action {
            case .character(let c) where page == .letters && c.count == 1 && (c.first?.isLetter ?? false):
                button.setTitle(upper ? c.uppercased() : c)
            case .shift:
                button.isActive = upper
                button.setSymbol(shift == .locked ? "capslock.fill" : (upper ? "shift.fill" : "shift"))
            default:
                break
            }
        }
    }

    // MARK: Układ

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !buttonRows.isEmpty, bounds.width > 0 else { return }
        let rowHeight = bounds.height / CGFloat(buttonRows.count)
        let unit = bounds.width / 10

        for (rowIndex, row) in buttonRows.enumerated() {
            let fixedWidth = row.filter { !$0.key.flexible }.reduce(CGFloat(0)) { $0 + $1.key.weight } * unit
            let flexibleCount = row.filter { $0.key.flexible }.count
            let flexibleWidth = flexibleCount > 0
                ? max(0, (bounds.width - fixedWidth) / CGFloat(flexibleCount)) : 0
            let sideInset = flexibleCount > 0 ? 0 : max(0, (bounds.width - fixedWidth) / 2)
            var x = sideInset

            for (index, button) in row.enumerated() {
                let width = button.key.flexible ? flexibleWidth : button.key.weight * unit
                var frame = CGRect(x: x, y: CGFloat(rowIndex) * rowHeight, width: width, height: rowHeight)
                button.extraLeft = 0
                button.extraRight = 0
                if index == 0, sideInset > 0 {
                    frame.origin.x = 0
                    frame.size.width += sideInset
                    button.extraLeft = sideInset
                }
                if index == row.count - 1, sideInset > 0 {
                    frame.size.width += sideInset
                    button.extraRight = sideInset
                }
                button.frame = frame
                button.setNeedsLayout()
                x += width
            }
        }
    }

    // MARK: Akcje

    @objc private func keyTapped(_ sender: KeyButton) {
        onKey?(sender.key)
    }

    @objc private func backspaceDown() {
        onBackspace?()
        stopBackspaceRepeat()
        // Po 0,4 s przytrzymania kasowanie powtarza się co 80 ms.
        let timer = Timer(fire: Date().addingTimeInterval(0.4), interval: 0.08, repeats: true) { [weak self] _ in
            self?.onBackspace?()
        }
        RunLoop.main.add(timer, forMode: .common)
        backspaceTimer = timer
    }

    @objc private func backspaceUp() {
        stopBackspaceRepeat()
    }

    private func stopBackspaceRepeat() {
        backspaceTimer?.invalidate()
        backspaceTimer = nil
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? KeyButton else { return }
        switch gesture.state {
        case .began:
            var options = button.key.alternates
            if shift != .off, page == .letters {
                options = options.map { $0.uppercased() }
            }
            let popup = AlternatesPopup(options: options)
            let keyFrame = button.frame
            var origin = CGPoint(x: keyFrame.midX - AlternatesPopup.cellSize.width / 2 - 4,
                                 y: keyFrame.minY - popup.bounds.height + 2)
            origin.x = min(max(2, origin.x), bounds.width - popup.bounds.width - 2)
            popup.frame.origin = origin
            addSubview(popup)
            self.popup?.removeFromSuperview()
            self.popup = popup
        case .changed:
            guard let popup else { return }
            popup.select(atX: gesture.location(in: popup).x)
        case .ended:
            if let popup {
                onAlternate?(popup.options[popup.selectedIndex])
            }
            popup?.removeFromSuperview()
            popup = nil
        default:
            popup?.removeFromSuperview()
            popup = nil
        }
    }
}
