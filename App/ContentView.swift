import SwiftUI

struct ContentView: View {
    @ObservedObject var dictation: DictationService
    @State private var isUserScrolledUp = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch viewState {
            case .loading:
                loadingView
                    .transition(.opacity)
            case .idle:
                idleView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            case .recording:
                recordingView
                    .transition(.opacity)
            case .done:
                // Brief flash before auto-return -- shows recording view
                // with a checkmark overlay, then resets to idle
                recordingView
                    .overlay(doneOverlay)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewState)
        .onAppear {
            dictation.setupBackgroundAudio()
            dictation.listenForKeyboardCommands()
        }
        .onChange(of: viewState) { _, newState in
            if newState == .done {
                autoReturnToKeyboard()
            }
        }
    }

    // MARK: - View States

    private enum ViewState: Equatable {
        case loading
        case idle
        case recording
        case done
    }

    private var viewState: ViewState {
        if !dictation.isModelReady { return .loading }
        switch dictation.status {
        case .idle:           return .idle
        case .recording:      return .recording
        case .transcribing:   return .recording
        case .ready:          return .done
        case .error:          return .idle
        }
    }

    // MARK: - Auto-return

    /// After dictation completes, reset to idle after a brief delay.
    /// The keyboard extension polls for the transcription and inserts it.
    /// Keeping the app on "Done" is a dead end -- reset so next launch is ready.
    private func autoReturnToKeyboard() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                dictation.resetToIdle()
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading model...")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(dictation.modelStatus)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 40) {
            Spacer()

            Button(action: { dictation.startRecording() }) {
                VStack(spacing: 16) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(.blue)
                    Text("Tap to dictate")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 0) {
            // Status bar: recording indicator
            recordingStatusBar
                .padding(.horizontal)
                .padding(.top, 8)

            // Text area -- dominant element, fills available space
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Confirmed text: stable, high contrast, large
                        if !dictation.confirmedText.isEmpty {
                            Text(dictation.confirmedText)
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Visual separator between stable and volatile zones
                        if !dictation.confirmedText.isEmpty
                            && (!dictation.unconfirmedText.isEmpty || !dictation.currentText.isEmpty) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                                .padding(.vertical, 8)
                        }

                        // Volatile zone: unconfirmed + current hypothesis
                        volatileText
                            .font(.title2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(20)
                }
                .onChange(of: dictation.confirmedText) { _, _ in
                    scrollToBottomIfNeeded(proxy: proxy)
                }
                .onChange(of: dictation.currentText) { _, _ in
                    scrollToBottomIfNeeded(proxy: proxy)
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Stop button
            Button(action: { dictation.stopRecording() }) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                    Text("Done")
                        .font(.title3.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 48)
                .padding(.vertical, 14)
                .background(Color.red)
                .clipShape(Capsule())
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    /// Recording status bar with pulsing red dot and "Recording" label
    private var recordingStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .modifier(PulsingModifier())

            Text("Recording")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)

            Spacer()
        }
    }

    /// Unconfirmed + current text in the volatile zone.
    /// Uses distinct styling so the user learns this region changes.
    private var volatileText: some View {
        let hasUnconfirmed = !dictation.unconfirmedText.isEmpty
        let hasCurrent = !dictation.currentText.isEmpty
        let hasConfirmed = !dictation.confirmedText.isEmpty

        if !hasUnconfirmed && !hasCurrent && !hasConfirmed {
            return Text("Listening...")
                .foregroundStyle(.secondary)
                .italic()
        }

        var result = Text("")
        if hasUnconfirmed {
            result = result + Text(dictation.unconfirmedText)
                .foregroundStyle(.secondary)
        }
        if hasCurrent {
            let separator = hasUnconfirmed ? " " : ""
            result = result
                + Text(separator)
                + Text(dictation.currentText)
                .foregroundStyle(.secondary.opacity(0.6))
                .italic()
        }
        return result
    }

    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy) {
        // Always auto-scroll. A future improvement could track whether
        // the user has manually scrolled up and pause auto-scroll.
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: - Done Overlay

    /// Brief confirmation overlay shown for ~1 second before auto-return to idle
    private var doneOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                Spacer()
            }
            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Pulsing Animation Modifier

private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

#Preview {
    ContentView(dictation: DictationService())
}
