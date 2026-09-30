import SwiftUI

/// Card 1080×1920 (proporção stories) renderizado via `ImageRenderer` pro compartilhamento
/// do Wrapped. Não aparece na tela — só existe pra virar imagem.
struct WrappedShareCard: View {
    let data: WrappedData
    let handle: String

    var body: some View {
        ZStack {
            MV.C.marvel
            Halftone(spacing: 8, radius: 1.4, color: MV.C.paper.opacity(0.18))

            VStack(alignment: .leading, spacing: 28) {
                Text(L10n.text("MULTIVERSE WRAPPED · SET 2026"))
                    .font(MVFont.label(13)).textCase(.uppercase).tracking(1.4)
                    .foregroundStyle(MV.C.paper.opacity(0.85))

                Text(L10n.text("SEU MÊS\nNO CÂNONE"))
                    .font(MVFont.display(64, width: 122))
                    .lineSpacing(-14)
                    .foregroundStyle(MV.C.paper)

                VStack(alignment: .leading, spacing: 14) {
                    stat(L10n.text("REGISTROS"), "\(data.logCount)")
                    stat(L10n.text("UNIVERSO DO MÊS"), data.universe.name.uppercased())
                    if let top = data.topItem { stat(L10n.text("NOTA MAIS ALTA"), top.title) }
                    stat(L10n.text("ARQUÉTIPO"), data.archetypeTitle.uppercased())
                }
                .padding(20)
                .background(MV.C.ink.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Spacer()

                Text(handle)
                    .font(MVFont.black(20))
                    .foregroundStyle(MV.C.paper)
            }
            .padding(40)
        }
        .frame(width: 360, height: 640)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(MVFont.label(10)).textCase(.uppercase).tracking(1).foregroundStyle(MV.C.paper.opacity(0.7))
            Text(value).font(MVFont.black(20)).foregroundStyle(MV.C.paper)
        }
    }
}
