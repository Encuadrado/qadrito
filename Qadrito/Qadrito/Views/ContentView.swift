import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = PRViewModel()
    @EnvironmentObject private var preferences: AppPreferences
    @State private var showingSettings = false
    @State private var showingAuthFlow = false
    @State private var showNotificationsPanel = false
    @EnvironmentObject private var notificationStore: NotificationStore
    @State private var collapsedAgeGroups: Set<Int> = Set(PRAgeGroup.allCases.map(\.rawValue))
    /// Apply Critical→Warning→On time expand heuristic once per scope until the user changes tabs.
    @State private var didApplyDefaultAgeCollapse = false
    
    var body: some View {
        Group {
            if !viewModel.isAuthenticated {
                signInView
            } else {
                mainView
            }
        }
        .sheet(isPresented: $showingAuthFlow) {
            AuthenticationView(viewModel: viewModel, isPresented: $showingAuthFlow)
        }
    }
    
    private var mainView: some View {
        ZStack(alignment: .trailing) {
        VStack(spacing: 0) {
            toolbar
            
            Divider()
            
            filters
            
            Divider()
            
            // Body loader when this scope has no rows yet (All often takes a while).
            // Keep showing the list when refreshing with cached data.
            if viewModel.isLoading && viewModel.displayedPRs.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .scaleEffect(1.15)
                    Text("Loading PRs…")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
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
                    Text(viewModel.emptyStateTitle)
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
                        listHeader
                        
                        ForEach(viewModel.displayedSections) { section in
                            ageGroupHeader(section)
                            if !collapsedAgeGroups.contains(section.group.rawValue) {
                                stackList(section.stacks)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            footer
        }
        .frame(minWidth: 600, minHeight: 400)

            if showNotificationsPanel {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showNotificationsPanel = false
                        }
                    }

                NotificationsPanelView(store: notificationStore) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showNotificationsPanel = false
                    }
                }
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onChange(of: viewModel.authorFilter) {
            viewModel.updateDisplayedPRs()
        }
        .onChange(of: viewModel.repoFilter) {
            viewModel.updateDisplayedPRs()
        }
        .onChange(of: viewModel.teamFilter) {
            viewModel.updateDisplayedPRs()
        }
        .onChange(of: viewModel.tagFilter) {
            viewModel.updateDisplayedPRs()
        }
        .onAppear {
            applyDefaultAgeCollapseIfNeeded()
        }
        .onChange(of: viewModel.isLoading) { _, loading in
            if !loading {
                applyDefaultAgeCollapseIfNeeded()
            }
        }
        .onChange(of: ageCollapseSignature) { _, _ in
            applyDefaultAgeCollapseIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .qadritoOpenNotificationsPanel)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                showNotificationsPanel = true
            }
        }
    }
    
    private var signInView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("QAdrito")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("View your Encuadrado PR review queue")
                .font(.title3)
                .foregroundColor(.secondary)

            if let reason = viewModel.sessionExpiredReason {
                VStack(spacing: 4) {
                    Label("Your GitHub session expired", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
            }

            Button(action: {
                showingAuthFlow = true
            }) {
                Label("Sign in with GitHub", systemImage: "chevron.right")
                    .font(.headline)
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .padding(40)
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private var toolbar: some View {
        Picker("Scope", selection: $viewModel.selectedScope) {
            ForEach(PRScope.allCases) { scope in
                Text(scope.tabTitle).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: viewModel.selectedScope) { _, _ in
            didApplyDefaultAgeCollapse = false
            viewModel.handleScopeChange()
            applyDefaultAgeCollapseIfNeeded()
        }
        .padding()
    }
    
    private var filters: some View {
        HStack(spacing: 16) {
            SearchableFilterDropdown(
                placeholder: "Filter by team",
                systemImage: "person.3.fill",
                options: viewModel.teamOptions,
                selectionNounPlural: "teams",
                selection: $viewModel.teamFilter
            )
            
            SearchableFilterDropdown(
                placeholder: "Filter by author",
                systemImage: "person.fill",
                options: viewModel.authorOptions,
                selectionNounPlural: "authors",
                selection: $viewModel.authorFilter
            )
            
            SearchableFilterDropdown(
                placeholder: "Filter by repo",
                systemImage: "folder.fill",
                options: viewModel.repoOptions,
                selectionNounPlural: "repos",
                selection: $viewModel.repoFilter
            )
            
            SearchableFilterDropdown(
                placeholder: "Filter by tag",
                systemImage: "tag.fill",
                options: viewModel.tagOptions,
                selectionNounPlural: "tags",
                selection: $viewModel.tagFilter
            )
            
            HStack(spacing: 8) {
                Text("Stacked PRs")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Picker(
                    "Stacked PRs",
                    selection: Binding(
                        get: { preferences.collapseStackedPRs },
                        set: { preferences.setCollapseStackedPRs($0) }
                    )
                ) {
                    Text("Collapsed").tag(true)
                    Text("Expanded").tag(false)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            Spacer()
            
            if preferences.isDoNotDisturb {
                Image(systemName: "moon.fill")
                    .foregroundColor(.secondary)
                    .help("Do Not Disturb is on")
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showNotificationsPanel.toggle()
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14))
                        .frame(width: 22, height: 18)
                    if notificationStore.unreadCount > 0 {
                        Text(notificationStore.unreadCount > 9 ? "9+" : "\(notificationStore.unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 8, y: -8)
                    }
                }
                .frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .help("Notifications")
            
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
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var listHeader: some View {
        HStack {
            Text(viewModel.selectedScope.rawValue)
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 12)
            
            Spacer()
            
            Group {
                if viewModel.listedPRCount != viewModel.displayedPRs.count {
                    Text("\(viewModel.listedPRCount) PRs · \(viewModel.displayedPRs.count) stacks")
                } else {
                    Text("\(viewModel.listedPRCount) PR\(viewModel.listedPRCount == 1 ? "" : "s")")
                }
            }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    

    /// Counts per age group — used to (re)apply the default expand heuristic after data lands.
    private var ageCollapseSignature: String {
        viewModel.displayedSections
            .map { "\($0.group.rawValue):\($0.stacks.count)" }
            .joined(separator: "|")
    }
    
    /// Expand the highest non-empty group (Critical → Warning → On time); collapse the rest.
    private func applyDefaultAgeCollapseIfNeeded() {
        guard !didApplyDefaultAgeCollapse else { return }
        guard !viewModel.isLoading else { return }
        // Instant cache / finished fetch: sections may be empty (all caught up).
        guard viewModel.lastRefreshDate != nil || !viewModel.displayedSections.isEmpty else { return }
        
        var collapsed = Set(PRAgeGroup.allCases.map(\.rawValue))
        let priority: [PRAgeGroup] = [.critical, .warning, .onTime]
        if let open = priority.first(where: { group in
            viewModel.displayedSections.contains { $0.group == group && !$0.stacks.isEmpty }
        }) {
            collapsed.remove(open.rawValue)
        }
        collapsedAgeGroups = collapsed
        didApplyDefaultAgeCollapse = true
    }
    
    private func ageGroupHeader(_ section: PRAgeSection) -> some View {
        let isCollapsed = collapsedAgeGroups.contains(section.group.rawValue)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isCollapsed {
                    collapsedAgeGroups.remove(section.group.rawValue)
                } else {
                    collapsedAgeGroups.insert(section.group.rawValue)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                
                Text(section.group.title)
                    .font(.title2.weight(.semibold))
                
                Text(ageGroupGlyph(section.group))
                    .font(.system(size: 18))
                    .accessibilityLabel(section.group.title)
                
                Text("\(section.stacks.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer(minLength: 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func color(for group: PRAgeGroup) -> Color {
        switch group {
        case .critical: return .red
        case .warning: return .orange
        case .onTime: return .green
        }
    }
    
    private func ageGroupGlyph(_ group: PRAgeGroup) -> String {
        switch group {
        case .critical: return "🔴"
        case .warning: return "⚠️"
        case .onTime: return "🟢"
        }
    }
    
    private func stackList(_ stacks: [PRStack]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(stacks) { stack in
                PRRowView(stack: stack, collapseStackedPRs: preferences.collapseStackedPRs)
                
                if stack.id != stacks.last?.id {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .padding(.leading, 20)
    }
    
    private var footer: some View {
        Text(viewModel.subtitleText)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
    }
}
