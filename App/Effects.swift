import BedtimeCore
import SwiftUI

// Dramatic presentation: stamps, shakes, flashes, confetti, chat threads and the
// panic countdown. Everything respects Reduce Motion: no movement, just fades.

/// A verdict slammed onto an outcome ("BOUNDARY: HELD").
struct StampView: View {
    let text: String
    var color: Color = .red
    var delay: Double = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        Text(text)
            .font(.system(.title2, design: .rounded).weight(.black))
            .tracking(1.2)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color, lineWidth: 4))
            .foregroundStyle(color)
            .rotationEffect(.degrees(-7))
            .scaleEffect(landed || reduceMotion ? 1 : 2.8)
            .opacity(landed ? 0.92 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.5).delay(delay)) { landed = true }
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: landed)
            .accessibilityLabel("Verdict: \(text)")
    }
}

/// What the screen does for an outcome. Triggers are counters: bump one to fire.
struct ScreenFX: Equatable {
    var shakes = 0
    var flashes = 0
    var confetti = 0
}

/// Shake and red flash for whatever it's applied to (the play area).
struct ScreenFXModifier: ViewModifier {
    let fx: ScreenFX
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat(0), trigger: fx.shakes) { view, offset in
                view.offset(x: reduceMotion ? 0 : offset)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-16, duration: 0.05)
                    LinearKeyframe(14, duration: 0.07)
                    LinearKeyframe(-11, duration: 0.07)
                    LinearKeyframe(8, duration: 0.07)
                    LinearKeyframe(-4, duration: 0.07)
                    SpringKeyframe(0, duration: 0.2)
                }
            }
            .overlay {
                Color.clear
                    .keyframeAnimator(initialValue: 0.0, trigger: fx.flashes) { view, opacity in
                        view.background(Color.red.opacity(opacity))
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0.45, duration: 0.06)
                            CubicKeyframe(0.0, duration: 0.75)
                        }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .overlay {
                if fx.confetti > 0, !reduceMotion {
                    ConfettiView().id(fx.confetti).ignoresSafeArea()
                }
            }
            .sensoryFeedback(.error, trigger: fx.shakes)
            .sensoryFeedback(.warning, trigger: fx.flashes)
            .sensoryFeedback(.success, trigger: fx.confetti)
    }
}

extension View {
    func screenFX(_ fx: ScreenFX) -> some View { modifier(ScreenFXModifier(fx: fx)) }
}

/// About 70 pieces of falling confetti. Each appearance is a new burst.
struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id = UUID()
        let x = CGFloat.random(in: 0...1)
        let drift = CGFloat.random(in: -60...60)
        let delay = Double.random(in: 0...0.35)
        let duration = Double.random(in: 1.3...2.3)
        let size = CGFloat.random(in: 7...12)
        let spin = Double.random(in: 240...900)
        let color = [Color.pink, .orange, .yellow, .mint, .indigo, .teal, .red].randomElement() ?? .pink
    }

    @State private var pieces: [Piece] = (0..<70).map { _ in Piece() }
    @State private var falling = false

    var body: some View {
        GeometryReader { proxy in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * 0.45)
                    .rotationEffect(.degrees(falling ? piece.spin : 0))
                    .position(x: piece.x * proxy.size.width + (falling ? piece.drift : 0),
                              y: falling ? proxy.size.height + 40 : -30)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: falling)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { DispatchQueue.main.async { falling = true } }
    }
}

/// A text thread, revealed one bubble at a time with a typing indicator.
/// Names are already filled in by the caller.
struct ChatThread: View {
    struct Line: Equatable {
        var from: String
        var text: String
        var mine: Bool
    }

    let title: String?
    let lines: [Line]
    var animated = true
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var typing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.accentColor.gradient)
                        .frame(width: 26, height: 26)
                        .overlay(Text(String(title.prefix(1))).font(.caption.bold()).foregroundStyle(.white))
                    Text(title).font(.subheadline.weight(.semibold))
                }
                .padding(.bottom, 4)
                .accessibilityElement(children: .combine)
            }
            ForEach(Array(lines.prefix(shown).enumerated()), id: \.offset) { index, line in
                let showSender = !line.mine && title != nil && line.from != title
                    && (index == 0 || lines[index - 1].from != line.from)
                ChatBubble(line: line, showSender: showSender)
                    .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: line.mine ? .bottomTrailing : .bottomLeading)
                                                .combined(with: .opacity),
                                            removal: .opacity))
            }
            if typing, shown < lines.count {
                TypingDots(mine: lines[shown].mine)
                    .transition(.opacity)
            }
        }
        .task(id: lines) { @MainActor in
            await reveal()
        }
    }

    @MainActor
    private func reveal() async {
        guard animated, !reduceMotion else {
            shown = lines.count
            onFinished()
            return
        }
        shown = 0
        for line in lines {
            withAnimation(.easeOut(duration: 0.15)) { typing = true }
            let pause = min(1.1, 0.35 + Double(line.text.count) * 0.012)
            try? await Task.sleep(for: .seconds(pause))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                typing = false
                shown += 1
            }
            try? await Task.sleep(for: .seconds(0.18))
        }
        onFinished()
    }
}

struct ChatBubble: View {
    let line: ChatThread.Line
    var showSender = false

    var body: some View {
        HStack {
            if line.mine { Spacer(minLength: 48) }
            VStack(alignment: line.mine ? .trailing : .leading, spacing: 2) {
                if showSender {
                    Text(line.from).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 10)
                }
                Text(line.text)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(line.mine ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    )
                    .foregroundStyle(line.mine ? Color.white : Color.primary)
            }
            if !line.mine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.mine ? "You" : line.from): \(line.text)")
    }
}

/// The three-dot "typing..." bubble.
struct TypingDots: View {
    var mine = false

    var body: some View {
        HStack {
            if mine { Spacer() }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .frame(width: 7, height: 7)
                        .phaseAnimator([0.3, 1.0]) { dot, phase in
                            dot.opacity(phase)
                        } animation: { _ in
                            .easeInOut(duration: 0.4).delay(Double(i) * 0.13)
                        }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
            if !mine { Spacer() }
        }
        .accessibilityLabel("Typing")
    }
}

/// The panic countdown: a draining bar that turns red and pulses at the end.
struct CountdownBar: View {
    /// 1 at the start, 0 when time is up.
    let fraction: Double
    let secondsLeft: Int

    var body: some View {
        let urgent = secondsLeft <= 2
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DECIDE")
                    .font(.caption.weight(.black))
                    .tracking(2)
                Spacer()
                Text("\(secondsLeft)")
                    .font(.title3.weight(.black).monospacedDigit())
                    .contentTransition(.numericText())
                    .scaleEffect(urgent ? 1.25 : 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.4), value: secondsLeft)
            }
            .foregroundStyle(urgent ? Color.red : Color.orange)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(urgent ? Color.red : Color.orange)
                        .frame(width: max(0, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(secondsLeft) seconds to decide")
    }
}
