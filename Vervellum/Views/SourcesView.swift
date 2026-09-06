import SwiftUI
import AppKit

/// The source list under a turn.
///
/// Sources are split into *cited* and *found but unused*, and the split is shown
/// rather than hidden. A source the model looked at and did not use is evidence about
/// the answer: four cited out of eighteen found means the model was selective, and the
/// user should be able to see the fourteen it passed over.
struct SourcesView: View {

    let sources: [Source]
    let citedNumbers: Set<Int>
    @Binding var showsAll: Bool

    private var cited: [Source] { sources.filter { citedNumbers.contains($0.number) } }
    private var uncited: [Source] { sources.filter { !citedNumbers.contains($0.number) } }

    var body: some View {
        VStack(alignment: .leading, spacing: PanelTheme.Space.small) {
            SectionLabel(text: "Sources", trailing: countText)
            VStack(alignment: .leading, spacing: PanelTheme.Space.tight) {
                ForEach(cited) { source in
                    SourceRow(source: source, isCited: true)
                }
                if showsAll {
                    ForEach(uncited) { source in
                        SourceRow(source: source, isCited: false)
                    }
                }
            }
            if !uncited.isEmpty {
                Button {
                    withAnimation(PanelTheme.Motion.disclosure) { showsAll.toggle() }
                } label: {
                    Text(showsAll
                         ? "Hide the \(uncited.count) uncited"
                         : "Show \(uncited.count) found but not cited")
                        .font(PanelTheme.Font.caption)
                        .foregroundStyle(PanelTheme.Palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var countText: String? {
        guard !sources.isEmpty else { return nil }
        return "\(cited.count) of \(sources.count) cited"
    }
}

/// One source: number, title, domain, date, and the snippet the model actually saw.
///
/// The snippet is shown, and labelled as a search summary, because the single most
/// misleading thing a research tool can do is present a citation as though the page
/// had been read. What was read is this paragraph, and the user can see exactly that.
struct SourceRow: View {
    let source: Source
    var isCited: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            guard let url = URL(string: source.url) else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(alignment: .top, spacing: PanelTheme.Space.small) {
                Text("\(source.number)")
                    .font(PanelTheme.Font.citation(1.0))
                    .foregroundStyle(isCited ? PanelTheme.Palette.accent : PanelTheme.Palette.tertiaryText)
                    .frame(width: 18, alignment: .trailing)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isCited
                                         ? PanelTheme.Palette.primaryText
                                         : PanelTheme.Palette.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: PanelTheme.Space.tight) {
                        Text(source.domain)
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelTheme.Palette.tertiaryText)
                        if let published = source.publishedAt, !published.isEmpty {
                            Text("·").foregroundStyle(PanelTheme.Palette.tertiaryText)
                            Text(published)
                                .font(.system(size: 10.5))
                                .foregroundStyle(PanelTheme.Palette.tertiaryText)
                        }
                    }
                    if isHovering, !source.snippet.isEmpty {
                        Text(source.snippet)
                            .font(.system(size: 10.5))
                            .foregroundStyle(PanelTheme.Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                        Text("Search summary — not the full page")
                            .font(.system(size: 9.5))
                            .foregroundStyle(PanelTheme.Palette.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 9))
                    .foregroundStyle(PanelTheme.Palette.tertiaryText)
                    .opacity(isHovering ? 1 : 0)
                    .padding(.top, 2)
            }
            .padding(.vertical, PanelTheme.Space.tight)
            .padding(.horizontal, PanelTheme.Space.small)
            .background(isHovering ? PanelTheme.Palette.chipFill : .clear,
                        in: RoundedRectangle(cornerRadius: PanelTheme.Radius.chip, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(PanelTheme.Motion.disclosure) { isHovering = hovering }
        }
        .help(source.url)
        .accessibilityLabel("Source \(source.number), \(source.title), \(source.domain)")
    }
}
