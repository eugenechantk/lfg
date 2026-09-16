        try expect(capped.needsInput.count == MenuBarSessionProjection.activeLimit && capped.needsInputCount == 7,
                   "needs-input rows are capped while retaining the full count")
        try expect(capped.recent.count == MenuBarSessionProjection.recentLimit && capped.recentCount == 7,
                   "recent rows are capped while retaining the full count")

        let searchableItems = [
            menuTestItem(id: "needle-input", lastActivity: 100, needsInput: true),
            menuTestItem(id: "needle-running", lastActivity: 300, busy: true),
            menuTestItem(id: "needle-recent", lastActivity: 200),
            menuTestItem(id: "other-recent", lastActivity: 400),
        ]
        let filtered = MenuBarSessionProjection(items: searchableItems, query: "  NEEDLE \n")
        try expect(filtered.needsInput.map(\.session.id) == ["needle-input"] &&
                   filtered.running.map(\.session.id) == ["needle-running"] &&
                   filtered.recent.map(\.session.id) == ["needle-recent"],
                   "menu search filters all sections case-insensitively after trimming")
        try expect(filtered.needsInputCount == 1 && filtered.runningCount == 1 && filtered.recentCount == 1,
                   "filtered section counts describe only matching sessions")
        let restored = MenuBarSessionProjection(items: searchableItems, query: " \n")
        try expect(restored.needsInputCount + restored.runningCount + restored.recentCount == searchableItems.count,
                   "clearing menu search restores every session")

        try runSearchTests()
        try runNewSessionPlannerTests()
    }

    /// Creation starts from search context, so pin the directory/model decision
    /// independently of networking and iTerm automation.
    @MainActor
    private static func runNewSessionPlannerTests() throws {
        let fallback = DesktopNewSessionPlanner.plan(
            query: "   ",
            items: [],
            defaultHostURL: "http://default:8766",
            inbox: "/Users/me/repos/_inbox"
        )
        try expect(fallback == DesktopNewSessionPlan(
            hostURL: "http://default:8766",
            cwd: "/Users/me/repos/_inbox",
            agent: "claude",
            model: "claude-opus-5"
        ), "empty search uses the default host Inbox and the iOS default model")

        let exactDirectory = newSessionTestItem(
            id: "exact-directory", title: "older work", project: "lfg",
            cwd: "/Users/me/dev/lfg", lastActivity: 100,
            agent: "claude", model: "sonnet", hostURL: "http://pro:8766")
        let incidentalMention = newSessionTestItem(
            id: "incidental", title: "fix the lfg integration", project: "website",
            cwd: "/Users/me/dev/website", lastActivity: 500,
            agent: "claude", model: "opus", hostURL: "http://air:8766")
        let latestInExactDirectory = newSessionTestItem(
            id: "latest-model", title: "unrelated title", project: "workspace",
            cwd: "/Users/me/dev/lfg/", lastActivity: 300,
            agent: "codex", model: "gpt-5.6-sol", hostURL: "http://pro:8766")
        let inferred = try require(DesktopNewSessionPlanner.plan(
            query: "lfg",
            items: [incidentalMention, exactDirectory, latestInExactDirectory],
            defaultHostURL: "http://default:8766",
            inbox: "/Users/me/repos/_inbox"
        ), "search resolves a directory-bearing plan")
        try expect(inferred == DesktopNewSessionPlan(
            hostURL: "http://pro:8766",
            cwd: "/Users/me/dev/lfg",
            agent: "codex",
            model: "gpt-5.6-sol"
        ), "exact directory relevance wins and its newest session supplies agent/model")

        let hostScopedDirectory = newSessionTestItem(
            id: "host-scoped-directory", title: "selected project", project: "unique-project",
            cwd: "/Users/me/dev/shared", lastActivity: 100,
            agent: "codex", model: "gpt-5.6-sol", hostURL: "http://pro:8766")
        let samePathOtherHost = newSessionTestItem(
            id: "same-path-other-host", title: "unrelated title", project: "workspace",
            cwd: "/Users/me/dev/shared", lastActivity: 900,
            agent: "claude", model: "haiku", hostURL: "http://air:8766")
        try expect(DesktopNewSessionPlanner.plan(
            query: "unique-project",
            items: [hostScopedDirectory, samePathOtherHost],
            defaultHostURL: "http://default:8766",
            inbox: "/Users/me/repos/_inbox"
        )?.model == "gpt-5.6-sol",
                   "model history stays on the selected host when another host has the same path")

        let noModel = newSessionTestItem(
            id: "codex-no-model", title: "render pipeline", project: "render",
            cwd: "/Users/me/dev/render", lastActivity: 10,
            agent: "codex", model: nil, hostURL: "http://studio:8766")
        try expect(DesktopNewSessionPlanner.plan(
            query: "render", items: [noModel],
            defaultHostURL: "http://default:8766", inbox: "/inbox"
        )?.model == "gpt-5.6-sol", "known agent without model uses that agent's iOS default")

        let readableOlderModel = newSessionTestItem(
            id: "render-known-model", title: "older render", project: "render",
            cwd: "/Users/me/dev/render", lastActivity: 5,
            agent: "codex", model: "gpt-5.6-terra", hostURL: "http://studio:8766")
        try expect(DesktopNewSessionPlanner.plan(
            query: "render", items: [noModel, readableOlderModel],
            defaultHostURL: "http://default:8766", inbox: "/inbox"
        )?.model == "gpt-5.6-terra",
                   "newest readable directory model wins over newer metadata without a model")

        try expect(DesktopNewSessionPlanner.plan(
            query: "missing", items: [exactDirectory],
            defaultHostURL: "http://default:8766", inbox: "/inbox"
        ) == nil, "non-empty search with no directory-bearing match does not fall back to Inbox")

        let request = try DesktopSessionCreator.newSessionRequest(plan: inferred)
        let body = try require(request.httpBody, "create request has a JSON body")
        let payload = try require(
            try JSONSerialization.jsonObject(with: body) as? [String: String],
            "create request JSON has string fields")
        try expect(request.httpMethod == "POST" && request.url?.path == "/api/sessions/new",
                   "create request targets POST /api/sessions/new")
        try expect(payload == [
            "cwd": "/Users/me/dev/lfg",
            "prompt": "",
            "agent": "codex",
            "model": "gpt-5.6-sol",
        ], "create request sends the inferred directory, agent, and model with an empty prompt")

        let createdHost = HostState(
            url: "http://pro:8766", sshTarget: "pro", remoteTransport: .moshBridged,
            displayName: "Pro", info: HostInfoResponse(hostId: "pro-id", hostName: "Pro.local"),
            isLocal: false)
