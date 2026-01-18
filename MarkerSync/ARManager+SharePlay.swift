import GroupActivities
import Combine

extension ARManager {
    // MARK: - SharePlay Management

    /// Start SharePlay session
    func startSharePlay() async throws {
        let activity = ARCollaborationActivity()

        switch await activity.prepareForActivation() {
        case .activationPreferred:
            _ = try await activity.activate()
            appState = .waitingForHost
            userRole = .undetermined

        case .activationDisabled:
            appState = .waitingForHost
            print("SharePlay disabled - local mode")

        case .cancelled:
            appState = .waitingForSharePlay

        @unknown default:
            break
        }
    }

    /// Observe incoming GroupSessions
    func observeGroupSessions() {
        groupSessionTask?.cancel()

        groupSessionTask = Task { [weak self] in
            guard let self = self else { return }

            for await session in ARCollaborationActivity.sessions() {
                if Task.isCancelled { break }

                await MainActor.run {
                    self.configureGroupSession(session)
                }
            }
        }
    }

    /// Configure new GroupSession
    private func configureGroupSession(_ session: GroupSession<ARCollaborationActivity>) {
        self.groupSession?.leave()
        self.subscriptions.removeAll()

        self.groupSession = session

        // Monitor session state
        session.$state
            .sink { [weak self] state in
                guard let self = self else { return }

                Task { @MainActor in
                    switch state {
                    case .joined:
                        self.isConnected = true
                        self.appState = .waitingForHost

                    case .waiting:
                        self.isConnected = false

                    case .invalidated:
                        self.isConnected = false
                        self.handleSessionInvalidation()

                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &subscriptions)

        // Monitor participants
        session.$activeParticipants
            .sink { participants in
                print("👥 Active participants: \(participants.count)")
            }
            .store(in: &subscriptions)

        session.join()
    }

    /// Handle session end
    private func handleSessionInvalidation() {
        appState = .error("연결이 끊어졌습니다")

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await retry()
        }
    }
}
