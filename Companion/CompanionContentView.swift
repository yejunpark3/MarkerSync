import SwiftUI
import PeerToPeerMessaging

struct CompanionContentView: View {
    @Environment(PeerMessagingController<Server<TankCommand>>.self) private var serverController
    @Environment(CompanionViewModel.self) private var viewModel
    
    @State private var deviceIdentifierInput: String = ""

    var body: some View {
        NavigationStack {
            VStack {
                switch serverController.connectionState {
                case .stopped, .tlsFailed, .cancelled:
                    setupView
                case .waitingForConnection:
                    waitingView
                case .connecting:
                    connectingView
                case .connected:
                    CompanionControlPanel()
                }
            }
            .navigationTitle("MarkerSync Controller")
        }
        .task {
            for await message in serverController.incomingMessages {
                switch message {
                case .tankEvent(let event):
                    viewModel.handleTankEvent(event)
                case .stateSync(let state):
                    viewModel.handleStateSync(state)
                case .meshListSync(let items):
                    viewModel.handleMeshListSync(items)
                default:
                    break
                }
            }
        }
        .onAppear {
            if let savedID = UserDefaults.standard.string(forKey: "DeviceIdentifier") {
                deviceIdentifierInput = savedID
            }
        }
    }

    private var setupView: some View {
        VStack(spacing: 24) {
            Image(systemName: "ipad.and.iphone")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Connect to Vision Pro")
                .font(.title2)

            TextField("Device Identifier", text: $deviceIdentifierInput)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
                .onChange(of: deviceIdentifierInput) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "DeviceIdentifier")
                }

            Button(action: {
                serverController.start(deviceIdentifier: deviceIdentifierInput)
            }) {
                Text("Start Listening")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(deviceIdentifierInput.isEmpty)

            if serverController.connectionState == .tlsFailed {
                Text("TLS Connection Failed. Ensure certificates match.")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }

    private var waitingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Listening for Vision Pro...")
                .font(.headline)

            Text("Waiting for connection with identifier:\n\(deviceIdentifierInput)")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(role: .cancel, action: {
                serverController.cancel()
            }) {
                Text("Stop")
            }
            .buttonStyle(.bordered)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Connecting...")
                .foregroundColor(.secondary)
        }
    }
}

struct CompanionControlPanel: View {
    @Environment(CompanionViewModel.self) private var viewModel
    @Environment(PeerMessagingController<Server<TankCommand>>.self) private var serverController

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected to Vision Pro")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.top, 8)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Tank Colors")
                        .font(.headline)
                    ColorPickerGrid(
                        selection: Binding(
                            get: { viewModel.color },
                            set: { viewModel.syncColor($0) }
                        ),
                        colors: TankColor.allCases,
                        isEnabled: true
                    )
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Tank Options")
                        .font(.headline)
                    OptionsControlView(
                        options: Binding(
                            get: { viewModel.options },
                            set: { viewModel.syncOptions($0) }
                        ),
                        isEnabled: true
                    )
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Scale")
                        .font(.headline)
                    ScaleControlView(
                        scale: Binding(
                            get: { viewModel.scale },
                            set: { viewModel.syncScale($0) }
                        ),
                        isEnabled: true
                    )
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Rotation")
                        .font(.headline)
                    RotationControlView(
                        rotation: Binding(
                            get: { viewModel.rotation },
                            set: { viewModel.syncRotation($0) }
                        ),
                        isEnabled: true
                    )
                }

                Toggle(isOn: Binding(
                    get: { viewModel.showBillboards },
                    set: { viewModel.syncShowBillboards($0) }
                )) {
                    Label("Show Part Labels", systemImage: "tag.fill")
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Mesh Visibility")
                        .font(.headline)

                    if viewModel.meshItems.isEmpty {
                        Text("No mesh data loaded")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(viewModel.meshItems) { item in
                            Toggle(isOn: Binding(
                                get: { item.isVisible },
                                set: { viewModel.syncMeshVisibility(key: item.entityKey, isVisible: $0) }
                            )) {
                                Text(item.displayName)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Disconnect") {
                    serverController.cancel()
                }
                .foregroundColor(.red)
            }
        }
    }
}
