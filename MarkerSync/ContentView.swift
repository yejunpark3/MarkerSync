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

    var body: some View {
        VStack(spacing: 24) {
            switch arManager.appState {
            case .initializing:
                ProgressView("초기화 중...")

            case .waitingForSharePlay:
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    Text("SharePlay 세션을 시작하거나 참가하세요")
                        .font(.title2)
                    Button("SharePlay 시작") {
                        Task {
                            try await arManager.startSharePlay()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .waitingForHost:
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Host가 위치를 설정할 때까지 대기 중...")
                        .font(.title3)
                    Text("또는 직접 Host가 되려면 마커를 인식하세요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("마커 인식 시작 (Host 되기)") {
                        Task {
                            arManager.userRole = .host
                            await openImmersiveSpace(id: "tracking")
                        }
                    }
                    .buttonStyle(.bordered)
                }

            case .hostMode:
                VStack(spacing: 16) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("마커 인식 모드 활성화됨")
                        .font(.title2)
                    Text("2D 마커를 카메라로 비추세요")
                        .foregroundColor(.secondary)
                }

            case .viewingModel:
                VStack(spacing: 16) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    Text("3D 모델 표시 중")
                        .font(.title2)
                }

            case .error(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("오류 발생")
                        .font(.title2)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("다시 시도") {
                        Task {
                            await arManager.retry()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(40)
        .task {
            await arManager.initialize()
        }
        .onChange(of: arManager.sharedAnchors.count) { oldCount, newCount in
            if newCount > 0 && arManager.userRole == .participant {
                Task { @MainActor in
                    await openImmersiveSpace(id: "model")
                    arManager.appState = .viewingModel
                }
            }
        }
        .onChange(of: arManager.isConnected) { _, isConnected in
            if !isConnected && arManager.appState == .viewingModel {
                Task { @MainActor in
                    arManager.appState = .error("연결이 끊어졌습니다")
                }
            }
        }
    }
}
