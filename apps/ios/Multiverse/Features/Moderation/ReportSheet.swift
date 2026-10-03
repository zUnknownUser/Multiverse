import SwiftUI

/// Sheet de denúncia (recurso 3b) — aberta pelo "•••" nos cards de review/comentário.
struct ReportSheet: View {
    let targetType: String   // "review" | "comentário"
    let targetID: String
    let authorHandle: String
    let targetTitle: String
    var reviewID: String? = nil

    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .spoiler
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Capsule().fill(MV.C.ink).frame(width: 44, height: 5).frame(maxWidth: .infinity)

                Text(L10n.format("DENUNCIAR %1$@", L10n.text(targetType == "comentário" ? "COMENTÁRIO" : "REVIEW"))).font(MVFont.display(24, width: 118)).foregroundStyle(MV.C.ink)
                Text(L10n.format("de %1$@ sobre %2$@", String(describing: authorHandle), String(describing: targetTitle))).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.muted)

                VStack(spacing: 10) {
                    ForEach(ReportReason.allCases, id: \.self) { option in
                        reasonRow(option)
                    }
                }

                HStack {
                    Text(L10n.text("Também bloquear essa pessoa")).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                    Spacer()
                    Toggle("", isOn: $alsoBlock).labelsHidden().tint(MV.C.marvel)
                }

                if let errorMessage { AuthErrorBanner(message: errorMessage) }
                Text(L10n.text(isSending ? "SALVANDO…" : "ENVIAR DENÚNCIA"))
                    .font(MVFont.bold(15))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(MV.C.paper)
                    .background(MV.C.ink)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.marvel).offset(x: MV.Shadow.s, y: MV.Shadow.s))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: send)

                Text(L10n.text("Sua denúncia será registrada para análise. A pessoa não recebe sua identidade."))
                    .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(MV.pad)
            .padding(.bottom, 12)
            .allowsHitTesting(!isSending)
        }
        .interactiveDismissDisabled(isSending)
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.hidden)
    }

    private func reasonRow(_ option: ReportReason) -> some View {
        let selected = reason == option
        return HStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke)
                if selected { Circle().fill(MV.C.ink).padding(6) }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(option.rawValue)).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                if !option.subtitle.isEmpty {
                    Text(option.subtitle).font(MVFont.body(12, weight: 500)).foregroundStyle(selected ? MV.C.ink.opacity(0.7) : MV.C.muted)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(selected ? MV.C.accent : MV.C.card)
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .contentShape(Rectangle())
        .onTapGesture { reason = option }
    }

    private func send() {
        guard !isSending else { return }
        if let social = store.social {
            if let reviewID, let comment = social.comments[reviewID]?.first(where: { $0.id == targetID }), comment.user != store.meID {
                isSending = true; errorMessage = nil
                Task {
                    if await social.reportComment(reviewID: reviewID, id: targetID, authorID: comment.user, reason: reason, alsoBlock: alsoBlock) {
                        store.showToast(L10n.text("Denúncia registrada. O comentário foi ocultado para você."))
                        dismiss()
                        await store.refreshAfterSafetyChange()
                        await social.loadReview(reviewID)
                        await social.loadComments(reviewID)
                    } else { errorMessage = social.actionError }
                    isSending = false
                }
                return
            }
            guard targetType == "review", let review = store.review(targetID), review.user != store.meID else {
                errorMessage = SocialError.unavailable.localizedDescription
                return
            }
            isSending = true; errorMessage = nil
            Task {
                if await social.report(targetID, authorID: review.user, reason: reason, alsoBlock: alsoBlock) {
                    store.showToast(L10n.text("Denúncia registrada. Esta review foi ocultada para você."))
                    dismiss()
                    Task { await store.refreshAfterSafetyChange() }
                } else { errorMessage = social.actionError }
                isSending = false
            }
            return
        }
        store.submitReport(targetType: targetType, targetID: targetID, reason: reason, alsoBlock: alsoBlock)
        if alsoBlock {
            Task { await auth.blockUser(handle: authorHandle) }
        }
        dismiss()
    }
}
