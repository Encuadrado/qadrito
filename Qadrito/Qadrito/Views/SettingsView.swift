import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PRViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var organization: String = "Encuadrado"
    @State private var slackMapJSON: String = ""
    @State private var showingSlackMapError = false
    @State private var slackMapErrorMessage = ""
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
                        Text("Organization")
                            .font(.headline)
                        
                        TextField("Encuadrado", text: $organization)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Slack User Map (Optional)")
                            .font(.headline)
                        
                        Text("JSON mapping GitHub login to Slack info:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $slackMapJSON)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100)
                            .border(Color.secondary.opacity(0.3), width: 1)
                        
                        Text(#"Example: {"cnovoab": {"slackUserId": "U123", "slackName": "Claudio"}}"#)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            
            if showingSlackMapError {
                Text(slackMapErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
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
                .disabled(organization.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600, height: 500)
        .onAppear {
            loadCurrentSettings()
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
    
    private func loadCurrentSettings() {
        if let org = UserDefaults.standard.string(forKey: "organization") {
            organization = org
        }
        
        if let slackMapData = UserDefaults.standard.data(forKey: "slackMap"),
           let slackMap = try? JSONDecoder().decode([String: SlackUser].self, from: slackMapData) {
            if let jsonData = try? JSONEncoder().encode(slackMap),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                slackMapJSON = jsonString
            }
        }
    }
    
    private func saveSettings() {
        var settings = AppSettings()
        settings.githubLogin = viewModel.currentUsername ?? ""
        settings.organization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !slackMapJSON.isEmpty {
            if let jsonData = slackMapJSON.data(using: .utf8),
               let slackMap = try? JSONDecoder().decode([String: SlackUser].self, from: jsonData) {
                settings.slackMap = slackMap
                showingSlackMapError = false
            } else {
                showingSlackMapError = true
                slackMapErrorMessage = "Invalid JSON format for Slack map"
                return
            }
        }
        
        viewModel.updateSettings(settings)
        dismiss()
    }
}
