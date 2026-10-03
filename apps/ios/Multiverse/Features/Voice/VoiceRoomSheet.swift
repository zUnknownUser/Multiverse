import SwiftUI
import AVKit

struct VoiceRoomSheet: View {
    let voice: VoiceSession
    let api: (any VoiceAPI)?
    let item: String
    let title: String
    let segment: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var availability: VoiceAvailability?
    @State private var loading = true
    private var segmentTitle: String { segment == 0 ? L10n.text("Geral") : segment == 1 ? L10n.text("Até a metade") : L10n.text("Final") }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("CONVERSA POR VOZ")).kicker(10).foregroundStyle(MV.C.muted)
                    Text(title).font(MVFont.section(20)).lineLimit(2)
                    Text(segmentTitle).font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("FECHAR"))
            }.padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = voice.error { AuthErrorBanner(message: error) }
                    if voice.state == .connected || voice.state == .reconnecting {
                        Text(voice.state == .reconnecting ? L10n.text("Reconectando à sala…") : L10n.format("%1$@ pessoas na voz", String(voice.participants.count)))
                            .font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                        ForEach(voice.participants) { person in
                            HStack(spacing: 12) {
                                Text(String(person.name.prefix(1)).uppercased()).font(MVFont.bold(17))
                                    .frame(width: 42, height: 42).background(MV.C.desk, in: Circle())
                                    .overlay(Circle().strokeBorder(person.speaking ? MV.C.dc : .clear, lineWidth: 3))
                                Text(person.local ? L10n.text("Você") : person.name).font(MVFont.bold(14))
                                Spacer()
                                Image(systemName: person.muted ? "mic.slash" : person.speaking ? "waveform" : "mic")
                                    .foregroundStyle(person.speaking ? MV.C.dc : MV.C.muted)
                                    .accessibilityLabel(person.muted ? L10n.text("Microfone desligado") : L10n.text("Microfone ligado"))
                            }.padding(12).comicCard(shadow: MV.Shadow.s)
                        }
                    } else {
                        Image(systemName: "waveform").font(.system(size: 32, weight: .light))
                            .frame(maxWidth: .infinity).padding(.top, 12)
                        Text(L10n.text("Entre para ouvir. Ligue o microfone quando quiser falar."))
                            .font(MVFont.body(15)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        Text(L10n.text("Até 8 pessoas. O áudio termina ao sair da sala ou colocar o app em segundo plano."))
                            .font(MVFont.body(12)).foregroundStyle(MV.C.muted).multilineTextAlignment(.center)
                        if !loading && availability?.enabled != true {
                            Text(L10n.text("A voz está indisponível agora. Tente novamente em instantes."))
                                .font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                        }
                    }
                }.padding(20)
            }.scrollIndicators(.hidden)
            controls.padding(20)
        }
        .foregroundStyle(MV.C.ink).background(MV.C.paper)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: voice.state)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationBackground(MV.C.paper).presentationCornerRadius(MV.R.sheet)
        .task {
            defer { loading = false }
            do { availability = try await api?.voiceAvailability() }
            catch { voice.error = error.localizedDescription }
        }
    }
    @ViewBuilder private var controls: some View {
        if voice.state == .connected || voice.state == .reconnecting {
            HStack(spacing: 12) {
                Button { Task { await voice.toggleMicrophone() } } label: {
                    Label(voice.muted ? L10n.text("FALAR") : L10n.text("SILENCIAR"), systemImage: voice.muted ? "mic.slash" : "mic.fill")
                        .font(MVFont.label(12)).frame(maxWidth: .infinity, minHeight: 50)
                        .comicCard(bg: voice.muted ? MV.C.card : MV.C.desk, radius: MV.R.md)
                }.buttonStyle(.plain).disabled(voice.changingMic || voice.state != .connected)
                VoiceAudioRoutePicker().frame(width: 44, height: 44).accessibilityLabel(L10n.text("SAÍDA DE ÁUDIO"))
                Button { Task { await voice.leave() } } label: {
                    Image(systemName: "phone.down.fill").foregroundStyle(.white).frame(width: 52, height: 50)
                        .comicCard(bg: MV.C.marvel, radius: MV.R.md)
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("SAIR DA VOZ"))
            }
        } else {
            Button {
                if voice.active { Task { await voice.leave() } }
                else if let api { Task { await voice.join(api: api, item: item, segment: segment) } }
            } label: {
                HStack(spacing: 10) {
                    if loading || voice.active { ProgressView() }
                    Text(voice.active ? L10n.text("CANCELAR") : L10n.text("ENTRAR NA VOZ")).font(MVFont.label(13))
                }.foregroundStyle(Color(hex: "#16130F")).frame(maxWidth: .infinity, minHeight: 52)
                    .comicCard(bg: MV.C.accent, radius: MV.R.md)
            }.buttonStyle(.plain).disabled(loading || availability?.enabled != true || voice.state == .leaving)
        }
    }
}
private struct VoiceAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.prioritizesVideoDevices = false; view.tintColor = .label; return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
