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
        let created = try DesktopSessionCreator.createdItem(
            response: DesktopNewSessionResponse(
                ok: true, sessionId: "new-id", tmuxName: "lfg-new123",
                cwd: "/Users/me/dev/lfg", agent: "codex"),
            plan: inferred,
            host: createdHost)
        try expect(created.session.tmuxName == "lfg-new123" && created.session.sessionId == "new-id",
                   "create response retains the returned tmux and session identifiers")
        try expect(created.hostSSHTarget == "pro" && created.hostRemoteTransport == .moshBridged,
                   "created row retains host transport metadata for the existing iTerm opener")
