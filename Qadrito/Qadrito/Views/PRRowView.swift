import SwiftUI

struct PRRowView: View {
    let stack: PRStack
    var collapseStackedPRs: Bool = false
    @State private var isExpanded = false
    
    private var pr: PullRequest { stack.base }
    
    /// Matches ContentView group indent so the control sits in that gutter.
    private let gutterWidth: CGFloat = 22
    private let expandHitSize: CGFloat = 22
    
    private var showStackMembers: Bool {
        stack.stackSize > 1 && isExpanded
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Gutter pulled into the group indent; titles stay aligned with non-stack rows.
                ZStack(alignment: .top) {
                    Color.clear.frame(width: gutterWidth)
                    if stack.stackSize > 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: showStackMembers ? "minus" : "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: expandHitSize, height: expandHitSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(showStackMembers ? "Collapse stack" : "Show stacked PRs")
                        // Sit on the title line (below displayName + spacing).
                        .padding(.top, 18)
                    }
                }
                .frame(width: gutterWidth)
                .padding(.leading, -gutterWidth)
                
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: { open(pr.htmlUrl) }) {
                        HStack(spacing: 8) {
                            Text(stack.displayName)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                            
                            Text(pr.author)
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            if stack.stackSize > 1 {
                                Text("Stack · \(stack.stackSize)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                                
                                if !showStackMembers {
                                    Text("+\(stack.stackSize - 1) more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            ageBadge(for: pr)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { open(pr.htmlUrl) }) {
                        HStack(spacing: 12) {
                            Text(pr.title)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer(minLength: 0)
                            
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    prMetadataLine(for: pr)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onAppear {
                isExpanded = !collapseStackedPRs
            }
            .onChange(of: collapseStackedPRs) { _, collapsed in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded = !collapsed
                }
            }
            
            if showStackMembers {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(stack.prs) { member in
                        stackMemberRow(member)
                    }
                }
                .padding(.leading, 16)
                .padding(.bottom, 8)
            }
        }
    }
    
    private func stackMemberRow(_ member: PullRequest) -> some View {
        Button {
            open(member.htmlUrl)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: member.id == pr.id ? "arrowtriangle.up.fill" : "circle")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                
                Text(member.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(member.id == pr.id ? .semibold : .regular)
                
                Text(member.title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(member.ageText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private func ageBadge(for pr: PullRequest) -> some View {
        Text(pr.ageText)
            .font(.caption)
            .foregroundColor(pr.ageDays >= 30 ? .orange : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
    
    /// Checks fraction + comment count under the PR title.
    private func prMetadataLine(for pr: PullRequest) -> some View {
        HStack(spacing: 12) {
            checksIndicator(for: pr)
            commentsIndicator(for: pr)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
    
    @ViewBuilder
    private func checksIndicator(for pr: PullRequest) -> some View {
        let conclusion = pr.checksConclusion?.lowercased()
        let fractionText: String? = {
            guard let passed = pr.checkPassed, let total = pr.checkTotal, total > 0 else {
                return nil
            }
            return "\(passed)/\(total)"
        }()
        
        switch conclusion {
        case "success":
            checkStatusLabel(symbol: "checkmark", color: .green, fraction: fractionText)
        case "failure":
            checkStatusLabel(symbol: "xmark", color: .red, fraction: fractionText)
        case "pending":
            checkStatusLabel(symbol: "ellipsis.circle", color: .secondary, fraction: fractionText)
        default:
            checkStatusLabel(symbol: "circle", color: .secondary, fraction: nil)
        }
    }
    
    private func checkStatusLabel(symbol: String, color: Color, fraction: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundColor(color)
            if let fraction {
                Text(fraction)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func commentsIndicator(for pr: PullRequest) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bubble.right")
                .foregroundColor(.secondary)
            Text("\(pr.commentCount)")
                .foregroundColor(.secondary)
        }
    }
    
    private func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
