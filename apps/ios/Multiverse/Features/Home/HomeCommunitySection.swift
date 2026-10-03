import SwiftUI

/// Uses the existing community entry and cards; never downloads post images on Home.
struct HomeCommunitySection: View {
    @Environment(AppStore.self) private var store
    @State private var composing = false

    var body: some View {
        if store.communityAPI != nil {
            VStack(alignment: .leading, spacing: 12) {
                CommunityLink().padding(.horizontal, MV.pad)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(alignment: .leading, spacing: 12) { actions }
                }.padding(.horizontal, MV.pad)
                if let error = store.homeCommunity.error {
                    PeopleStatusNotice(message: error) { await load() }.padding(.horizontal, MV.pad)
                }
                if store.homeCommunity.busy && store.homeCommunity.posts.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if store.homeCommunity.posts.isEmpty && store.homeCommunity.error == nil {
                    Text(L10n.text("Qual assunto de Marvel ou DC você quer conversar hoje?"))
                        .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
                        .padding(.horizontal, MV.pad)
                }
                if !store.homeCommunity.posts.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(store.homeCommunity.posts.prefix(3)) { post in
                                CommunityPostCard(post: post, user: store.homeCommunity.users[post.user], compact: true)
                                    .frame(width: 280)
                            }
                        }.padding(.horizontal, MV.pad).padding(.bottom, 5)
                    }.scrollIndicators(.hidden)
                }
            }
            .task { await load() }
            .sheet(isPresented: $composing, onDismiss: { Task { await load() } }) {
                PostComposer(universe: nil, item: nil)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button { composing = true } label: {
            Label(L10n.text("COMEÇAR CONVERSA"), systemImage: "square.and.pencil")
        }.font(MVFont.bold(11)).buttonStyle(.borderedProminent).tint(MV.C.ink).fixedSize(horizontal: true, vertical: false)
        Button(L10n.text("SEM RESPOSTAS")) {
            store.push(.communityFeed(.init(feed: "unanswered")))
        }.font(MVFont.bold(11)).foregroundStyle(MV.C.ink).buttonStyle(.bordered).fixedSize(horizontal: true, vertical: false)
    }

    private func load() async {
        if let api = store.communityAPI { await store.homeCommunity.load(api: api, filter: .init()) }
    }
}
