import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PRViewModel()
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            
            Divider()
            
            filters
            
            Divider()
            
            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading PRs...")
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                Spacer()
            } else if viewModel.displayedPRs.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("No PRs waiting on you")
                        .font(.title3)
                    if viewModel.waitingPRs.isEmpty {
                        Text("You're all caught up!")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No PRs match the current filters")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader
                        
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.displayedPRs) { stack in
                                PRRowView(stack: stack)
                                
                                if stack.id != viewModel.displayedPRs.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            footer
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onChange(of: viewModel.selectedMode) { _ in
            viewModel.updateDisplayedPRs()
        }
        .onChange(of: viewModel.authorFilter) { _ in
            viewModel.updateDisplayedPRs()
        }
        .onChange(of: viewModel.repoFilter) { _ in
            viewModel.updateDisplayedPRs()
        }
    }
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            Picker("View Mode", selection: $viewModel.selectedMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            
            Spacer()
            
            Button(action: {
                Task {
                    await viewModel.refresh()
                }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
            
            Button(action: {
                showingSettings = true
            }) {
                Label("Settings", systemImage: "gear")
            }
        }
        .padding()
    }
    
    private var filters: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "person.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Filter by author", text: $viewModel.authorFilter)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                
                if !viewModel.authorFilter.isEmpty {
                    Button(action: {
                        viewModel.authorFilter = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Filter by repo", text: $viewModel.repoFilter)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                
                if !viewModel.repoFilter.isEmpty {
                    Button(action: {
                        viewModel.repoFilter = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var sectionHeader: some View {
        HStack {
            Text("⏳ Waiting on you")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 12)
            
            Spacer()
            
            Text("\(viewModel.displayedPRs.count) PR\(viewModel.displayedPRs.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var footer: some View {
        Text(viewModel.subtitleText)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
    }
}
