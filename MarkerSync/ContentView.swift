//
//  ContentView.swift
//  MarkerSync
//
//  Created by 박예준 on 1/18/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(ARManager.self) var arManager
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    
    @State private var showDebugPanel = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 상단 헤더
            headerView
            
            Divider()
            
            // 메인 콘텐츠
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 하단 상태 바
            bottomStatusBar
        }
        .frame(minWidth: 350, minHeight: 300)
        .task {
            await arManager.initialize()
        }
        .onChange(of: arManager.sharedAnchors.count) { oldCount, newCount in
            handleAnchorsChanged(oldCount: oldCount, newCount: newCount)
        }
        .onChange(of: arManager.trackingStatus) { _, newStatus in
            handleTrackingStatusChanged(newStatus)
        }
        .onChange(of: arManager.isConnected) { _, isConnected in
            handleConnectionChanged(isConnected)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // 앱 타이틀
            HStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("K2 MR Viewer")
                    .font(.headline)
            }
            
            Spacer()
            
            // 역할 배지
            RoleBadge(role: arManager.userRole)
            
            // 연결 상태
            ConnectionIndicator(isConnected: arManager.isConnected)
            
            // 디버그 토글
            Button(action: { showDebugPanel.toggle() }) {
                Image(systemName: "ladybug")
                    .foregroundColor(showDebugPanel ? .orange : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 24) {
            switch arManager.appState {
            case .initializing:
                InitializingView()
                
            case .waitingForSharePlay:
                WaitingForSharePlayView(
                    onStartSharePlay: startSharePlay,
                    onSkipSharePlay: skipSharePlay
                )
                
            case .waitingForHost:
                WaitingForHostView(
                    onBecomeHost: becomeHost,
                    trackingStatus: arManager.trackingStatus
                )
                
            case .hostMode:
                HostModeView(trackingStatus: arManager.trackingStatus)
                
            case .viewingModel:
                ViewingModelView(
                    anchorsCount: arManager.sharedAnchors.count,
                    userRole: arManager.userRole
                )
                
            case .error(let message):
                ErrorView(
                    message: message,
                    onRetry: retry
                )
            }
            
            // 디버그 패널
            if showDebugPanel {
                DebugInfoPanel(arManager: arManager)
            }
        }
        .padding(40)
        .animation(.easeInOut(duration: 0.3), value: arManager.appState)
    }
    
    // MARK: - Bottom Status Bar
    
    private var bottomStatusBar: some View {
        HStack {
            // TrackingStatus 표시
            TrackingStatusIndicator(status: arManager.trackingStatus)
            
            Spacer()
            
            // 앵커 카운트
            if arManager.sharedAnchors.count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.green)
                    Text("\(arManager.sharedAnchors.count)개 앵커")
                        .font(.caption)
                }
            }
            
            // 위치 힌트
            if arManager.positionHint != .none {
                Text(arManager.positionHint.message)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Actions
    
    private func startSharePlay() {
        Task {
            do {
                try await arManager.startSharePlay()
            } catch {
                print("❌ SharePlay start failed: \(error)")
            }
        }
    }
    
    private func skipSharePlay() {
        // SharePlay 없이 단독 모드로 진행
        arManager.appState = .waitingForHost
        arManager.userRole = .host
    }
    
    private func becomeHost() {
        Task {
            arManager.userRole = .host
            arManager.appState = .hostMode
            await openImmersiveSpace(id: "tracking")
        }
    }
    
    private func retry() {
        Task {
            await arManager.retry()
        }
    }
    
    // MARK: - State Change Handlers
    
    private func handleAnchorsChanged(oldCount: Int, newCount: Int) {
        // Participant가 앵커를 수신하면 모델 뷰로 전환
        if newCount > 0 && arManager.userRole == .participant {
            Task { @MainActor in
                await openImmersiveSpace(id: "model")
                arManager.appState = .viewingModel
            }
        }
    }
    
    private func handleTrackingStatusChanged(_ status: TrackingStatus) {
        // Anchored 상태가 되면 모델 뷰로 전환
        if status == .anchored && arManager.userRole == .host {
            Task { @MainActor in
                // MarkerTrackingView에서 이미 처리하지만 백업용
                if arManager.appState != .viewingModel {
                    arManager.appState = .viewingModel
                }
            }
        }
    }
    
    private func handleConnectionChanged(_ isConnected: Bool) {
        if !isConnected && arManager.appState == .viewingModel {
            // 연결 끊김은 ModelDisplayView에서 처리하므로 여기서는 로그만
            print("⚠️ Connection lost while viewing model")
        }
    }
}

