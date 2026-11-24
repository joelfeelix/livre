import WidgetKit
import SwiftUI

private let appGroup = "group.com.livreapp.livre"
private let dayMs = 86_400_000.0

/// Dados enviados pelo app (ver syncWidget() no index.html).
struct WidgetData: Decodable {
    var name: String
    var emoji: String
    var start: Double          // ms desde 1970; 0 = nenhum vício cadastrado
    var affirmations: [String]
    var day0: Double           // meia-noite do dia em que os dados foram gerados (ms)

    static func load() -> WidgetData? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "widget") else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    func affirmation(on date: Date) -> String {
        guard !affirmations.isEmpty else { return "Eu sou livre." }
        let i = Int(floor((date.timeIntervalSince1970 * 1000 - day0) / dayMs))
        return affirmations[max(0, min(i, affirmations.count - 1))]
    }
}

struct LivreEntry: TimelineEntry {
    let date: Date
    let name: String
    let emoji: String
    let days: Int?
    let affirmation: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> LivreEntry {
        LivreEntry(date: .now, name: "Cigarro", emoji: "🚬", days: 12, affirmation: "Eu sou livre. Nenhum vício decide por mim.")
    }

    func getSnapshot(in context: Context, completion: @escaping (LivreEntry) -> Void) {
        completion(entry(at: .now, data: WidgetData.load()) ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LivreEntry>) -> Void) {
        let data = WidgetData.load()
        var dates: Set<Date> = [.now]
        let cal = Calendar.current
        // troca de afirmação à meia-noite
        for i in 1...7 { if let d = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: .now)) { dates.insert(d) } }
        // troca do número de dias no "aniversário" da hora em que parou
        if let d = data, d.start > 0 {
            let start = Date(timeIntervalSince1970: d.start / 1000)
            let done = Int(Date.now.timeIntervalSince(start) / 86_400)
            for i in 1...7 { dates.insert(start.addingTimeInterval(Double(done + i) * 86_400)) }
        }
        let entries = dates.sorted().prefix(15).compactMap { entry(at: $0, data: data) }
        let fallback = LivreEntry(date: .now, name: "", emoji: "🕊️", days: nil, affirmation: "Abra o Livre para começar.")
        completion(Timeline(entries: entries.isEmpty ? [fallback] : entries, policy: .atEnd))
    }

    private func entry(at date: Date, data: WidgetData?) -> LivreEntry? {
        guard let d = data else { return nil }
        let days: Int? = d.start > 0 ? max(0, Int((date.timeIntervalSince1970 * 1000 - d.start) / dayMs)) : nil
        return LivreEntry(date: date, name: d.name, emoji: d.emoji, days: days, affirmation: d.affirmation(on: date))
    }
}

// MARK: - Visual

private let bgGradient = LinearGradient(
    colors: [Color(red: 0.13, green: 0.47, blue: 0.47), Color(red: 0.07, green: 0.12, blue: 0.22)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

private extension View {
    @ViewBuilder func widgetBackground<B: View>(_ bg: B) -> some View {
        if #available(iOS 17.0, *) { containerBackground(for: .widget) { bg } } else { background(bg) }
    }
}

struct CounterView: View {
    @Environment(\.widgetFamily) var family
    let entry: LivreEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text(entry.days.map(String.init) ?? "–").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("dias").font(.system(size: 10))
                }
            }
            .widgetBackground(Color.clear)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.emoji) Livre há \(entry.days ?? 0) \(entry.days == 1 ? "dia" : "dias")").font(.headline)
                Text(entry.affirmation).font(.caption).lineLimit(2)
            }
            .widgetBackground(Color.clear)
        case .systemMedium:
            HStack(spacing: 16) {
                counter
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
                Text(entry.affirmation)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .widgetBackground(bgGradient)
        default:
            counter.widgetBackground(bgGradient)
        }
    }

    private var counter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.emoji) \(entry.name)")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            Spacer(minLength: 0)
            Text(entry.days.map(String.init) ?? "–")
                .font(.system(size: 48, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(entry.days == 1 ? "dia livre" : "dias livre")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.31, green: 0.82, blue: 0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AffirmationView: View {
    @Environment(\.widgetFamily) var family
    let entry: LivreEntry

    var body: some View {
        if family == .accessoryRectangular {
            Text(entry.affirmation).font(.system(size: 14, weight: .semibold, design: .serif)).lineLimit(3)
                .widgetBackground(Color.clear)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("✨ AFIRMAÇÃO DO DIA").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                Text(entry.affirmation)
                    .font(.system(size: family == .systemSmall ? 17 : 22, weight: .semibold, design: .serif))
                    .foregroundStyle(.white).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetBackground(LinearGradient(
                colors: [Color(red: 0.24, green: 0.2, blue: 0.4), Color(red: 0.08, green: 0.12, blue: 0.19)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

struct CounterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LivreCounter", provider: Provider()) { CounterView(entry: $0) }
            .configurationDisplayName("Contador")
            .description("Quantos dias você está livre, com a afirmação do dia.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct AffirmationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LivreAffirmation", provider: Provider()) { AffirmationView(entry: $0) }
            .configurationDisplayName("Afirmação do dia")
            .description("Uma afirmação nova todo dia na sua tela.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct LivreWidgets: WidgetBundle {
    var body: some Widget {
        CounterWidget()
        AffirmationWidget()
    }
}
