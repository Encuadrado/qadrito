import SwiftUI

/// Searchable multi-select dropdown populated from a fixed options list.
/// Empty selection = no filter. Options stay visible when opening; typing filters via a separate query.
struct SearchableFilterDropdown: View {
    let placeholder: String
    let systemImage: String
    let options: [String]
    /// Plural noun for the compact multi-select label, e.g. "authors" / "repos".
    let selectionNounPlural: String
    @Binding var selection: Set<String>
    
    @State private var isOpen = false
    @State private var query = ""
    @FocusState private var isFocused: Bool
    
    private var filteredOptions: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return options }
        return options.filter { $0.localizedCaseInsensitiveContains(q) }
    }
    
    private var buttonLabel: String {
        if selection.isEmpty {
            return placeholder
        }
        if selection.count == 1, let only = selection.first {
            return only
        }
        return "\(selection.count) \(selectionNounPlural)"
    }
    
    private func isSelected(_ option: String) -> Bool {
        selection.contains { $0.caseInsensitiveCompare(option) == .orderedSame }
    }
    
    private func toggle(_ option: String) {
        if let existing = selection.first(where: { $0.caseInsensitiveCompare(option) == .orderedSame }) {
            selection.remove(existing)
        } else {
            selection.insert(option)
        }
    }
    
    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                Text(buttonLabel)
                    .foregroundColor(selection.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)
                
                if !selection.isEmpty {
                    Button {
                        selection = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
                
                MultiFilterOptionsPopover(
                    options: options,
                    filteredOptions: filteredOptions,
                    selection: selection,
                    emptyOptionsMessage: "No options yet — refresh PRs",
                    onToggle: { option in
                        toggle(option)
                    }
                )
            }
            .frame(width: 260, height: min(CGFloat(max(filteredOptions.count, 1)) * 28 + 52, 280))
            .onAppear {
                query = ""
                isFocused = true
            }
        }
    }
}

/// Searchable required-selection dropdown (no empty/clear). Selection is by display label.
struct SearchableSelectDropdown: View {
    let placeholder: String
    let systemImage: String
    let options: [String]
    @Binding var selection: String
    
    @State private var isOpen = false
    @State private var query = ""
    @FocusState private var isFocused: Bool
    
    private var filteredOptions: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return options }
        return options.filter { $0.localizedCaseInsensitiveContains(q) }
    }
    
    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                Text(selection.isEmpty ? placeholder : selection)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 180)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
                
                FilterOptionsPopover(
                    options: options,
                    filteredOptions: filteredOptions,
                    selection: selection,
                    emptyOptionsMessage: "No matches"
                ) { option in
                    selection = option
                    query = ""
                    isOpen = false
                }
            }
            .frame(width: 260, height: min(CGFloat(max(filteredOptions.count, 1)) * 28 + 52, 240))
            .onAppear {
                query = ""
                isFocused = true
            }
        }
    }
}

private struct MultiFilterOptionsPopover: View {
    let options: [String]
    let filteredOptions: [String]
    let selection: Set<String>
    let emptyOptionsMessage: String
    let onToggle: (String) -> Void
    
    private func isSelected(_ option: String) -> Bool {
        selection.contains { $0.caseInsensitiveCompare(option) == .orderedSame }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if options.isEmpty {
                Text(emptyOptionsMessage)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if filteredOptions.isEmpty {
                Text("No matches")
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredOptions, id: \.self) { option in
                            let selected = isSelected(option)
                            Button {
                                onToggle(option)
                            } label: {
                                HStack {
                                    Text(option)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                selected
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct FilterOptionsPopover: View {
    let options: [String]
    let filteredOptions: [String]
    let selection: String
    let emptyOptionsMessage: String
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if options.isEmpty {
                Text(emptyOptionsMessage)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if filteredOptions.isEmpty {
                Text("No matches")
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredOptions, id: \.self) { option in
                            Button {
                                onSelect(option)
                            } label: {
                                HStack {
                                    Text(option)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if option.caseInsensitiveCompare(selection) == .orderedSame {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                option.caseInsensitiveCompare(selection) == .orderedSame
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                            )
                        }
                    }
                }
            }
        }
    }
}
