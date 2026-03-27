import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var appState: AppState

    @StateObject private var recorder = AudioRecorder()
    @StateObject private var transcriptionService = TranscriptionService()

    @State private var transcribedText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showShareSheet = false
    @State private var showCopiedToast = false
    @State private var showKeyboardSetup = false
    @State private var keyboardIsEnabled = false
    /// Whether this session was initiated by the keyboard extension via URL scheme.
    @State private var isDictationFromKeyboard = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Model loading status
                    statusBar

                    // Keyboard setup prompt
                    if !keyboardIsEnabled {
                        keyboardSetupBanner
                    }

                    // Scrollable text area
                    ScrollView {
                        VStack(spacing: 24) {
                            transcriptionArea

                            if !transcribedText.isEmpty {
                                actionButtons
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 140)
                    }

                    Spacer(minLength: 0)

                    // Big mic button
                    recordingButton
                        .padding(.bottom, 40)
                }

                // Copied confirmation
                if showCopiedToast {
                    copiedToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Murmur")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(transcriptionService: transcriptionService)
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(text: transcribedText)
            }
        }
        .task {
            await recorder.requestPermission()
            await transcriptionService.loadModel()
            checkKeyboardEnabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkKeyboardEnabled()
        }
        .onChange(of: appState.shouldStartDictation) { shouldStart in
            if shouldStart {
                appState.shouldStartDictation = false
                // Check if this was initiated by the keyboard extension
                isDictationFromKeyboard = SharedDefaults.consumeDictationRequested()
                handleDictationRequest()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: transcribedText.isEmpty)
        .animation(.spring(response: 0.3), value: showCopiedToast)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        Group {
            switch transcriptionService.modelState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(transcriptionService.loadingProgress.isEmpty
                         ? "Loading model..."
                         : transcriptionService.loadingProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)

            case .error(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Transcription Area

    private var transcriptionArea: some View {
        Group {
            if isProcessing || transcriptionService.isTranscribing {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Transcribing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)

            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)

            } else if transcribedText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Tap the mic to start dictating")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)

            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(transcribedText)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                copyToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.primary)

            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.primary)

            Button(role: .destructive) {
                withAnimation {
                    transcribedText = ""
                    errorMessage = nil
                }
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    // MARK: - Recording Button

    private var recordingButton: some View {
        Button {
            handleRecordingTap()
        } label: {
            ZStack {
                // Pulsing rings when recording
                if recorder.isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 3)
                        .frame(width: 88, height: 88)
                        .scaleEffect(1.0 + CGFloat(recorder.audioLevel) * 0.4)
                        .opacity(0.6)
                        .animation(.easeInOut(duration: 0.15), value: recorder.audioLevel)

                    Circle()
                        .stroke(Color.red.opacity(0.15), lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .scaleEffect(1.0 + CGFloat(recorder.audioLevel) * 0.6)
                        .opacity(0.4)
                        .animation(.easeInOut(duration: 0.2), value: recorder.audioLevel)
                }

                // Main circle
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 72, height: 72)
                    .shadow(
                        color: (recorder.isRecording ? Color.red : Color.accentColor).opacity(0.3),
                        radius: 8, y: 4
                    )

                // Mic / stop icon
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .disabled(!recorder.hasPermission || transcriptionService.modelState != .loaded || isProcessing)
        .opacity(
            (!recorder.hasPermission || transcriptionService.modelState != .loaded || isProcessing)
                ? 0.5 : 1.0
        )
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Copied Toast

    private var copiedToast: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Copied to clipboard")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.top, 60)

            Spacer()
        }
    }

    // MARK: - Keyboard Setup Banner

    private var keyboardSetupBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Murmur Keyboard")
                        .font(.subheadline.weight(.semibold))
                    Text("Add Murmur as a keyboard to dictate in any app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button {
                openKeyboardSettings()
            } label: {
                Text("Open Keyboard Settings")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// Checks whether the Murmur keyboard extension is currently enabled.
    private func checkKeyboardEnabled() {
        // UITextInputMode.activeInputModes lists all enabled keyboards.
        // If our keyboard bundle ID appears, it's enabled.
        let enabled = UITextInputMode.activeInputModes.contains { mode in
            mode.value(forKey: "identifier") as? String == "com.murmurkeyboard.app.keyboard"
        }
        withAnimation {
            keyboardIsEnabled = enabled
        }
    }

    /// Opens iOS Settings to the keyboard management page.
    private func openKeyboardSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Actions

    private func handleRecordingTap() {
        if recorder.isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    /// Called when the app receives a murmur://dictate URL scheme request.
    /// Waits for the model to be ready, then auto-starts recording.
    private func handleDictationRequest() {
        Task {
            // Wait for model to finish loading if needed (up to 30 seconds)
            for _ in 0..<60 {
                if transcriptionService.modelState == .loaded && recorder.hasPermission {
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }

            guard transcriptionService.modelState == .loaded, recorder.hasPermission else {
                errorMessage = "Cannot start dictation: model not loaded or no mic permission."
                return
            }

            startRecording()
        }
    }

    private func startRecording() {
        errorMessage = nil
        do {
            try recorder.startRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAndTranscribe() {
        guard let audioURL = recorder.stopRecording() else {
            errorMessage = "No audio was recorded."
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let rawText = try await transcriptionService.transcribe(audioURL: audioURL)
                let cleanedText = TextProcessor.process(rawText)

                withAnimation {
                    if transcribedText.isEmpty {
                        transcribedText = cleanedText
                    } else {
                        transcribedText += " " + cleanedText
                    }
                }

                // If this transcription was initiated by the keyboard extension,
                // save the result to shared storage so the keyboard can insert it.
                if isDictationFromKeyboard && !cleanedText.isEmpty {
                    SharedDefaults.setPendingText(cleanedText)
                    isDictationFromKeyboard = false
                    // Small delay so the user can see the result, then return
                    try? await Task.sleep(for: .milliseconds(800))
                    // Note: There's no reliable API to "return to previous app" from
                    // a main app. The user will need to manually switch back.
                    // On iOS 17+, we could potentially use openURL with the source app's
                    // URL scheme, but keyboard extensions don't have their own scheme.
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            isProcessing = false
            recorder.cleanupRecording()
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = transcribedText
        showCopiedToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopiedToast = false
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var transcriptionService: TranscriptionService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Model", selection: $transcriptionService.selectedModel) {
                        ForEach(WhisperModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Whisper Model")
                } footer: {
                    Text("Tiny is fastest with slightly lower accuracy. Base is more accurate but uses more memory.")
                }

                Section {
                    Button("Reload Model") {
                        Task {
                            await transcriptionService.unloadModel()
                            await transcriptionService.loadModel()
                            dismiss()
                        }
                    }
                    .disabled(transcriptionService.modelState == .loading)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Murmur v1.0")
                            .font(.headline)
                        Text("On-device speech-to-text powered by WhisperKit.\nNo data leaves your device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
