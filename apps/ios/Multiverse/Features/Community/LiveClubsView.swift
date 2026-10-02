import SwiftUI

struct LiveClubsView: View {
    var universe: String? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var clubs: [LiveClub] = []
    @State private var cursor: String?
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?
    @State private var creating = false
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("CLUBES")).font(MVFont.display(28, width: 122))
                Text(L10n.text("Leia, acompanhe e converse em grupo.")).font(MVFont.body(14, weight: 500))
                TextField(L10n.text("Buscar clubes"), text: $query).padding(12).comicCard(shadow: MV.Shadow.s)
                Button(L10n.text("CRIAR CLUBE")) { creating = true }.buttonStyle(.borderedProminent)
                if let error { AuthErrorBanner(message: error); Button(L10n.text("TENTAR DE NOVO")) { Task { await load() } } }
                if busy { ProgressView() }
                if clubs.isEmpty && !busy && error == nil { CommunityEmptyMessage(text: L10n.text("Nenhum clube por aqui ainda. Crie o primeiro.")) }
                ForEach(clubs) { club in
                    Button { store.push(.liveClub(club.id)) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(club.name).font(MVFont.section(20))
                            Text(club.description).font(MVFont.body(14, weight: 500)).lineLimit(3)
                            HStack { Label("\(club.memberCount)", systemImage: "person.3"); Spacer(); if club.joined { Text(L10n.text("PARTICIPANDO")).kicker() } }
                        }.foregroundStyle(MV.C.ink).frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard()
                    }.buttonStyle(.plain)
                }
                if cursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await load(more: true) } }.disabled(busy) }
            }.padding(MV.pad)
        }.task(id: query) {
            do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation(); await load() } catch { }
        }.refreshable { await load() }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) { ClubEditor(universe: universe) }
    }
    private func load(more: Bool = false) async {
        guard let api = store.spacesAPI else { return }; let requestedQuery = query; busy = true; error = nil
        defer { if requestedQuery == query { busy = false } }
        do {
            let page = try await api.fetchClubs(query: requestedQuery, universe: universe, after: more ? cursor : nil)
            try Task.checkCancellation(); guard requestedQuery == query else { return }
            let previous = more ? clubs : []; clubs = previous + page.clubs.filter { next in !previous.contains { $0.id == next.id } }; cursor = page.nextCursor
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}
struct CommunityEmptyMessage: View {
    let text: String
    var body: some View { Text(text).font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.muted).frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard(shadow: MV.Shadow.s) }
}
struct LiveClubView: View {
    let id: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var detail: LiveClubDetail?
    @State private var members: [ClubMember] = []
    @State private var memberCursor: String?
    @State private var selectedSchedule = ""
    @State private var units = 0
    @State private var busy = false
    @State private var error: String?
    @State private var editing = false
    @State private var addingSchedule = false
    @State private var deleting = false
    @State private var reporting = false
    @State private var deletingSchedule: ClubSchedule?
    private var plan: ClubSchedule? { detail?.schedule.first { $0.id == selectedSchedule } }
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                if let error { AuthErrorBanner(message: error); Button(L10n.text("TENTAR DE NOVO")) { Task { await load() } } }
                if busy { ProgressView() }
                if let detail {
                    hero(detail.club)
                    membership(detail.club)
                    Text(L10n.text("CALENDÁRIO")).font(MVFont.section(19))
                    if detail.schedule.isEmpty { CommunityEmptyMessage(text: L10n.text("O organizador ainda não adicionou obras ao calendário.")) }
                    else {
                        Picker(L10n.text("Etapa do clube"), selection: $selectedSchedule) {
                            ForEach(detail.schedule) { schedule in Text("\(schedule.startsOn) · \(store.item(schedule.itemID)?.title ?? schedule.itemID)").tag(schedule.id) }
                        }.tint(MV.C.ink)
                    }
                    if let plan {
                        VStack(alignment: .leading, spacing: 12) {
                            if let item = store.item(plan.itemID) {
                                HStack(spacing: 12) {
                                    Button { store.push(.item(item.id)) } label: { PosterView(item: item, universe: store.universe(of: item), width: 60, height: 90, titleSize: 9) }.buttonStyle(.plain)
                                    VStack(alignment: .leading) { Text(item.title).font(MVFont.section(18)); Text(plan.startsOn).kicker(); Text("\(plan.totalUnits) \(plan.unitLabel)").font(MVFont.body(12, weight: 600)) }
                                }
                            }
                            if detail.club.joined {
                                Stepper(value: $units, in: 0...plan.totalUnits) { Text("\(units)/\(plan.totalUnits) \(plan.unitLabel)").font(MVFont.bold(13)) }
                                ComicProgress(value: Double(units) / Double(plan.totalUnits), fill: MV.C.wow, height: 12)
                                Button(L10n.text("SALVAR PROGRESSO")) { Task { await saveProgress(plan) } }.disabled(busy || units == plan.myUnits)
                            }
                            Button(L10n.text("CONVERSAR SOBRE ESTA ETAPA")) { store.push(.communityFeed(.init(universe: detail.club.universeID, item: plan.itemID, club: id, schedule: plan.id))) }
                            if detail.club.owner == store.meID { Button(L10n.text("REMOVER ETAPA"), role: .destructive) { deletingSchedule = plan }.disabled(busy) }
                        }.padding(14).comicCard()
                    }
                    if detail.club.owner == store.meID { Button(L10n.text("ADICIONAR ETAPA")) { addingSchedule = true }.disabled(busy) }
                    Button(L10n.text("CONVERSA DO CLUBE")) { store.push(.communityFeed(.init(universe: detail.club.universeID, club: id))) }.buttonStyle(.borderedProminent)
                    if detail.club.joined {
                        Text(L10n.text("MEMBROS E PROGRESSO")).font(MVFont.section(19))
                        ForEach(members) { member in
                            HStack(spacing: 10) {
                                Button { store.openUserProfile(member.id) } label: { HStack { AvatarView(user: member.user, size: 30); Text(member.name).font(MVFont.bold(13)) } }.buttonStyle(.plain)
                                Spacer()
                                if let plan { Text("\(member.units)/\(plan.totalUnits)").font(MVFont.bold(12)) }
                            }
                        }
                        if memberCursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await loadMembers(more: true) } }.disabled(busy) }
                    }
                    if detail.club.owner != store.meID { Button(L10n.text("DENUNCIAR CLUBE")) { reporting = true } }
                    if detail.club.owner == store.meID {
                        Button(L10n.text("EDITAR CLUBE")) { editing = true }.disabled(busy)
                        Button(L10n.text("EXCLUIR CLUBE"), role: .destructive) { deleting = true }.disabled(busy)
                    }
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }.task { await load() }.refreshable { await load() }
        .onChange(of: selectedSchedule) { _, _ in units = plan?.myUnits ?? 0; Task { await loadMembers() } }
        .sheet(isPresented: $reporting) { ClubReportForm(id: id) { dismiss() } }
        .sheet(isPresented: $editing, onDismiss: { Task { await load() } }) { if let club = detail?.club { ClubEditor(universe: club.universeID, editing: club) } }
        .sheet(isPresented: $addingSchedule, onDismiss: { Task { await load() } }) { if let club = detail?.club { ScheduleEditor(club: club) } }
        .confirmationDialog(L10n.text("Excluir este clube e encerrar suas conversas?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(L10n.text("EXCLUIR CLUBE"), role: .destructive) { Task { await remove() } }
        }
        .confirmationDialog(L10n.text("Remover esta etapa e sua discussão?"), isPresented: Binding(get: { deletingSchedule != nil }, set: { if !$0 { deletingSchedule = nil } }), titleVisibility: .visible) {
            Button(L10n.text("REMOVER ETAPA"), role: .destructive) { if let removing = deletingSchedule { Task { await removeSchedule(removing) } } }
        }
    }
    private func hero(_ club: LiveClub) -> some View {
        let uni = store.universe(club.universeID)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("CLUBE")).kicker()
            Text(club.name.uppercased()).font(MVFont.display(30, width: 122))
            Text(club.description).font(MVFont.body(14, weight: 500))
            Label("\(club.memberCount)", systemImage: "person.3").font(MVFont.bold(12))
        }.foregroundStyle(uni?.inkColor ?? MV.C.ink).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(uni?.color ?? MV.C.wow).comicCard()
    }
    private func membership(_ club: LiveClub) -> some View {
        HStack {
            if club.owner != store.meID {
                Button(club.joined ? L10n.text("SAIR DO CLUBE") : L10n.text("ENTRAR NO CLUBE")) { Task { await join(!club.joined) } }.disabled(busy)
            }
            Spacer()
            ShareLink(item: "\(club.name) · Multiverse\nmultiverse://club/\(club.id)") { Label(L10n.text("CONVIDAR"), systemImage: "square.and.arrow.up") }
        }.font(MVFont.bold(12))
    }
    private func load() async {
        guard !busy, let api = store.spacesAPI else { return }; busy = true; error = nil
        do {
            let result = try await api.fetchClub(id); try Task.checkCancellation(); detail = result
            if !result.schedule.contains(where: { $0.id == selectedSchedule }) { selectedSchedule = result.schedule.first?.id ?? "" }
            units = plan?.myUnits ?? 0; busy = false; await loadMembers()
        } catch { self.error = error.localizedDescription; if case CommunityError.clubUnavailable = error { detail = nil; members = [] }; busy = false }
    }
    private func loadMembers(more: Bool = false) async {
        guard detail?.club.joined == true, let api = store.spacesAPI else { members = []; return }
        let requested = selectedSchedule
        do {
            let result = try await api.fetchClubMembers(club: id, schedule: requested.isEmpty ? nil : requested, after: more ? memberCursor : nil)
            try Task.checkCancellation(); guard requested == selectedSchedule else { return }
            let previous = more ? members : []; members = previous + result.members.filter { next in !previous.contains { $0.id == next.id } }; memberCursor = result.nextCursor
        } catch { self.error = error.localizedDescription }
    }
    private func perform(_ action: (any SpacesAPI) async throws -> Void) async {
        guard !busy, let api = store.spacesAPI else { return }; busy = true; error = nil
        do { try await action(api); busy = false; await load() } catch { self.error = error.localizedDescription; busy = false }
    }
    private func join(_ joined: Bool) async { await perform { api in let r = try await api.joinClub(id, joined: joined); guard r.saved, r.id == id else { throw SocialError.invalid } } }
    private func saveProgress(_ plan: ClubSchedule) async { let value = units; await perform { api in let r = try await api.saveClubProgress(club: id, schedule: plan.id, units: value); guard r.saved, r.id == plan.id else { throw SocialError.invalid } } }
    private func removeSchedule(_ plan: ClubSchedule) async { await perform { api in let r = try await api.deleteSchedule(club: id, id: plan.id); guard r.deleted, r.id == plan.id else { throw SocialError.invalid } } }
    private func remove() async {
        guard !busy, let api = store.spacesAPI else { return }; busy = true
        do { let r = try await api.deleteClub(id); guard r.deleted, r.id == id else { throw SocialError.invalid }; dismiss() }
        catch { self.error = error.localizedDescription }; busy = false
    }
}
