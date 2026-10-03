import SwiftUI

/// Campo de texto no estilo gibi: kicker label, borda 2pt, sombra dura, com acessório à direita opcional.
struct AuthField<Trailing: View>: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure = false
    var errored = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    @ViewBuilder var trailing: () -> Trailing

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).kicker(11).foregroundStyle(errored ? MV.C.marvel : MV.C.ink)
            HStack(spacing: 8) {
                Group {
                    if isSecure && !revealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(MVFont.body(16, weight: 500))
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .focused($focused)

                if isSecure {
                    Button(revealed ? L10n.text("OCULTAR") : L10n.text("MOSTRAR")) { revealed.toggle() }
                        .font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                        .buttonStyle(.plain)
                } else {
                    trailing()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(MV.C.card)
            .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(errored ? MV.C.marvel : MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
            .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.s, y: MV.Shadow.s))
        }
    }
}

extension AuthField where Trailing == EmptyView {
    init(label: String, text: Binding<String>, placeholder: String = "", isSecure: Bool = false, errored: Bool = false, keyboardType: UIKeyboardType = .default, autocapitalization: TextInputAutocapitalization = .sentences) {
        self.init(label: label, text: text, placeholder: placeholder, isSecure: isSecure, errored: errored, keyboardType: keyboardType, autocapitalization: autocapitalization, trailing: { EmptyView() })
    }
}

/// Barra "OPS!" de erro no topo do formulário.
struct AuthErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(L10n.text("OPS!"))
                .font(MVFont.black(12))
                .foregroundStyle(MV.C.ink)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(MV.C.card)
                .overlay(RoundedRectangle(cornerRadius: MV.R.xs).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.xs))
            Text(message).font(MVFont.bold(13)).foregroundStyle(MV.C.paper)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(MV.C.marvel)
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.s, y: MV.Shadow.s))
    }
}

/// Barra de força de senha (4 segmentos) + rótulo "Força: {label}".
struct PasswordStrengthMeter: View {
    let password: String
    var trailingHint: String? = nil

    private var strength: PasswordStrength { .evaluate(password) }
    private var color: Color {
        switch strength {
        case .fraca: return MV.C.marvel
        case .media: return MV.C.accent
        case .boa: return MV.C.accent
        case .excelente: return MV.C.dc
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < strength.rawValue ? color : Color.clear)
                        .frame(height: 6)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(MV.C.ink, lineWidth: 1.5))
                }
            }
            HStack {
                Text(L10n.format("Força: %1$@", String(describing: strength.label))).font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                Spacer()
                if let trailingHint {
                    Text(trailingHint).font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                }
            }
        }
    }
}

/// Checklist "Pelo menos 8 caracteres / Uma letra maiúscula / Um número ou símbolo".
struct PasswordRequirementsList: View {
    let requirements: PasswordRequirements

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(L10n.text("Pelo menos 8 caracteres"), met: requirements.hasEightChars)
            row(L10n.text("Uma letra maiúscula"), met: requirements.hasUppercase)
            row(L10n.text("Um número ou símbolo"), met: requirements.hasNumberOrSymbol)
        }
        .padding(14)
        .comicCard(shadow: 0)
    }

    private func row(_ text: String, met: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(met ? MV.C.ink : Color.clear)
                Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke)
                if met { Text("✓").font(MVFont.black(11)).foregroundStyle(MV.C.paper) }
            }
            .frame(width: 22, height: 22)
            Text(text).font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
        }
    }
}
