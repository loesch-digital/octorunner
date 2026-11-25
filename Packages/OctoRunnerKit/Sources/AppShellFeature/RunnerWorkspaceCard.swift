import AppKit
import DesignSystem
import SwiftUI

struct RunnerWorkspaceCard: View {
    @Environment(\.locale) private var locale

    let rootPath: String
    let workPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Workspace & APFS File System", locale: locale))
                .font(.system(size: 13, weight: .semibold))

            directoryRow(
                title: AppLocalization.string("Runner Root Directory (.runner & bin/)", locale: locale), path: rootPath,
                actionTitle: AppLocalization.string("Open in Finder", locale: locale), icon: "folder"
            )
            directoryRow(
                title: AppLocalization.string("Job Working Directory (_work)", locale: locale), path: workPath,
                actionTitle: AppLocalization.string("Open _work", locale: locale), icon: "folder.badge.gearshape"
            )
        }
        .padding(14)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
    }

    private func directoryRow(title: String, path: String, actionTitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Button(actionTitle, systemImage: icon) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
            .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
        }
    }
}
