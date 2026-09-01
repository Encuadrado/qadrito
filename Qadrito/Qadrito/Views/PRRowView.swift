import SwiftUI

struct PRRowView: View {
    let stack: PRStack
    
    private var pr: PullRequest {
        stack.tip
    }
    
    private var ageText: String {
        let days = pr.ageDays
        if days == 0 {
            let hours = Int(pr.age / 3600)
            if hours == 0 {
                let minutes = Int(pr.age / 60)
                return "\(minutes)m"
            }
            return "\(hours)h"
        } else if days == 1 {
            return "1 day"
        } else {
            return "\(days) days"
        }
    }
    
    var body: some View {
        Button(action: {
            if let url = URL(string: pr.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(stack.displayName)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        
                        Text(pr.author)
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(ageText)
                            .font(.caption)
                            .foregroundColor(pr.ageDays >= 30 ? .orange : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    
                    Text(pr.title)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color(nsColor: .controlBackgroundColor)
                .opacity(0)
        )
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
