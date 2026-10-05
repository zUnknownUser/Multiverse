import FirebaseAuth

@MainActor protocol AuthIdentityObserving: AnyObject {
    func start(_ changed: @escaping @MainActor @Sendable (String?) -> Void)
}

/// The listener token owns its removal; the Firebase callback never retains the store.
private final class IdentityListener: @unchecked Sendable {
    let auth: Auth
    let handle: AuthStateDidChangeListenerHandle
    init(auth: Auth, handle: AuthStateDidChangeListenerHandle) {
        self.auth = auth; self.handle = handle
    }
    deinit { auth.removeStateDidChangeListener(handle) }
}

@MainActor final class FirebaseIdentityObserver: AuthIdentityObserving {
    private var listener: IdentityListener?
    func start(_ changed: @escaping @MainActor @Sendable (String?) -> Void) {
        let auth = Auth.auth()
        let handle = auth.addStateDidChangeListener { _, user in
            let uid = user?.uid
            Task { @MainActor in
                // Ignore callbacks queued before another SDK identity transition.
                guard Auth.auth().currentUser?.uid == uid else { return }
                changed(uid)
            }
        }
        listener = IdentityListener(auth: auth, handle: handle)
    }
}
