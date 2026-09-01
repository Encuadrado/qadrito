import SwiftUI

struct AuthenticationView: View {
    @ObservedObject var viewModel: PRViewModel
    @Binding var isPresented: Bool
    @State private var isAuthenticating = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Sign in with GitHub")
                .font(.title)
                .fontWeight(.bold)
            
            if isAuthenticating {
                if let userCode = viewModel.oauthManager.userCode {
                    VStack(spacing: 16) {
                        Text("Enter this code on GitHub:")
                            .font(.headline)
                        
                        Text(userCode)
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        
                        Text("Your browser should have opened automatically.\nIf not, visit: github.com/login/device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        ProgressView("Waiting for GitHub authorization...")
                            .padding(.top)
                    }
                } else {
                    ProgressView("Connecting to GitHub...")
                }
                
                Button("Cancel") {
                    viewModel.oauthManager.cancelAuthentication()
                    isAuthenticating = false
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .padding(.top)
            } else {
                if let error = viewModel.oauthManager.errorMessage {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("QAdrito will request access to:")
                        .font(.headline)
                    
                    Label("Your repositories (to read PR details)", systemImage: "doc.text")
                        .font(.body)
                    Label("Your profile (to display your username)", systemImage: "person")
                        .font(.body)
                    Label("Organization data (to search PRs)", systemImage: "building.2")
                        .font(.body)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
                Button(action: {
                    startAuthentication()
                }) {
                    Label("Continue with GitHub", systemImage: "arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(width: 500, height: 500)
    }
    
    private func startAuthentication() {
        isAuthenticating = true
        
        Task {
            let success = await viewModel.completeAuthentication()
            
            if success {
                isPresented = false
            }
            
            isAuthenticating = false
        }
    }
}
