import AppKit
@testable import AppShellFeature
import CoreModels
import Foundation
import SwiftData
import SwiftUI
import Testing

@MainActor
struct AuditLogDialogTests {
    @Test("Lifecycle and update audit events persist only explicit metadata")
    func systemEvents() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        for event in [AppAuditEvent.started, .stopped, .updateStarted, .updateFailed, .updateInstalled] {
            try event.record(in: container.mainContext)
        }
        let entries = try container.mainContext.fetch(FetchDescriptor<AuditLogEntity>())
        #expect(entries.count == 5)
        #expect(entries.filter { $0.category == .appUpdate }.count == 3)
        #expect(entries.contains { $0.title == "App started" })
        #expect(entries.contains { $0.title == "App stopped" })
        #expect(entries.contains { $0.title == "Update failed" && $0.severity == .warning })
    }

    @Test("Database audit filters combine category, severity, exact runner and case-insensitive search")
    func filters() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let matched = AuditLogEntity(category: .runnerLifecycle, severity: .warning, title: "Runner restarted", summary: "Unexpected exit", targetRunnerName: "Mac Runner")
        context.insert(matched)
        context.insert(AuditLogEntity(category: .system, severity: .warning, title: "Runner restarted", summary: "Unexpected exit", targetRunnerName: "Mac Runner"))
        context.insert(AuditLogEntity(category: .runnerLifecycle, severity: .info, title: "Runner restarted", summary: "Unexpected exit", targetRunnerName: "Mac Runner"))
        context.insert(AuditLogEntity(category: .runnerLifecycle, severity: .warning, title: "Runner restarted", summary: "Unexpected exit", targetRunnerName: "Other Runner"))
        try context.save()
        let filter = AuditLogFilter(category: .runnerLifecycle, severity: .warning, runnerName: "Mac Runner", search: "UNEXPECTED")
        let fetched = try context.fetch(filter.descriptor(limit: 200))
        #expect(fetched.map(\.id) == [matched.id])
        #expect(try context.fetch(AuditLogFilter(search: "no such event").descriptor(limit: 200)).isEmpty)
        #expect(try context.fetch(AuditLogFilter().descriptor(limit: 2)).count == 2)
    }

    @Test("Selecting an audit runner keeps the stored name exact, including boundary whitespace")
    func selectedRunnerNameIsExact() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let padded = AuditLogEntity(category: .runnerLifecycle, title: "Imported", summary: "", targetRunnerName: " build-mac ")
        container.mainContext.insert(padded)
        container.mainContext.insert(AuditLogEntity(category: .runnerLifecycle, title: "Imported", summary: "", targetRunnerName: "build-mac"))
        try container.mainContext.save()
        let selected = AuditLogFilter(runnerName: " build-mac ")
        #expect(try container.mainContext.fetch(selected.descriptor(limit: 200)).map(\.id) == [padded.id])
    }

    @Test("Audit export snapshots preserve Unicode, quotes, identity and ISO timestamps without model references")
    func export() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = AuditLogEntity(timestamp: date, category: .configuration, title: "Änderung \"Shell\"", summary: "Zeile 1\nZeile 2", actorAccountLogin: "frank", targetRunnerName: "Mac Runner", previousValue: "/bin/bash", newValue: "/bin/zsh")
        let snapshot = AuditEventSnapshot(entry)
        entry.title = "changed after snapshot"
        let data = try AuditExportDocument(events: [snapshot], exportedAt: date).data
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(events[0]["title"] as? String == "Änderung \"Shell\"")
        #expect(events[0]["timestamp"] as? String == "2027-01-15T08:00:00Z")
        #expect(events[0]["previousValue"] as? String == "/bin/bash")
        #expect(events[0]["id"] as? String == entry.id.uuidString)
    }

    @Test("Audit dialog renders empty and populated histories at narrow and wide sizes in DE/EN Light/Dark")
    func rendering() async throws {
        for populated in [false, true] {
            let container = try OctoRunnerPersistence.makeInMemoryContainer()
            if populated {
                container.mainContext.insert(AuditLogEntity(category: .configuration, severity: .warning, title: String(repeating: "Langer Ereignistitel ", count: 8), summary: String(repeating: "Details zur Änderung ", count: 20), targetRunnerName: String(repeating: "mac-runner-", count: 20)))
                try container.mainContext.save()
            }
            for language in ["de", "en"] {
                for width in [680.0, 1100.0] {
                    for scheme in [ColorScheme.light, .dark] {
                        let host = NSHostingView(rootView: AuditLogView().modelContainer(container)
                            .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme)
                            .frame(width: width, height: 640))
                        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                        host.frame = CGRect(x: 0, y: 0, width: width, height: 640)
                        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        window.contentView = host
                        for _ in 0..<5 { await Task.yield() }
                        host.layoutSubtreeIfNeeded()
                        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        #expect(host.fittingSize.width <= width)
                        if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appending(path: "audit-\(populated)-\(language)-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
                        }
                        window.close()
                    }
                }
            }
        }
    }
}
