import AppKit
import MacFreeCore
import SwiftUI

struct SuggestionsView: View {
    private var model: AppModel { .shared }

    var body: some View {
        let suggestions = model.suggestions
        ScrollView {
            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    SuggestionCard(
                        title: suggestion.title,
                        detail: suggestion.detail,
                        symbol: suggestion.symbol,
                        size: suggestion.total,
                        examples: suggestion.items.sorted { $0.size > $1.size }.prefix(3).map(\.name),
                        isSelected: suggestion.items.allSatisfy(model.isChecked),
                        select: { model.check(suggestion.items) },
                        unselect: { suggestion.items.forEach { model.setChecked($0, false) } },
                        review: { model.section = suggestion.reviewSection }
                    )
                }
                if model.activeDuplicates.isEmpty {
                    duplicatesPrompt
                } else {
                    let groups = model.activeDuplicates
                    let extras = groups.flatMap(\.extras)
                    SuggestionCard(
                        title: "Duplicate Files",
                        detail: "Selecting keeps one copy of each file.",
                        symbol: "doc.on.doc",
                        size: groups.reduce(0) { $0 + $1.wastedSize },
                        examples: extras.prefix(3).map(\.name),
                        isSelected: extras.allSatisfy(model.isChecked),
                        select: { model.check(extras) },
                        unselect: { extras.forEach { model.setChecked($0, false) } },
                        review: { model.section = .duplicates }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var duplicatesPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc").font(.title3).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Duplicate Files").font(.headline)
                Text("Compares file contents, which takes a little longer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Find Duplicates") {
                model.section = .duplicates
                model.findDuplicates()
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}

private struct SuggestionCard: View {
    let title: String
    let detail: String
    let symbol: String
    let size: Int64
    let examples: [String]
    let isSelected: Bool
    let select: () -> Void
    let unselect: () -> Void
    let review: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Text(examples.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Text(Format.size(size))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Button("Review", action: review)
            Button(isSelected ? "Unselect" : "Select", action: isSelected ? unselect : select)
                .frame(minWidth: 70)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}

struct DuplicatesView: View {
    private var model: AppModel { .shared }

    var body: some View {
        Group {
            if let done = model.duplicateProgress {
                progress(done)
            } else if !model.hasSearchedDuplicates {
                ContentUnavailableView {
                    Label("Find identical files", systemImage: "doc.on.doc")
                } description: {
                    Text("MacFree reads files over 1 MB and compares their contents. App data, hidden folders and code projects are left out, because their copies are often needed. Nothing is deleted.")
                } actions: {
                    Button("Find Duplicates") { model.findDuplicates() }
                }
            } else if model.activeDuplicates.isEmpty {
                ContentUnavailableView("No duplicates found", systemImage: "checkmark.circle")
            } else {
                results
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progress(_ value: (done: Int, total: Int)) -> some View {
        VStack(spacing: 14) {
            ProgressView(value: Double(value.done), total: Double(max(value.total, 1)))
                .frame(width: 320)
            Text("Compared \(value.done.formatted()) of \(value.total.formatted()) possible matches")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Cancel") { model.cancelDuplicates() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        let groups = model.activeDuplicates
        return VStack(spacing: 8) {
            HStack {
                Text("\(Format.size(groups.reduce(0) { $0 + $1.wastedSize })) could be freed")
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Button("Select All Extra Copies") { model.check(groups.flatMap(\.extras)) }
            }
            .padding(.horizontal, 20)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(groups) { group in
                        VStack(spacing: 6) {
                            ForEach(group.remaining) { file in
                                DuplicateRow(file: file, isKeeper: file === group.keeper)
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

private struct DuplicateRow: View {
    private var model: AppModel { .shared }
    let file: FileNode
    let isKeeper: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Select \(file.name)", isOn: Binding(
                get: { model.isChecked(file) },
                set: { model.setChecked(file, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            FileIcon(node: file, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Text(file.displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            if isKeeper {
                Text("Suggested keep")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: .capsule)
            }
            Text(Format.size(file.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show in Finder")
        }
    }
}
