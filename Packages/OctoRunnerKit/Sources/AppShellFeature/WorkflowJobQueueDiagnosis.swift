import CoreModels
import Foundation
import GitHubAPI
import SyncKit

struct WorkflowJobQueueDiagnosis {
    enum Reason {
        case staleJob, runnerStatusUnavailable, noKnownMatch, idleMatch, busyOrOffline
    }

    struct Runner: Identifiable {
        enum State {
            case idle, busy, offline
        }

        let id: Int64
        let name: String
        let state: State

        init?(_ remote: GitHubRemoteRunnerDTO) {
            switch remote.status {
            case "offline": state = .offline
            case "online": state = remote.busy ? .busy : .idle
            default: return nil
            }
            id = remote.id
            name = remote.name
        }
    }

    let jobAge: Double?
    let reason: Reason
    let runners: [Runner]

    init?(job: GitHubWorkflowJobDTO, repository: String, jobObservedAt: Date?,
          account: RunnerSyncAccount?, configurations: [UUID: LocalDotRunnerConfig],
          snapshot: RunnerSyncSnapshot?, now: Date) {
        let requiredLabels = Set((job.labels ?? []).map { $0.lowercased() })
        guard job.status == "queued", (job.runnerID ?? 0) <= 0,
              requiredLabels.contains("self-hosted") else { return nil }

        guard Self.isFresh(jobObservedAt, at: now) else {
            jobAge = nil
            reason = .staleJob
            runners = []
            return
        }
        jobAge = WorkflowExecutionDuration.elapsedSeconds(since: job.createdAt, at: now)

        guard let snapshot, snapshot.account == account, Self.isFresh(snapshot.observedAt, at: now),
              let slug = GitHubRepositorySlug(input: repository) else {
            reason = .runnerStatusUnavailable
            runners = []
            return
        }
        let candidates = Self.repositoryRunners(snapshot, configurations: configurations, repository: slug)
        let matches = candidates.filter { requiredLabels.isSubset(of: $0.labelNames.map { $0.lowercased() }) }
        runners = matches.compactMap(Runner.init)
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }

        if runners.contains(where: { $0.state == .idle }) {
            reason = .idleMatch
        } else if !runners.isEmpty {
            reason = .busyOrOffline
        } else if candidates.isEmpty || !matches.isEmpty {
            reason = .runnerStatusUnavailable
        } else {
            reason = .noKnownMatch
        }
    }

    private static func repositoryRunners(_ snapshot: RunnerSyncSnapshot, configurations: [UUID: LocalDotRunnerConfig],
                                          repository: GitHubRepositorySlug) -> [GitHubRemoteRunnerDTO] {
        var byID: [Int64: GitHubRemoteRunnerDTO] = [:]
        for (id, configuration) in configurations {
            guard snapshot.configurations[id] == configuration,
                  GitHubRepositorySlug(input: configuration.gitHubUrl.absoluteString) == repository,
                  case .found(let runner, _) = snapshot.results[id], runner.id == configuration.agentId else { continue }
            byID[runner.id] = runner
        }
        return Array(byID.values)
    }

    static func isFresh(_ observation: Date?, at now: Date) -> Bool {
        guard let observation else { return false }
        return (-5...90).contains(now.timeIntervalSince(observation))
    }
}
