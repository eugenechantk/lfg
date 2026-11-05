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
            .background(SharePalette.list.ignoresSafeArea())
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
            TextField("Search sessions and chats", text: $model.query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("share_search")
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear search").accessibilityIdentifier("share_search_clear")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(SharePalette.search, in: Capsule())
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
                if !sections.recent.isEmpty { recipientSection("Recent", rows: sections.recent, id: "recent") }
                // Sessions first; chats keep their own section after them.
                if !sections.sessions.isEmpty { recipientSection(model.query.isEmpty ? "All sessions" : "Sessions", rows: sections.sessions, id: "sessions") }
                if !sections.chats.isEmpty { recipientSection("Chats", rows: sections.chats, id: "chats") }
                if sections.isEmpty {
                    ContentUnavailableView(model.query.isEmpty ? "No sessions yet" : "No matching sessions or chats", systemImage: "bubble.left.and.bubble.right",
                                           description: Text(model.query.isEmpty ? "Choose New session to start one with this share." : "Try a title, folder, chat name or computer name."))
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
        .padding(12).background(SharePalette.card, in: RoundedRectangle(cornerRadius: 22))
        .disabled(model.locksDraft)
    }

    private func recipientSection(_ title: String, rows: [ShareRecipient], id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 12)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("share_section_\(id)")
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
            }.background(SharePalette.card, in: RoundedRectangle(cornerRadius: 22))
        }.disabled(model.locksDraft)
    }

    private func avatar(_ row: ShareRecipient) -> some View {
        Image(row.session.agent == "codex" ? "agent-codex" : "agent-claude")
            .resizable().scaledToFit().frame(width: 25, height: 25)
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemGroupedBackground), in: Circle())
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(statusColor(row)).frame(width: 10, height: 10)
                    .overlay { Circle().stroke(SharePalette.card, lineWidth: 2) }
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

    /// The send panel is its own lighter surface, like the reference share
    /// sheet: a full-width preview strip, then an outlined text field filled
    /// with the list colour, then who gets it and Send.
    private var composer: some View {
        VStack(spacing: 0) {
            preview
            VStack(alignment: .leading, spacing: 10) {
                TextField("Add a message", text: $model.text, axis: .vertical)
                    .lineLimit(1...5).focused($editing)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(SharePalette.field, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(SharePalette.fieldBorder, lineWidth: 1) }
                    .accessibilityIdentifier("share_message").disabled(model.locksDraft)
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "arrow.turn.up.right").padding(.top, 2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.recipientTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(model.effect).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        editing = false
                        Task { await model.send() }
                    } label: {
                        // A filled button, not a text link: the one action in the panel.
                        Group {
                            if model.sending { ProgressView().tint(.white) }
                            else { Text(model.delivery?.status == .failed ? "Retry" : "Send").font(.body.weight(.semibold)) }
                        }
                        .foregroundStyle(.white)
                        .frame(minWidth: 52, minHeight: 44)
                        .padding(.horizontal, 18)
                        .background(accent, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSend).opacity(model.canSend || model.sending ? 1 : 0.4)
                    .accessibilityIdentifier("share_send")
                }.accessibilityIdentifier("share_send_effect")
                if let job = model.delivery {
                    deliveryStatus(job)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        }
        .background(SharePalette.panel)
        .overlay(alignment: .top) { Rectangle().fill(SharePalette.edge).frame(height: 0.5) }
        .accessibilityIdentifier("share_composer")
    }

    @ViewBuilder private var preview: some View {
        if !model.files.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.files) { file in ShareAttachmentPreview(file: file, url: model.spool.fileURL(jobID: model.inputID, file: file)) }
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }
            .frame(maxHeight: 80)
            .overlay(alignment: .bottom) { Rectangle().fill(SharePalette.edge).frame(height: 0.5) }
            .accessibilityIdentifier("share_attachment_preview")
        } else if let url = model.text.split(whereSeparator: \.isWhitespace).compactMap({ URL(string: String($0)) }).first(where: { ["https", "http"].contains($0.scheme ?? "") }) {
            HStack(spacing: 12) {
                Image(systemName: "link").font(.title2).foregroundStyle(.secondary)
                    .frame(width: 64, height: 64).background(SharePalette.thumbnail)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.previewTitle ?? url.host ?? "Link").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(url.host ?? url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(SharePalette.edge).frame(height: 0.5) }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("share_link_preview")
        }
    }

    @ViewBuilder private func deliveryStatus(_ job: ShareJob) -> some View {
        switch job.status {
        case .sent:
            Label(model.confirmation, systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(.green).accessibilityIdentifier("share_sent")
        case .queued:
            Label(job.waitsForTurn == true ? "Queued. LFG sends it after this chat’s current turn." :
                    "Saved on this device. Open LFG to send when \(job.host.label) is back.", systemImage: "clock")
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

/// Three surface levels, as in the reference: list, cards, then a lighter
/// send panel whose text field drops back to the list colour.
private enum SharePalette {
    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
    static let panel = dynamic(dark: 0x48484A, light: 0xE5E5EA)
    static let field = dynamic(dark: 0x1C1C1E, light: 0xFFFFFF)
    static let fieldBorder = dynamic(dark: 0x636366, light: 0xC7C7CC)
    static let thumbnail = dynamic(dark: 0x3A3A3C, light: 0xD1D1D6)
    static let edge = dynamic(dark: 0x636366, light: 0xC7C7CC)
    // The sheet sits darker than the cards so the search pill and the cards
    // both read as raised (reference: sheet #161717, cards #242626, pill #404141).
    static let list = dynamic(dark: 0x111113, light: 0xF2F2F7)
    // Fixed, not tertiarySystemBackground: in a sheet that lifts to #3A3A3C
    // and matches the search pill.
    static let card = dynamic(dark: 0x2C2C2E, light: 0xFFFFFF)
    static let search = dynamic(dark: 0x3A3A3C, light: 0xE3E3E8)
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
