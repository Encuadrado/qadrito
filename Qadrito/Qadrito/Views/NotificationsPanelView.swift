import SwiftUI

struct NotificationsPanelView: View {
    @ObservedObject var store: NotificationStore
    let onClose: () -> Void
    @State private var showingClearAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.items) { item in
                            NotificationRowView(item: item) {
                                store.open(item)
                            } onClear: {
                                store.remove(id: item.id)
                            }
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Clear Notifications", isPresented: $showingClearAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text("This removes all notifications from the inbox. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Notifications")
                .font(.headline)
            Spacer()
            if store.unreadCount > 0 {
                Button("Mark all as read") {
                    store.markAllRead()
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.caption)
            }
            if !store.items.isEmpty {
                Button("Clear all") {
                    showingClearAllConfirm = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .font(.caption)
                .help("Clear all notifications")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No notifications yet")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NotificationRowView: View {
    let item: QAdritoNotification
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .leading) {
                    if item.isUnread {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.accentColor)
                            .frame(width: 3)
                    } else {
                        Color.clear.frame(width: 3)
                    }
                }
                .frame(height: 44)

                Image(systemName: item.systemImageName)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 13, weight: item.isUnread ? .semibold : .regular))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if item.isUnread {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                        }
                    }
                    Text(item.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Text(relativeTime(item.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.85))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(item.isUnread ? Color.accentColor.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Clear", role: .destructive, action: onClear)
        }
    }

    private var iconColor: Color {
        switch item.type {
        case .comment, .reviewComment, .commentOnParticipating: return .blue
        case .changesRequested: return .orange
        case .approved: return .green
        case .checksFailed: return .red
        case .conflicts: return .yellow
        case .readyToMerge: return .green
        case .opened, .reviewRequested: return .purple
        case .merged: return .green
        case .closed: return .secondary
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
