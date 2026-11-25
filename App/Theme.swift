import BedtimeCore
import SwiftUI
import UIKit

extension Meter {
    var symbol: String {
        switch self {
        case .energy: return "bolt.fill"
        case .rel: return "heart.fill"
        case .mood: return "face.smiling"
        case .sleepy: return "moon.zzz.fill"
        case .debt: return "bed.double.fill"
        }
    }

    var tint: Color {
        switch self {
        case .energy: return .orange
        case .rel: return .pink
        case .mood: return .yellow
        case .sleepy: return .indigo
        case .debt: return .purple
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
        case .energy, .rel: return 20
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

/// Today's sleepiness as a word: bedtime is a goal you time, not a meter.
enum BedtimeReadiness {
    case wired, drowsy, ready, overtired

    init(sleepy: Int, bar: Int) {
        if sleepy >= 80 { self = .overtired }
        else if sleepy >= bar { self = .ready }
        else if sleepy >= bar - 20 { self = .drowsy }
        else { self = .wired }
    }

    var label: String {
        switch self {
        case .wired: return "Wired"
        case .drowsy: return "Drowsy"
        case .ready: return "Ready for bed"
        case .overtired: return "Overtired"
        }
    }

    var tint: Color {
        switch self {
        case .wired: return .orange
        case .drowsy: return .indigo
        case .ready: return .green
        case .overtired: return .red
        }
    }

    var symbol: String {
        switch self {
        case .wired: return "bolt.horizontal.fill"
        case .drowsy: return "moon.fill"
        case .ready: return "moon.zzz.fill"
        case .overtired: return "exclamationmark.triangle.fill"
        }
    }
}

extension GameContent {
    /// Tonight's bedtime bar: Friday's date night asks for more (read from the
    /// date_check card's failure check), other nights use config.bedtime.
    func bedtimeBar(day: Int) -> Int {
        if day == days.count - 1,
           let check = events.first(where: { $0.id == "date_check" })?.checks
               .compactMap({ $0.condition?.maximum["sleepy"] }).first {
            return check + 1
        }
        return config.bedtime.threshold
    }
}
