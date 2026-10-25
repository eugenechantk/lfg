import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import LFGCore

struct ShareComposerView: View {
    @Bindable var model: ShareComposerModel
    var onClose: () -> Void
    @FocusState private var editing: Bool
    private let accent = Color(red: 10/255, green: 110/255, blue: 224/255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                search
                if let error = model.inputError {
                    ContentUnavailableView("Couldn’t load this share", systemImage: "exclamationmark.triangle", description: Text(error))
                        .accessibilityIdentifier("share_input_error")
                } else if model.configuration.hosts.isEmpty {
                    ContentUnavailableView("Set up LFG first", systemImage: "network", description: Text("Open LFG and add a computer, then share again."))
                        .accessibilityIdentifier("share_setup_required")
                } else {
                    recipients
                }
            }
            .background(Color(.secondarySystemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.selectedID != nil && !model.loadingInput { composer }
                else if model.loadingInput { ProgressView("Loading share…").padding().accessibilityIdentifier("share_loading") }
            }
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.cancel(); onClose()
                    } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close share")
                    .disabled(model.sending)
                    .accessibilityIdentifier("share_cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.refresh() } } label: {
                        if model.refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityLabel("Refresh sessions")
                    .accessibilityIdentifier("share_refresh")
                    .disabled(model.refreshing || model.locksDraft)
                }
            }
            .sheet(isPresented: $model.showingOptions) { options }
            .task(id: model.query) { await model.searchHistory() }
            .interactiveDismissDisabled(model.sending)
            .task(id: completionToken) {
                guard completionToken != nil else { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled else { return }
                onClose()
            }
            .animation(.easeInOut(duration: 0.18), value: model.selectedID)
            .accessibilityIdentifier("share_sheet")
        }
        .tint(accent)
    }

    /// A newly persisted job starts queued, even when its upload is about to
    /// begin. Only the completed operation may start the dismissal timer.
    private var completionToken: String? {
        guard !model.sending, let job = model.delivery,
              job.status == .sent || job.status == .queued else { return nil }
        return job.id + ":" + job.status.rawValue
    }

    private var search: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search sessions", text: $model.query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("share_search")
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear search").accessibilityIdentifier("share_search_clear")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        .disabled(model.locksDraft)
    }

    private var recipients: some View {
        let sections = ShareRecipients.sections(model.recipients, query: model.query)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                newSession
                if let error = model.refreshError {
                    Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
                        .accessibilityIdentifier("share_offline_notice")
                }
                if !sections.recent.isEmpty { recipientSection("Recent", rows: sections.recent) }
                if !sections.all.isEmpty { recipientSection(model.query.isEmpty ? "All sessions" : "Results", rows: sections.all) }
                if sections.all.isEmpty && sections.recent.isEmpty {
                    ContentUnavailableView(model.query.isEmpty ? "No sessions yet" : "No matching sessions", systemImage: "bubble.left.and.bubble.right",
                                           description: Text(model.query.isEmpty ? "Choose New session to start one with this share." : "Try a title, folder or computer name."))
                        .accessibilityIdentifier("share_no_results")
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("share_recipients")
    }

    private var newSession: some View {
        HStack(spacing: 8) {
            Button { editing = false; model.select("new") } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus").font(.title2).frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("New session").font(.body)
                        Text([model.cwd.isEmpty ? "Choose a folder" : URL(fileURLWithPath: model.cwd).lastPathComponent, model.host?.label ?? "", model.agent == "claude" ? "Claude" : "Codex"]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("share_new_session")
                .accessibilityAddTraits(model.isNew ? .isSelected : [])
            Button { model.showingOptions = true } label: {
                Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("New session options").accessibilityIdentifier("share_new_options")
            Button { editing = false; model.select("new") } label: { check(model.isNew).frame(minWidth: 32, minHeight: 44) }
                .buttonStyle(.plain).accessibilityLabel("Select new session").accessibilityIdentifier("share_new_session_check")
        }
        .padding(12).background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
        .disabled(model.locksDraft)
    }

    private func recipientSection(_ title: String, rows: [ShareRecipient]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 12)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    Button { editing = false; model.select(row.id) } label: {
                        HStack(spacing: 12) {
                            avatar(row)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.session.title).font(.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                (Text(row.status).foregroundColor(statusColor(row)) + Text(" · " + [row.session.project ?? row.session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "", row.host.label]
                                    .filter { !$0.isEmpty }.joined(separator: " · ")).foregroundColor(.secondary))
                                    .font(.caption).lineLimit(1)
                            }
                            check(model.selectedID == row.id)
                        }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("share_recipient_\(row.session.id)")
                        .accessibilityAddTraits(model.selectedID == row.id ? .isSelected : [])
                    if row.id != rows.last?.id { Divider().padding(.leading, 70) }
                }
            }.background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
        }.disabled(model.locksDraft)
    }

    private func avatar(_ row: ShareRecipient) -> some View {
        Image(row.session.agent == "codex" ? "agent-codex" : "agent-claude")
            .resizable().scaledToFit().frame(width: 25, height: 25)
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemGroupedBackground), in: Circle())
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(statusColor(row)).frame(width: 10, height: 10)
                    .overlay { Circle().stroke(Color(.tertiarySystemBackground), lineWidth: 2) }
            }.accessibilityHidden(true)
    }
    private func statusColor(_ row: ShareRecipient) -> Color {
        if !row.isReachable || row.session.prompt != nil || row.session.isBlocked { return .orange }
        if row.session.closed { return .secondary }
        return row.session.busy == true ? .green : .secondary
    }
    private func check(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 26, weight: .regular)).foregroundStyle(selected ? accent : Color(.tertiaryLabel))
            .accessibilityHidden(true)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.files.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.files) { file in ShareAttachmentPreview(file: file, url: model.spool.fileURL(jobID: model.inputID, file: file)) }
                    }
                }.frame(maxHeight: 72).accessibilityIdentifier("share_attachment_preview")
            } else if let url = model.text.split(whereSeparator: \.isWhitespace).compactMap({ URL(string: String($0)) }).first(where: { ["https", "http"].contains($0.scheme ?? "") }) {
                HStack(spacing: 10) {
                    Image(systemName: "link").font(.title2).frame(width: 42, height: 42).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.previewTitle ?? url.host ?? "Link").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(url.host ?? url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.accessibilityIdentifier("share_link_preview")
            }
            TextField("Add a message", text: $model.text, axis: .vertical)
                .lineLimit(1...5).focused($editing)
                .padding(12).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityIdentifier("share_message").disabled(model.locksDraft)
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "arrow.turn.up.right").padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.recipientTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(model.effect).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    editing = false
                    Task { await model.send() }
                } label: {
                    if model.sending { ProgressView() }
                    else { Text(model.delivery?.status == .failed ? "Retry" : "Send").font(.body.weight(.semibold)) }
                }
                .buttonStyle(.plain).foregroundStyle(accent).frame(minWidth: 44, minHeight: 44)
                .disabled(!model.canSend).opacity(model.canSend || model.sending ? 1 : 0.4)
                .accessibilityIdentifier("share_send")
            }.accessibilityIdentifier("share_send_effect")
            if let job = model.delivery {
                deliveryStatus(job)
            }

        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .background(Color(.tertiarySystemBackground))
        .accessibilityIdentifier("share_composer")
    }

    @ViewBuilder private func deliveryStatus(_ job: ShareJob) -> some View {
        switch job.status {
        case .sent:
            Label(model.confirmation, systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(.green).accessibilityIdentifier("share_sent")
        case .queued:
            Label("Saved on this device. Open LFG to send when \(job.host.label) is back.", systemImage: "clock")
                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("share_queued")
        case .failed:
            Text(job.error ?? "Not sent. Try again.").font(.footnote).foregroundStyle(.red).accessibilityIdentifier("share_failed")
        case .uncertain:
            Text("Delivery is unconfirmed. Open LFG and check the session before sending again.")
                .font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("share_uncertain")
        default: EmptyView()
        }
    }

    private var options: some View {
        NavigationStack {
            Form {
                Picker("Computer", selection: $model.hostID) {
                    ForEach(model.configuration.hosts) { Text($0.label).tag($0.id) }
                }.accessibilityIdentifier("share_host")
                Picker("Agent", selection: $model.agent) {
                    Text("Claude Code").tag("claude"); Text("Codex").tag("codex")
                }.accessibilityIdentifier("share_agent")
                Section("Folder on this computer") {
                    TextField("Absolute path", text: $model.cwd).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("share_folder")
                    ForEach(Array(Set(model.configuration.recentDirs + model.directories)).sorted(), id: \.self) { path in
                        Button { model.cwd = path } label: {
                            HStack { Text(path).font(.subheadline); Spacer(); if model.cwd == path { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("share_folder_\(path)")
                    }
                }
            }
            .navigationTitle("New session").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.showingOptions = false }.accessibilityIdentifier("share_options_done")
                }
            }
            .task(id: model.hostID) { await model.loadDirectories() }
            .onChange(of: model.hostID) { _, _ in model.cwd = "" }
        }.presentationDetents([.medium, .large])
    }
}

private struct ShareAttachmentPreview: View {
    let file: ShareFile
    let url: URL
    var body: some View {
        HStack(spacing: 8) {
            if file.contentType.hasPrefix("image/"), let image = thumbnail {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 60, height: 60).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: file.contentType == "application/pdf" ? "doc.richtext" : "doc")
                    .font(.title2).frame(width: 40, height: 55)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(file.filename).font(.caption.weight(.medium)).lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: 150, alignment: .leading)
        }.padding(6).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
    private var thumbnail: UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
