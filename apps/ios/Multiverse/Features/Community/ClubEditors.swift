import SwiftUI

struct ClubEditor: View {
    var universe: String? = nil; var editing: LiveClub? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var id = UUID().uuidString.lowercased()
    @State private var selectedUniverse = ""
    @State private var name = ""
    @State private var description = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pending: ClubInput?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.text("Clubes são públicos. Pessoas podem encontrar o clube e entrar para participar."))
                    if editing == nil && universe == nil { Picker(L10n.text("Universo"), selection: $selectedUniverse) { ForEach(store.universes) { Text($0.name).tag($0.id) } } }
                    TextField(L10n.text("Nome do clube"), text: $name)
                    TextField(L10n.text("Descrição do clube"), text: $description, axis: .vertical).lineLimit(3...8)
                }.disabled(busy || pending != nil)
                if let error { AuthErrorBanner(message: error) }
                Button(L10n.text("SALVAR")) { Task { await save() } }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.unicodeScalars.count > 80 || description.unicodeScalars.count > 1000 || selectedUniverse.isEmpty)
            }.navigationTitle(editing == nil ? L10n.text("CRIAR CLUBE") : L10n.text("EDITAR CLUBE"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy || pending != nil)
        .onAppear { if selectedUniverse.isEmpty { selectedUniverse = editing?.universeID ?? universe ?? store.universes.first?.id ?? ""; if let editing { id = editing.id; name = editing.name; description = editing.description } } }
    }
    private func save() async {
        guard let api = store.spacesAPI else { return }; busy = true; error = nil; defer { busy = false }
        let input = pending ?? ClubInput(name: name, description: description, universeID: selectedUniverse, version: editing?.version); pending = input
        do {
            let receipt = try await api.saveClub(id: id, input: input)
            guard receipt.saved, receipt.id == id else { throw SocialError.invalid }
            pending = nil; dismiss(); if editing == nil { store.push(.liveClub(id)) }
        } catch { self.error = error.localizedDescription }
    }
}
struct ScheduleEditor: View {
    let club: LiveClub
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var id = UUID().uuidString.lowercased()
    @State private var item = ""
    @State private var startsOn = Date.now
    @State private var units = 1
    @State private var unitLabel = ""
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pending: ScheduleInput?
    private var works: [Item] { store.items.filter { $0.uni == club.universeID && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.text("Buscar obra"), text: $query)
                    Picker(L10n.text("Obra"), selection: $item) { Text(L10n.text("Selecione uma obra")).tag(""); ForEach(works) { Text($0.title).tag($0.id) } }
                    DatePicker(L10n.text("Início"), selection: $startsOn, displayedComponents: .date)
                    Stepper(L10n.format("%1$@ unidades", String(units)), value: $units, in: 1...10000)
                    TextField(L10n.text("Unidade: capítulos, páginas, episódios…"), text: $unitLabel)
                }.disabled(busy || pending != nil)
                if let error { AuthErrorBanner(message: error) }
                Button(L10n.text("ADICIONAR ETAPA")) { Task { await save() } }.disabled(busy || item.isEmpty || unitLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unitLabel.count > 30)
            }.navigationTitle(L10n.text("ADICIONAR ETAPA"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy || pending != nil)
    }
    private func save() async {
        guard let api = store.spacesAPI else { return }; busy = true; error = nil; defer { busy = false }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        let input = pending ?? ScheduleInput(itemID: item, startsOn: formatter.string(from: startsOn), totalUnits: units, unitLabel: unitLabel); pending = input
        do { let r = try await api.saveSchedule(club: club.id, id: id, input: input); guard r.saved, r.id == id else { throw SocialError.invalid }; pending = nil; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
struct ClubReportForm: View {
    let id: String; let completed: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ReportReason.spam
    @State private var block = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.text("Motivo"), selection: $reason) { ForEach(ReportReason.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Bloquear também o organizador"), isOn: $block)
                if let error { AuthErrorBanner(message: error) }
                Button(L10n.text("ENVIAR DENÚNCIA")) { Task {
                    guard let api = store.spacesAPI else { return }; busy = true; defer { busy = false }
                    do { let r = try await api.reportClub(id, reason: reason.apiValue, block: block); guard r.saved, r.id == id else { throw SocialError.invalid }; dismiss(); completed() }
                    catch { self.error = error.localizedDescription }
                } }.disabled(busy)
            }.navigationTitle(L10n.text("DENUNCIAR CLUBE"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy)
    }
}
