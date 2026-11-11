import AppKit
import QuartzCore

/// Строитель боковой стеклянной панели настроек.
enum SettingsSidePanelBuilder {
    struct Output {
        let panel: NSVisualEffectView
        let trailingConstraint: NSLayoutConstraint
        let engineStatusLabel: NSTextField
    }

    static func build(
        in root: NSView,
        above relativeView: NSView,
        settings: SettingsState,
        target: AnyObject,
        toggleAction: Selector,
        accentAction: Selector,
        openVPNAction: Selector,
        resetAction: Selector,
        checkUpdatesAction: Selector,
        closeAction: Selector
    ) -> Output {
        let sidePanel = NSVisualEffectView()
        sidePanel.material = .popover
        sidePanel.appearance = NSAppearance(named: .darkAqua)
        sidePanel.blendingMode = .withinWindow
        sidePanel.state = .active
        sidePanel.wantsLayer = true
        sidePanel.layer?.cornerRadius = 20
        sidePanel.layer?.masksToBounds = true
        sidePanel.layer?.borderWidth = 1
        sidePanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        sidePanel.layer?.shadowOpacity = 0.4
        sidePanel.layer?.shadowRadius = 32
        sidePanel.layer?.shadowOffset = NSSize(width: -6, height: 0)
        sidePanel.layer?.shadowColor = NSColor.black.cgColor
        sidePanel.alphaValue = 0
        sidePanel.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 9
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: AppConfig.name)
        name.font = .systemFont(ofSize: 18, weight: .bold)

        let verBadge = NSTextField(labelWithString: "v\(AppConfig.version)")
        verBadge.font = .systemFont(ofSize: 10, weight: .bold)
        verBadge.textColor = .secondaryLabelColor
        verBadge.wantsLayer = true
        verBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        verBadge.layer?.cornerRadius = 5
        verBadge.alignment = .center

        let nameRow = NSStackView(views: [name, verBadge])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 8

