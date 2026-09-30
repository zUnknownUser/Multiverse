import SwiftUI

/// 6 caixas de código (verificação de e-mail), digitadas via um campo invisível por cima.
struct CodeInputBoxes: View {
    @Binding var code: String
    var length = 6
    var errored = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { i in
                    let chars = Array(code)
                    let filled = i < chars.count
                    Text(filled ? String(chars[i]) : "")
                        .font(MVFont.black(24))
                        .foregroundStyle(MV.C.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(MV.C.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: MV.R.md)
                                .strokeBorder(errored ? MV.C.marvel : (i == chars.count ? MV.C.marvel : MV.C.ink), lineWidth: MV.stroke)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                }
            }
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.02)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(length))
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
    }
}
