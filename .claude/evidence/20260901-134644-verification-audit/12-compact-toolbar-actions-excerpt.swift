
    @ViewBuilder
    private var refreshButton: some View {
        let button = Button {
            Task { await store.refresh() }
        } label: {
            if store.refreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(store.refreshing)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help("Refresh (auto-refreshes every 10s)")
        if isCompactToolbar {
            button.controlSize(.mini)
        } else {
            button
        }
    }

    private var compactSearchButton: some View {
        Button {
            compactSearchShown.toggle()
            searchFieldFocused = compactSearchShown
            if !compactSearchShown { searchText = "" }
        } label: {
            Image(systemName: searchText.isEmpty
                  ? "magnifyingglass"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .help(compactSearchShown ? "Hide search" : "Search sessions")
        .accessibilityIdentifier("compact_search_toggle")
    }

    /// AppKit overflows separate trailing toolbar items aggressively at the
    /// 440pt minimum. Treat these as one layout unit while keeping each action
    /// as its own glass circle, so Group, Refresh, and Search survive together.
    private var compactToolbarActions: some View {
        HStack(spacing: 4) {
            groupPicker
