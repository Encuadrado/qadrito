import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PRViewModel
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    
    @State private var defaultTab: PRScope = .waitingForMe
    @State private var showingSignOutConfirm = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
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
                            Text("Silence notifications and dock badge updates")
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
            }
            .formStyle(.grouped)
            
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
        .frame(width: 520, height: 420)
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
    
    private func saveSettings() {
        viewModel.setDefaultPRScope(defaultTab)
        dismiss()
    }
}
