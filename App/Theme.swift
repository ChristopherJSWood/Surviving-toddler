import BedtimeCore
import SwiftUI

extension Meter {
    var symbol: String {
        switch self {
        case .energy: return "bolt.fill"
        case .rel: return "heart.fill"
        case .mood: return "face.smiling"
        case .sleepy: return "moon.zzz.fill"
        case .debt: return "bed.double.fill"
        case .home: return "house.fill"
        case .rep: return "bubble.left.and.bubble.right.fill"
        }
    }

    var tint: Color {
        switch self {
        case .energy: return .orange
        case .rel: return .pink
        case .mood: return .yellow
        case .sleepy: return .indigo
        case .debt: return .purple
        case .home: return .teal
        case .rep: return .mint
        }
    }

    /// Whether a rise is good news. Sleepiness is neither (you want it high at
    /// bedtime, but overtired is miserable); sleep debt rising is bad.
    var higherIsBetter: Bool? {
        switch self {
        case .sleepy: return nil
        case .debt: return false
        default: return true
        }
    }

    /// At or below this the bar turns red (nil: never).
    var dangerAt: Int? {
        switch self {
        case .energy, .rel, .home, .rep: return 20
        case .mood: return 10
        case .sleepy, .debt: return nil
        }
    }
}

/// Large, tappable, multi-line choice buttons. Locked choices stay visible.
struct ChoiceButtonStyle: ButtonStyle {
    var locked = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(locked ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(configuration.isPressed ? 0.28 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(locked ? Color.secondary.opacity(0.4) : Color.accentColor.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: locked ? [5, 4] : []))
            )
            .foregroundStyle(locked ? Color.secondary : Color.primary)
            .scaleEffect(configuration.isPressed && !locked ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The rounded card every screen's main content sits on.
struct Card<Content: View>: View {
    var border: Color?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(border ?? .clear, lineWidth: 2)
            )
    }
}

extension GameContent {
    /// Small label above a card's title, or nil for ordinary cards.
    func eyebrow(for event: GameEvent) -> (text: String, color: Color)? {
        if event.phase == .night { return ("2 AM", .indigo) }
        if event.hazard == .catastrophe { return ("Catastrophe", .red) }
        if event.hazard == .sting { return ("Hazard", .red) }
        if event.moment { return ("Small moment", .pink) }
        if events.contains(where: { $0.tell == event.id }) { return ("Warning", .orange) }
        if tasks.contains(where: { $0.expire == event.id }) { return ("From your list", .orange) }
        if event.forced, !event.endsWeek { return ("Payback", .orange) }
        return nil
    }
}