        let engineStatusLabel = NSTextField(labelWithString: "● Применяется сразу, без перезагрузки")
        engineStatusLabel.textColor = .systemGreen
        engineStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)

        let headerText = NSStackView(views: [nameRow, engineStatusLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 2

        let header = NSStackView(views: [icon, headerText])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        // Секция «Оформление»
        let designSpecs: [(key: String, symbol: String, color: NSColor)] = [
            ("modernDesign", "sparkles", .systemBlue),
            ("theme", "checkmark.seal.fill", .systemIndigo),
            ("roundedCards", "square.inset.filled", .systemPink),
            ("artworkHover", "cursorarrow.rays", .systemTeal)
        ]
        let designRows: [NSView] = designSpecs.compactMap { spec in
            guard let sw = settings.makeSwitch(for: spec.key, action: toggleAction, target: target) else { return nil }
            let badge = iconBadge(symbol: spec.symbol, color: spec.color)
            return modernSettingsRow(
                icon: badge,
                title: settings.title(for: spec.key),
                subtitle: settings.subtitle(for: spec.key),
                control: sw
            )
        }
        let designCard = makeCard(rows: designRows)

        // Секция «Акцент»
        let accentCtrl = settings.makeAccentControl(action: accentAction, target: target)
        let accentBadge = iconBadge(symbol: "paintpalette.fill", color: .systemPurple)
        let accentRow = modernSettingsRow(
            icon: accentBadge,
            title: "Цветовой акцент",
            subtitle: "Кнопки, шкала времени и громкость",
            control: accentCtrl
        )
        let accentCard = makeCard(rows: [accentRow])

        // Секция «Прослушивание»
        let listeningSpecs: [(key: String, symbol: String, color: NSColor)] = [
            ("focus", "eye.slash.fill", .systemPurple),
            ("adBlock", "shield.lefthalf.filled", .systemGreen)
        ]
        let listeningRows: [NSView] = listeningSpecs.compactMap { spec in
            guard let sw = settings.makeSwitch(for: spec.key, action: toggleAction, target: target) else { return nil }
            let badge = iconBadge(symbol: spec.symbol, color: spec.color)
            return modernSettingsRow(
                icon: badge,
                title: settings.title(for: spec.key),
                subtitle: settings.subtitle(for: spec.key),
                control: sw
            )
        }
        let listeningCard = makeCard(rows: listeningRows)

        // Секция «Система»
        let vpnBtn = NSButton(title: "Открыть…", target: target, action: openVPNAction)
        vpnBtn.bezelStyle = .rounded
        vpnBtn.controlSize = .small
        let vpnRow = modernSettingsRow(
            icon: iconBadge(symbol: "lock.shield.fill", color: .systemCyan),
            title: "Встроенный VPN",
            subtitle: "Действует только на DieCloude",
            control: vpnBtn
        )

        let resetBtn = NSButton(title: "Сбросить", target: target, action: resetAction)
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .small
        let resetRow = modernSettingsRow(
            icon: iconBadge(symbol: "arrow.counterclockwise", color: .systemYellow),
            title: "Сбросить оформление",
            subtitle: "Вернуть параметры по умолчанию",
            control: resetBtn
        )

        let updateBtn = NSButton(title: "Проверить…", target: target, action: checkUpdatesAction)
        updateBtn.bezelStyle = .rounded
        updateBtn.controlSize = .small
        let updateRow = modernSettingsRow(
            icon: iconBadge(symbol: "arrow.triangle.2.circlepath", color: .systemBlue),
            title: "Обновления",
            subtitle: "Проверить новую версию на GitHub",
            control: updateBtn
        )
        let actionsCard = makeCard(rows: [vpnRow, resetRow, updateRow])

        let footer = NSTextField(labelWithString: "Версия \(AppConfig.version) (\(AppConfig.build)) · \(AppConfig.author)")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center

        let close = symbolButton("xmark", action: closeAction, target: target, tooltip: "Закрыть (Esc)")

        let stack = NSStackView(views: [
            header,
            sectionTitle("Оформление"),
            designCard,
            sectionTitle("Акцент"),
            accentCard,
            sectionTitle("Прослушивание"),
            listeningCard,
            sectionTitle("Система"),
            actionsCard,
            footer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: header)
        stack.setCustomSpacing(12, after: designCard)
        stack.setCustomSpacing(12, after: accentCard)
        stack.setCustomSpacing(12, after: listeningCard)
        stack.setCustomSpacing(16, after: actionsCard)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for card in [designCard, accentCard, listeningCard, actionsCard, footer] as [NSView] {
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = stack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidePanel.addSubview(scroll)
        sidePanel.addSubview(close)
        root.addSubview(sidePanel, positioned: .above, relativeTo: relativeView)

        let trailing = sidePanel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: 500)
        NSLayoutConstraint.activate([
            sidePanel.topAnchor.constraint(equalTo: root.topAnchor, constant: 52),
            sidePanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            sidePanel.widthAnchor.constraint(equalToConstant: 420),
            trailing,
            scroll.topAnchor.constraint(equalTo: sidePanel.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidePanel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: sidePanel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            close.topAnchor.constraint(equalTo: sidePanel.topAnchor, constant: 14),
            close.trailingAnchor.constraint(equalTo: sidePanel.trailingAnchor, constant: -14)
        ])

        return Output(panel: sidePanel, trailingConstraint: trailing, engineStatusLabel: engineStatusLabel)
    }

    static func symbolButton(_ symbol: String, action: Selector, target: AnyObject, tooltip: String) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = (NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage()).withSymbolConfiguration(config) ?? NSImage()
        let button = ToolbarButton(image: image, target: target, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private static func iconBadge(symbol: String, color: NSColor) -> NSView {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.masksToBounds = true
        badge.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 28).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let img = (NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()).withSymbolConfiguration(config)
        let imageView = NSImageView(image: img ?? NSImage())
        imageView.contentTintColor = color
        imageView.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        return badge
    }

    private static func makeCard(rows: [NSView]) -> NSView {
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.appearance = NSAppearance(named: .darkAqua)
        card.blendingMode = .withinWindow
        card.wantsLayer = true
        card.layer?.cornerRadius = 13
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        for (i, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if i < rows.count - 1 {
                let div = NSView()
                div.wantsLayer = true
                div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
                div.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(div)
                div.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 50).isActive = true
                div.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12).isActive = true
                div.heightAnchor.constraint(equalToConstant: 1).isActive = true
            }
        }
        return card
    }

    private static func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .tertiaryLabelColor
        if let attributed = label.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            attributed.addAttribute(.kern, value: 1.1, range: NSRange(location: 0, length: attributed.length))
            label.attributedStringValue = attributed
        }
        return label
    }

    private static func modernSettingsRow(icon: NSView, title: String, subtitle: String, control: NSControl) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = control.isEnabled ? .labelColor : .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = control.isEnabled ? .secondaryLabelColor : .systemOrange
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [icon, text, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }
}
