import SwiftUI

struct WishItem: Codable, Identifiable {
    var id = UUID()
    var name: String
    var price: Double
    var addedAt = Date()
}

final class Wishlist: ObservableObject {
    @Published var items: [WishItem] { didSet { save() } }
    private let key = "wishlist"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([WishItem].self, from: data) {
            items = saved
        } else {
            items = []
        }
    }

    func add(name: String, price: Double) {
        items.append(WishItem(name: name, price: price))
    }

    /// The most recent removal, kept until it's undone or replaced so people can recover from mistakes.
    @Published private(set) var lastRemoved: (item: WishItem, index: Int)?

    func remove(_ item: WishItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        lastRemoved = (item, index)
    }

    func undoRemove() {
        guard let (item, index) = lastRemoved else { return }
        items.insert(item, at: min(index, items.count))
        lastRemoved = nil
    }

    func clearUndo() { lastRemoved = nil }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Views

struct WishlistView: View {
    let earnings: Earnings
    let currency: String
    let done: () -> Void

    @EnvironmentObject private var wishlist: Wishlist
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var price: Double?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Wishlist") {
                wishlist.clearUndo()
                done()
            }
            .padding(.horizontal, -4)

            HStack(spacing: 8) {
                TextField("Name", text: $name, prompt: Text("Something you want"))
                    .focused($nameFocused)
                TextField("Price", value: $price, format: .number, prompt: Text("Price"))
                    .frame(width: 76)
                    .multilineTextAlignment(.trailing)
                Button(action: add) {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
                .help("Add to Wishlist")
                .accessibilityLabel("Add to Wishlist")
            }
            .textFieldStyle(.roundedBorder)

            if wishlist.items.isEmpty {
                ContentUnavailableView {
                    Label("No Wishes Yet", systemImage: "gift")
                } description: {
                    Text("Add something you want to see how much work it costs and the day you'll have earned it.")
                }
                .frame(height: 170)
            } else {
                ScrollView {
                    TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 10)) { context in
                        LazyVStack(spacing: 0) {
                            ForEach(Array(wishlist.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider() }
                                WishRow(item: item, earnings: earnings, currency: currency, now: context.date)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let removed = wishlist.lastRemoved {
                HStack {
                    Text("Removed \u{201C}\(removed.item.name)\u{201D}")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") { withAnimation(.snappy) { wishlist.undoRemove() } }
                        .keyboardShortcut("z")
                    Button {
                        withAnimation(.snappy) { wishlist.clearUndo() }
                    } label: {
                        Image(systemName: "xmark").frame(width: 20, height: 20)
                    }
                    .buttonStyle(SubtleButtonStyle(horizontalPadding: 0))
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
                }
                .font(.subheadline)
                .padding(.leading, 10)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity)
            }
        }
        .padding(16)
        .onAppear { nameFocused = true }
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (price ?? 0) > 0
    }

    private func add() {
        guard canAdd, let price else { return }
        withAnimation(.snappy) {
            wishlist.clearUndo()
            wishlist.add(name: name.trimmingCharacters(in: .whitespaces), price: price)
        }
        name = ""
        self.price = nil
        nameFocused = true
    }
}

struct WishRow: View {
    let item: WishItem
    let earnings: Earnings
    let currency: String
    let now: Date
    var compact = false

    @EnvironmentObject private var wishlist: Wishlist
    @EnvironmentObject private var overtime: Overtime
    @State private var hovering = false

    var body: some View {
        let earnedSince = earnings.earned(from: item.addedAt, to: now)
            + overtime.earned(from: item.addedAt, to: now, earnings: earnings)
        let saved = min(earnedSince, item.price)
        let progress = item.price > 0 ? saved / item.price : 1
        let reached = progress >= 1

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.name).fontWeight(.medium).lineLimit(1)
                Spacer()
                Text(item.price.money(currency, decimals: 0))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if !compact {
                    Button { withAnimation(.snappy) { wishlist.remove(item) } } label: {
                        Image(systemName: "trash").frame(width: 20, height: 20)
                    }
                    .buttonStyle(SubtleButtonStyle(horizontalPadding: 0))
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0)          // reserved space, so nothing shifts on hover
                    .allowsHitTesting(hovering)
                    .help("Remove")
                    .accessibilityHidden(true)           // offered as an accessibility action instead
                }
            }

            ProgressView(value: progress)
                .controlSize(.small)
                .tint(reached ? .green : .accentColor)

            HStack(spacing: 4) {
                if reached {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Earned").foregroundStyle(.primary)
                } else {
                    Text("\(earnings.workTime(for: item.price - saved, at: now)) to go")
                    Spacer()
                    if let eta = earnings.date(whenEarned: item.price - saved, since: now) {
                        Text(readyText(eta))
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove", role: .destructive) { withAnimation(.snappy) { wishlist.remove(item) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Remove") { wishlist.remove(item) }
    }

    /// "Ready today at 16:20", "Ready Fri 3 Oct", or "Ready Nov 2027" once it's not this year.
    private func readyText(_ eta: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(eta, inSameDayAs: now) {
            return "Ready today at \(eta.formatted(date: .omitted, time: .shortened))"
        }
        if cal.component(.year, from: eta) == cal.component(.year, from: now) {
            return "Ready \(eta.formatted(.dateTime.weekday(.abbreviated).day().month()))"
        }
        return "Ready \(eta.formatted(.dateTime.month(.abbreviated).year()))"
    }
}
