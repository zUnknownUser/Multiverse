import SwiftUI

/// "Sugerir correção" — recurso 3c.
struct SuggestCorrectionView: View {
    let itemID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var changeType: CorrectionChangeType = .canonStatus
    @State private var fromValue = ""
    @State private var toValue = ""
    @State private var source = ""
    @State private var reasoning = ""

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if let item = store.item(itemID) {
                let uni = store.universe(of: item)
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.text("SUGERIR CORREÇÃO")).kicker(11).foregroundStyle(MV.C.muted)

                    HStack(spacing: 12) {
                        PosterView(item: item, universe: uni, width: 60, height: 90, titleSize: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title.uppercased()).font(MVFont.black(18)).foregroundStyle(MV.C.ink)
                            Text("\(uni.name) · \(L10n.text(item.type)) · \(item.year.description)")
                                .font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("O QUE MUDA?")).kicker(11).foregroundStyle(MV.C.muted)
                        let columns = [GridItem(.flexible()), GridItem(.flexible())]
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(CorrectionChangeType.allCases, id: \.self) { type in
                                PillButton(title: L10n.text(type.rawValue), active: changeType == type, size: 13) { changeType = type }
                            }
                        }
                        if changeType == .canonStatus {
                            HStack(spacing: 10) {
                                statusChip(fromValue.isEmpty ? item.canon : fromValue, bg: MV.C.card)
                                Text("→").font(MVFont.black(16)).foregroundStyle(MV.C.ink)
                                statusChip(toValue.isEmpty ? "?" : toValue, bg: MV.C.marvel, fg: MV.C.paper)
                            }
                        }
                    }
                    .padding(14)
                    .comicCard(shadow: 0)

                    if changeType == .canonStatus {
                        fieldRow(label: L10n.text("De"), text: $fromValue, placeholder: item.canon)
                        fieldRow(label: L10n.text("Para"), text: $toValue, placeholder: L10n.text("Ex.: Retconado"))
                    } else {
                        fieldRow(label: L10n.text("De"), text: $fromValue, placeholder: L10n.text("Valor atual"))
                        fieldRow(label: L10n.text("Para"), text: $toValue, placeholder: L10n.text("Novo valor"))
                    }

                    fieldRow(label: L10n.text("Fonte"), text: $source, placeholder: "dc.fandom.com/wiki/…", keyboard: .URL)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("POR QUÊ?")).kicker(11).foregroundStyle(MV.C.ink)
                        TextField(L10n.text("Explique com base em quê."), text: $reasoning, axis: .vertical)
                            .font(MVFont.body(14, weight: 500))
                            .lineLimit(3...5)
                            .padding(12)
                            .background(MV.C.card)
                            .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                            .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
                    }

                    existingSuggestions(uni: uni)

                    PrimaryAuthButton(title: L10n.text("ENVIAR SUGESTÃO"), enabled: !toValue.isEmpty && !source.isEmpty && !reasoning.isEmpty) {
                        store.submitCorrection(itemID: itemID, changeType: changeType, from: fromValue.isEmpty ? item.canon : fromValue, to: toValue, source: source, reasoning: reasoning)
                        dismiss()
                    }
                    Text(L10n.text("+15 de reputação se aprovada")).font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.muted).frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, MV.pad)
                .padding(.bottom, 24)
                .task { await store.loadCorrections(for: itemID) }
            }
        }
    }

    private func statusChip(_ text: String, bg: Color, fg: Color = MV.C.ink) -> some View {
        Text(L10n.text(text).uppercased())
            .font(MVFont.black(11)).tracking(0.3)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
    }

    private func fieldRow(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).kicker(11).foregroundStyle(MV.C.ink)
            TextField(placeholder, text: text)
                .font(MVFont.body(15, weight: 500))
                .keyboardType(keyboard)
                .autocorrectionDisabled(keyboard == .URL)
                .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(MV.C.card)
                .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        }
    }

    @ViewBuilder
    private func existingSuggestions(uni: Universe) -> some View {
        if let existing = store.correctionsByItem[itemID], !existing.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(existing) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.text("EM REVISÃO")).kicker(10).foregroundStyle(MV.C.paper.opacity(0.85))
                            Spacer()
                            Text(L10n.format("%1$@ de %2$@ aprovaram", String(describing: suggestion.approverIDs.count), String(describing: suggestion.approvalsNeeded))).font(MVFont.bold(12)).foregroundStyle(MV.C.paper)
                        }
                        HStack(spacing: 6) {
                            ForEach(suggestion.approverIDs, id: \.self) { id in
                                if let u = store.user(id) { AvatarView(user: u, size: 26) }
                            }
                            Text(L10n.format("Revisores com selo Lorista de %1$@", String(describing: store.badgeNames[uni.id] ?? uni.name)))
                                .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.paper.opacity(0.85))
                        }
                    }
                    .padding(14)
                    .background(MV.C.dc)
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
                    .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                }
            }
        }
    }
}
