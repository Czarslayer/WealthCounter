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

    func remove(_ item: WishItem) {
        items.removeAll { $0.id == item.id }
    }

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
    @State private var name = ""
    @State private var price: Double?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: done) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("Wishlist").font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("What do you want?", text: $name)
                    .focused($nameFocused)
                TextField("Price", value: $price, format: .number)
                    .frame(width: 80)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
            }
            .textFieldStyle(.roundedBorder)

            if wishlist.items.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "gift",
                                       description: Text("Add something you want and see how long you need to work for it."))
                    .frame(height: 160)
            } else {
                ScrollView {
                    TimelineView(.animation(minimumInterval: 1.0 / 10)) { context in
                        VStack(spacing: 10) {
                            ForEach(wishlist.items) { item in
                                WishRow(item: item, earnings: earnings, currency: currency, now: context.date)
                            }
                        }
                    }
                }
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .onAppear { nameFocused = true }
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (price ?? 0) > 0
    }

    private func add() {
        guard canAdd, let price else { return }
        withAnimation(.snappy) {
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

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).font(.body.weight(.semibold)).lineLimit(1)
                Spacer()
                if hovering && !compact {
                    Button { withAnimation(.snappy) { wishlist.remove(item) } } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                Text(item.price.money(currency, decimals: 0))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: progress).tint(reached ? .green : .accentColor)

            HStack {
                if reached {
                    Label("You've earned it!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("\(earnings.workTime(for: item.price, at: now)) of work", systemImage: "clock")
                    Spacer()
                    if let eta = earnings.date(whenEarned: item.price - saved, since: now) {
                        Text("Ready \(eta.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !reached && !compact {
                Text("\(saved.money(currency)) earned since added · \(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(11)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove", role: .destructive) { wishlist.remove(item) }
        }
    }
}
