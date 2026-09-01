import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PRViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var githubPAT: String = ""
    @State private var githubLogin: String = ""
    @State private var organization: String = "Encuadrado"
    @State private var slackMapJSON: String = ""
    @State private var showingSlackMapError = false
    @State private var slackMapErrorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GitHub Personal Access Token")
                            .font(.headline)
                        
                        SecureField("ghp_xxxxxxxxxxxx", text: $githubPAT)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Required scopes: repo, read:org")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GitHub Login")
                            .font(.headline)
                        
                        TextField("Your GitHub username", text: $githubLogin)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
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
                .disabled(githubPAT.isEmpty || githubLogin.isEmpty || organization.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600, height: 600)
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    private func loadCurrentSettings() {
        if let pat = KeychainManager.shared.load(key: "githubPAT") {
            githubPAT = pat
        }
        
        if let login = UserDefaults.standard.string(forKey: "githubLogin") {
            githubLogin = login
        }
        
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
        settings.githubPAT = githubPAT.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.githubLogin = githubLogin.trimmingCharacters(in: .whitespacesAndNewlines)
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
