import UIKit

/// Pasek podpowiedzi nad klawiszami. Dotknięcie wstawia słowo,
/// przytrzymanie pyta o usunięcie słowa z podpowiedzi (jak w SwiftKey).
final class SuggestionBar: UIView {
    var onSelect: ((Suggestion) -> Void)?
    var onBlock: ((Suggestion) -> Void)?

    private var suggestions: [Suggestion] = []
    private var pendingBlock: Suggestion?

    private let suggestionStack = UIStackView()
    private var buttons: [UIButton] = []
    private let confirmStack = UIStackView()
    private let confirmLabel = UILabel()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        suggestionStack.axis = .horizontal
        suggestionStack.distribution = .fillEqually
        for index in 0..<3 {
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.6
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.setTitleColor(.label, for: .normal)
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
            press.minimumPressDuration = 0.5
            button.addGestureRecognizer(press)
            suggestionStack.addArrangedSubview(button)
            buttons.append(button)
        }

        confirmLabel.font = .systemFont(ofSize: 15)
        confirmLabel.textColor = .label
        confirmLabel.adjustsFontSizeToFitWidth = true
        confirmLabel.minimumScaleFactor = 0.6
        confirmLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        confirmLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let removeButton = UIButton(type: .system)
        removeButton.setTitle("Usuń", for: .normal)
        removeButton.setTitleColor(.systemRed, for: .normal)
        removeButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        removeButton.addTarget(self, action: #selector(confirmBlock), for: .touchUpInside)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Anuluj", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16)
        cancelButton.addTarget(self, action: #selector(cancelBlock), for: .touchUpInside)

        confirmStack.axis = .horizontal
        confirmStack.spacing = 16
        confirmStack.alignment = .center
        confirmStack.isLayoutMarginsRelativeArrangement = true
        confirmStack.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        confirmStack.addArrangedSubview(confirmLabel)
        confirmStack.addArrangedSubview(removeButton)
        confirmStack.addArrangedSubview(cancelButton)
        confirmStack.isHidden = true

        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        messageLabel.adjustsFontSizeToFitWidth = true
        messageLabel.minimumScaleFactor = 0.7
        messageLabel.isHidden = true

        for view in [suggestionStack, confirmStack, messageLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ list: [Suggestion]) {
        suggestions = list
        pendingBlock = nil
        confirmStack.isHidden = true
        messageLabel.isHidden = true
        suggestionStack.isHidden = false

        // Kolejność jak w SwiftKey: najlepsza podpowiedź na środku, dosłowne słowo po lewej.
        let slots = arrange(list)
        for (index, button) in buttons.enumerated() {
            if let s = slots[index] {
                let title = (s.kind == .verbatim && !s.isKnown) ? "„\(s.text)”" : s.text
                button.setTitle(title, for: .normal)
                button.titleLabel?.font = index == 1 ? .boldSystemFont(ofSize: 17) : .systemFont(ofSize: 17)
                button.isEnabled = true
            } else {
                button.setTitle(nil, for: .normal)
                button.isEnabled = false
            }
        }
    }

    /// Krótki komunikat zamiast podpowiedzi (np. o braku Pełnego dostępu).
    func showMessage(_ text: String) {
        suggestions = []
        pendingBlock = nil
        suggestionStack.isHidden = true
        confirmStack.isHidden = true
        messageLabel.text = text
        messageLabel.isHidden = false
    }

    private var slotMap: [Int: Suggestion] = [:]

    private func arrange(_ list: [Suggestion]) -> [Suggestion?] {
        var slots: [Suggestion?] = [nil, nil, nil]
        if let first = list.first, first.kind == .verbatim {
            slots[0] = first
            if list.count > 1 { slots[1] = list[1] }
            if list.count > 2 { slots[2] = list[2] }
        } else {
            // Podpowiedzi następnego słowa: najlepsza na środku.
            if list.count > 0 { slots[1] = list[0] }
            if list.count > 1 { slots[0] = list[1] }
            if list.count > 2 { slots[2] = list[2] }
        }
        slotMap = [:]
        for (index, s) in slots.enumerated() {
            if let s { slotMap[index] = s }
        }
        return slots
    }

    @objc private func tapped(_ sender: UIButton) {
        guard let s = slotMap[sender.tag] else { return }
        onSelect?(s)
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? UIButton,
              let s = slotMap[button.tag] else { return }
        pendingBlock = s
        confirmLabel.text = "Nie podpowiadać „\(s.text)”?"
        suggestionStack.isHidden = true
        messageLabel.isHidden = true
        confirmStack.isHidden = false
    }

    @objc private func confirmBlock() {
        guard let s = pendingBlock else { return }
        pendingBlock = nil
        onBlock?(s)
    }

    @objc private func cancelBlock() {
        show(suggestions)
    }
}
