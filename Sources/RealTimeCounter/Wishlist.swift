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

    /// Edits keep `addedAt`, so everything earned since the item was added still counts toward it.
    func update(_ id: UUID, name: String, price: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].name = name
        items[i].price = price
    }

    /// Re-expresses every price in a new currency. Earnings scale by the same rate, so progress is unchanged.
    func convertPrices(by rate: Double) {
        for i in items.indices { items[i].price *= rate }
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
    @State private var editing: UUID?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Wishlist", escapeGoesBack: editing == nil) {
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
                .keyboardShortcut(editing == nil ? .defaultAction : nil)
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
                                Group {
                                    if editing == item.id {
                                        WishEditor(item: item) { newName, newPrice in
                                            wishlist.update(item.id, name: newName, price: newPrice)
                                            editing = nil
                                        } cancel: {
                                            editing = nil
                                        }
                                    } else {
                                        WishRow(item: item, earnings: earnings, currency: currency, now: context.date,
                                                onEdit: { editing = item.id })
                                    }
                                }
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
    var onEdit: (() -> Void)?

    @EnvironmentObject private var wishlist: Wishlist
    @EnvironmentObject private var overtime: Overtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                if !compact && hovering {
                    // Out of the layout until hover, so the price sits flush right; on hover the
                    // price slides over and the actions blur in.
                    HStack(spacing: 2) {
                        Button { onEdit?() } label: {
                            Image(systemName: "pencil").frame(width: 20, height: 20)
                        }
                        .help("Edit")
                        Button { withAnimation(.snappy) { wishlist.remove(item) } } label: {
                            Image(systemName: "trash").frame(width: 20, height: 20)
                        }
                        .help("Remove")
                    }
                    .buttonStyle(SubtleButtonStyle(horizontalPadding: 0))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)           // offered as accessibility actions instead
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                }
            }
            .frame(minHeight: 20)                        // row height doesn't change when actions appear

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
        .onHover { inside in
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.3)) { hovering = inside }
        }
        .onTapGesture(count: 2) { onEdit?() }      // double-click to edit, like renaming in Finder
        .contextMenu {
            if !compact {
                Button("Edit") { onEdit?() }
                Divider()
            }
            Button("Remove", role: .destructive) { withAnimation(.snappy) { wishlist.remove(item) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit") { onEdit?() }
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

/// Inline editor for a wish. Return saves, Esc cancels. Progress is kept because `addedAt` doesn't change.
struct WishEditor: View {
    let item: WishItem
    let save: (String, Double) -> Void
    let cancel: () -> Void

    @State private var name: String
    @State private var price: Double?
    @FocusState private var nameFocused: Bool

    init(item: WishItem, save: @escaping (String, Double) -> Void, cancel: @escaping () -> Void) {
        self.item = item
        self.save = save
        self.cancel = cancel
        _name = State(initialValue: item.name)
        _price = State(initialValue: item.price)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name", text: $name, prompt: Text("Name"))
                    .focused($nameFocused)
                TextField("Price", value: $price, format: .number, prompt: Text("Price"))
                    .frame(width: 76)
                    .multilineTextAlignment(.trailing)
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(commit)

            HStack {
                Text("Progress so far is kept.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .controlSize(.small)
        }
        .onAppear { nameFocused = true }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (price ?? 0) > 0
    }

    private func commit() {
        guard isValid, let price else { return }
        save(name.trimmingCharacters(in: .whitespaces), price)
    }
}