// MARK: - Sub Views

struct InitializingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("초기화 중...")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text("ARKit 권한을 확인하고 있습니다")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct WaitingForSharePlayView: View {
    let onStartSharePlay: () -> Void
    let onSkipSharePlay: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("협업 세션")
                .font(.title)
            
            Text("SharePlay를 통해 다른 사용자와 함께\n동일한 3D 모델을 공유할 수 있습니다")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                Button(action: onStartSharePlay) {
                    HStack {
                        Image(systemName: "shareplay")
                        Text("SharePlay 시작")
                    }
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: onSkipSharePlay) {
                    Text("단독 모드로 시작")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct WaitingForHostView: View {
    let onBecomeHost: () -> Void
    let trackingStatus: TrackingStatus
    
    var body: some View {
        VStack(spacing: 24) {
            // 대기 애니메이션
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.blue, lineWidth: 4)
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: UUID())
                
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)
            }
            
            Text("Host 대기 중")
                .font(.title2)
            
            Text("Host가 마커를 인식하여 위치를 설정할 때까지\n대기하고 있습니다")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 8) {
                Text("직접 Host가 되려면")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: onBecomeHost) {
                    HStack {
                        Image(systemName: "viewfinder")
                        Text("마커 인식 시작")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct HostModeView: View {
    let trackingStatus: TrackingStatus
    
    var body: some View {
        VStack(spacing: 24) {
            // 상태에 따른 아이콘
            statusIcon
            
            Text("마커 인식 모드")
                .font(.title2)
            
            // TrackingStatus 상세 표시
            VStack(spacing: 8) {
                Text(trackingStatus.displayText)
                    .font(.headline)
                    .foregroundColor(statusColor)
                
                statusDescription
            }
            .padding()
            .background(statusColor.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.1))
                .frame(width: 100, height: 100)
            
            Image(systemName: statusIconName)
                .font(.system(size: 40))
                .foregroundColor(statusColor)
        }
    }
    
    private var statusIconName: String {
        switch trackingStatus {
        case .notStarted: return "hourglass"
        case .searching: return "viewfinder"
        case .stabilizing: return "gyroscope"
        case .sampling: return "waveform.path.ecg"
        case .found: return "checkmark.circle"
        case .anchored: return "mappin.and.ellipse"
        case .error: return "exclamationmark.triangle"
        }
    }
    
    private var statusColor: Color {
        switch trackingStatus {
        case .notStarted: return .gray
        case .searching: return .blue
        case .stabilizing: return .orange
        case .sampling: return .blue
        case .found: return .green
        case .anchored: return .green
        case .error: return .red
        }
    }
    
    @ViewBuilder
    private var statusDescription: some View {
        switch trackingStatus {
        case .notStarted:
            Text("이미지 트래킹을 시작하는 중...")
                .font(.caption)
                .foregroundColor(.secondary)
            
        case .searching:
            Text("2D 마커를 카메라에 비춰주세요")
                .font(.caption)
                .foregroundColor(.secondary)
            
        case .stabilizing:
            Text("World Tracking 안정화 대기 중")
                .font(.caption)
                .foregroundColor(.secondary)
            
        case .sampling(let current, let total):
            VStack(spacing: 4) {
                ProgressView(value: Double(current), total: Double(total))
                    .frame(width: 150)
                Text("위치 샘플 수집 중 (\(current)/\(total))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .found:
            Text("위치가 확정되었습니다. 확인을 눌러주세요.")
                .font(.caption)
                .foregroundColor(.secondary)
            
        case .anchored:
            Text("WorldAnchor가 생성되었습니다")
                .font(.caption)
                .foregroundColor(.secondary)
            
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}

struct ViewingModelView: View {
    let anchorsCount: Int
    let userRole: UserRole
    @Environment(ARManager.self) var arManager

    var body: some View {
        VStack(spacing: 16) {
            // Compact header
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "cube.fill")
                        .font(.title3)
                        .foregroundColor(.purple)
                    Text("3D 모델 표시 중")
                        .font(.headline)
                }

                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(anchorsCount)개 활성화")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Control panel section
            if userRole == .host {
                VStack(spacing: 12) {
                    // Color picker
                    ColorPickerGrid(
                        selection: Binding(
                            get: { arManager.selectedTankColor },
                            set: { arManager.selectedTankColor = $0 }
                        ),
                        colors: TankColor.allCases,
                        isEnabled: true
                    )

                    // Options toggles
                    OptionsControlView(
                        options: Binding(
                            get: { arManager.selectedTankOptions },
                            set: { arManager.selectedTankOptions = $0 }
                        ),
                        isEnabled: true
                    )
                }
            } else {
                // Participant view-only mode
                VStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("관람 모드")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
            
            Text("오류 발생")
                .font(.title2)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            
            Button(action: onRetry) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("다시 시도")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

// MARK: - Component Views

struct RoleBadge: View {
    let role: UserRole
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)
            Text(roleText)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .cornerRadius(8)
    }
    
    private var iconName: String {
        switch role {
        case .undetermined: return "questionmark"
        case .host: return "crown.fill"
        case .participant: return "person.fill"
        }
    }
    
    private var roleText: String {
        switch role {
        case .undetermined: return "미정"
        case .host: return "Host"
        case .participant: return "참여자"
        }
    }
    
    private var backgroundColor: Color {
        switch role {
        case .undetermined: return Color.gray.opacity(0.2)
        case .host: return Color.orange.opacity(0.2)
        case .participant: return Color.blue.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch role {
        case .undetermined: return .gray
        case .host: return .orange
        case .participant: return .blue
        }
    }
}

struct ConnectionIndicator: View {
    let isConnected: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(isConnected ? "연결됨" : "연결 끊김")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TrackingStatusIndicator: View {
    let status: TrackingStatus
    
    var body: some View {
        HStack(spacing: 6) {
            // 상태 아이콘
            if status.isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            
            Text(status.displayText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .notStarted: return .gray
        case .searching, .stabilizing, .sampling: return .blue
        case .found, .anchored: return .green
        case .error: return .red
        }
    }
}

struct DebugInfoPanel: View {
    let arManager: ARManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🔧 Debug Info")
                .font(.headline)
            
            Divider()
            
            Group {
                debugRow("App State", "\(arManager.appState)")
                debugRow("Tracking Status", arManager.trackingStatus.displayText)
                debugRow("User Role", "\(arManager.userRole)")
                debugRow("Is Connected", arManager.isConnected ? "Yes" : "No")
                debugRow("World Tracking Stable", arManager.isWorldTrackingStable ? "Yes" : "No")
                debugRow("Samples", "\(arManager.samplingProgress.current)/\(arManager.samplingProgress.total)")
                debugRow("Shared Anchors", "\(arManager.sharedAnchors.count)")
                debugRow("Registered Entities", "\(arManager.anchorEntities.count)")
            }
        }
        .font(.caption.monospaced())
        .padding()
        .background(Color.black.opacity(0.8))
        .foregroundColor(.white)
        .cornerRadius(12)
    }
    
    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.gray)
            Spacer()
            Text(value)
        }
    }
}
