import SwiftUI

struct DiaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = DiaryQuery()
    @State private var visibleCount = 30
    private var matchingEntries: [DiaryEntry] { store.usesRemoteActivity ? store.diary : query.entries(store.diary) { store.item($0)?.title ?? "" } }
    private var groupedByMonth: [DiaryMonth] { DiaryTimeline.months(store.usesRemoteActivity ? matchingEntries : Array(matchingEntries.prefix(visibleCount))) }
    private var years: [Int] { store.diaryStore.summary?.years.sorted(by: >) ?? Array(Set(store.diary.map { Calendar.current.component(.year, from: $0.loggedAt) })).sorted(by: >) }

    private var yearRange: String {
        if let first = years.min(), let last = years.max() { return first == last ? String(first) : "\(first)–\(last)" }
        let dates = store.diary.map(\.loggedAt)
        let first = L10n.date(dates.min() ?? .now, template: "yyyy")
        let last = L10n.date(dates.max() ?? .now, template: "yyyy")
        return first == last ? first : "\(first)–\(last)"
    }

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            LazyVStack(alignment: .leading, spacing: 22) {
                ActivityRefreshNotice()
                if store.isDeletingLog {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.text("EXCLUINDO…")).font(MVFont.body(13, weight: 600))
                    }
                }
                if let error = store.diaryDeleteError, let pending = store.pendingDiaryDeletion {
                    VStack(alignment: .leading, spacing: 8) {
                        AuthErrorBanner(message: error)
                        Button(L10n.text("TENTAR EXCLUIR NOVAMENTE")) { store.deleteLog(id: pending.id) }
                            .font(MVFont.bold(12)).foregroundStyle(MV.C.ink)
                            .disabled(store.isMutatingActivity)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("DIÁRIO")).font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
                    Text(store.diaryCount == 0 ? L10n.text("Nenhum registro ainda") : L10n.format("diary.recordCount", store.diaryCount) + " · " + yearRange)
                        .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.muted)
                }

                if store.diaryCount > 0 {
                    TextField(L10n.text("Buscar obra pelo título"), text: $query.text).padding(12).comicCard(shadow: MV.Shadow.s).autocorrectionDisabled()
                    HStack {
                        Picker(L10n.text("Filtrar registros"), selection: $query.selection) {
                            ForEach(DiarySelection.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) }
                        }
                        Picker(L10n.text("Ano"), selection: $query.year) {
                            Text(L10n.text("Todos os anos")).tag(nil as Int?)
                            ForEach(years, id: \.self) { Text(String($0)).tag(Optional($0)) }
                        }
                    }.tint(MV.C.ink)
                    if matchingEntries.isEmpty {
                        Text(L10n.text("Nenhum registro corresponde aos filtros.")).font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                        Button(L10n.text("LIMPAR FILTROS")) { query = DiaryQuery() }
                    }
                }
                if store.diaryCount == 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Seu diário começa com o primeiro registro."))
                            .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                        PrimaryAuthButton(title: L10n.text("FAZER PRIMEIRO REGISTRO")) { store.openLogBlank() }
                    }
                }

                ForEach(groupedByMonth) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(L10n.date(group.start, template: Calendar.current.isDate(group.start, equalTo: .now, toGranularity: .year) ? "LLLL" : "LLLL yyyy").uppercased())
                                .font(MVFont.black(11)).tracking(0.4)
                                .foregroundStyle(MV.C.paper)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(MV.C.ink)
                            Rectangle().fill(MV.C.ink).frame(height: 2)
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(group.entries) { entry in
                                DiaryRow(entry: entry)
                            }
                        }
                    }
                }
                if let error = store.diaryStore.pageError { AuthErrorBanner(message: error) }
                if store.usesRemoteActivity && (store.diaryStore.nextCursor != nil || store.diaryStore.pageError != nil) {
                    PrimaryAuthButton(title: L10n.text("CARREGAR MAIS"), isLoading: store.diaryStore.isLoadingPage) {
                        Task { await store.loadDiaryPage(query: query, more: query == store.diaryStore.query && store.diaryStore.nextCursor != nil) }
                    }
                }
                if !store.usesRemoteActivity && matchingEntries.count > visibleCount {
                    PrimaryAuthButton(title: L10n.text("CARREGAR MAIS")) { visibleCount += 30 }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .task(id: query) {
            visibleCount = 30
            guard store.usesRemoteActivity, query != store.diaryStore.query else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await store.loadDiaryPage(query: query)
        }
        .onAppear { query = store.diaryStore.query }
        .onChange(of: store.diaryStore.query) { _, value in query = value }
        .refreshable { await store.refreshActivity() }
    }
}

private struct DiaryRow: View {
    let entry: DiaryEntry
    @Environment(AppStore.self) private var store
    @State private var confirmingDeletion = false

    var body: some View {
        if let item = store.item(entry.itemId) {
            let uni = store.universe(of: item)
            HStack(alignment: .top, spacing: 4) {
                Button { store.push(.item(item.id)) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(Calendar.current.component(.day, from: entry.loggedAt))").font(MVFont.black(24)).foregroundStyle(MV.C.ink).frame(width: 34, alignment: .leading)
                        PosterView(item: item, universe: uni, width: 34, height: 51, titleSize: 7, showLabel: false)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                            Text("\(L10n.text(item.type)) · \(uni.name)").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                            StarsText(rating: entry.rating, color: uni.color, size: 13)
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            if entry.liked { Text("♥").foregroundStyle(MV.C.marvel) }
                            if entry.rewatch { Text("↻").foregroundStyle(MV.C.ink) }
                        }
                        .font(.system(size: 14, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                if store.usesRemoteActivity {
                    Menu {
                        Button { store.editLog(id: entry.id) } label: {
                            Label(L10n.text("Editar registro"), systemImage: "pencil")
                        }
                        .disabled(store.pendingDiaryDeletion?.id == entry.id)
                        Button(role: .destructive) { confirmingDeletion = true } label: {
                            Label(L10n.text("Excluir registro"), systemImage: "trash")
                        }
                        .disabled(store.pendingDiaryDeletion != nil)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(MV.C.ink).frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L10n.text("Ações do registro"))
                    .disabled(store.isMutatingActivity)
                    .confirmationDialog(L10n.text("Excluir registro?"), isPresented: $confirmingDeletion, titleVisibility: .visible) {
                        Button(L10n.text("Excluir registro"), role: .destructive) { store.deleteLog(id: entry.id) }
                        Button(L10n.text("Cancelar"), role: .cancel) {}
                    } message: {
                        Text(L10n.text("A review, os comentários e as reações deste registro também serão excluídos. Esta ação não pode ser desfeita."))
                    }
                }
            }
        }
    }
}
