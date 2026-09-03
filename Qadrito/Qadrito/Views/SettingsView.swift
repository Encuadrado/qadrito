import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PRViewModel
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var notifPrefs: NotificationPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var defaultTab: PRScope = .waitingForMe
    @State private var showingSignOutConfirm = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GitHub Account")
                            .font(.headline)

                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading) {
                                Text(viewModel.currentUsername ?? "Unknown")
                                    .font(.body)
                                Text("Signed in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Sign Out") {
                                showingSignOutConfirm = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default tab")
                            .font(.headline)

                        Picker("Default tab", selection: $defaultTab) {
                            ForEach(PRScope.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Text("Opens to this tab on launch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { preferences.isDoNotDisturb },
                        set: { preferences.setDoNotDisturb($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Do Not Disturb")
                            Text("Silence OS banners; inbox and badge still update")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { preferences.launchAtLogin },
                        set: { preferences.setLaunchAtLogin($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open at Login")
                            Text("Start QAdrito when you sign in to this Mac")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Notifications — Comments") {
                    notifToggle(
                        title: "New comment on my PR",
                        subtitle: "Issue and review comments on PRs you authored",
                        get: { notifPrefs.commentOnMyPR },
                        set: { notifPrefs.setCommentOnMyPR($0) }
                    )
                    notifToggle(
                        title: "New comment in a conversation I'm in",
                        subtitle: "Comments on PRs you commented or reviewed in — not bare review requests",
                        get: { notifPrefs.commentOnParticipating },
                        set: { notifPrefs.setCommentOnParticipating($0) }
                    )
                }

                Section("Notifications — Reviews") {
                    notifToggle(
                        title: "PR reviewed — Approved",
                        subtitle: "Someone approves a PR you authored",
                        get: { notifPrefs.approved },
                        set: { notifPrefs.setApproved($0) }
                    )
                    notifToggle(
                        title: "PR reviewed — Changes requested",
                        subtitle: "Someone requests changes on a PR you authored",
                        get: { notifPrefs.changesRequested },
                        set: { notifPrefs.setChangesRequested($0) }
                    )
                    notifToggle(
                        title: "Review requested / re-requested",
                        subtitle: "One-shot alert when you are newly requested — does not fully watch every review-request PR",
                        get: { notifPrefs.reviewRequested },
                        set: { notifPrefs.setReviewRequested($0) }
                    )
                }

                Section("Notifications — Lifecycle") {
                    notifToggle(
                        title: "PR opened",
                        subtitle: "Someone opens a PR that requests your review",
                        get: { notifPrefs.opened },
                        set: { notifPrefs.setOpened($0) }
                    )
                    notifToggle(
                        title: "PR ready to merge",
                        subtitle: "Your authored PR becomes clean and not draft",
                        get: { notifPrefs.readyToMerge },
                        set: { notifPrefs.setReadyToMerge($0) }
                    )
                    notifToggle(
                        title: "PR merged",
                        subtitle: "A PR you authored or participated in is merged",
                        get: { notifPrefs.merged },
                        set: { notifPrefs.setMerged($0) }
                    )
                    notifToggle(
                        title: "PR closed",
                        subtitle: "A PR you authored or participated in is closed without merge",
                        get: { notifPrefs.closed },
                        set: { notifPrefs.setClosed($0) }
                    )
                }

                Section("Notifications — Status") {
                    notifToggle(
                        title: "Checks failed",
                        subtitle: "CI checks fail on a PR you authored",
                        get: { notifPrefs.checksFailed },
                        set: { notifPrefs.setChecksFailed($0) }
                    )
                    notifToggle(
                        title: "Conflicts",
                        subtitle: "Merge conflicts appear on a PR you authored",
                        get: { notifPrefs.conflicts },
                        set: { notifPrefs.setConflicts($0) }
                    )
                }
            }
            .formStyle(.grouped)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560, height: 640)
        .onAppear {
            defaultTab = viewModel.defaultPRScope
        }
        .alert("Sign Out", isPresented: $showingSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to sign out? You'll need to authenticate again to use QAdrito.")
        }
    }

    private func notifToggle(
        title: String,
        subtitle: String,
        get: @escaping () -> Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: get, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func saveSettings() {
        viewModel.setDefaultPRScope(defaultTab)
        dismiss()
    }
}
