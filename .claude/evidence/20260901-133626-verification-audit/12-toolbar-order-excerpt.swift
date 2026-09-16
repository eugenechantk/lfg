        } action: { width in
            if width != windowWidth { windowWidth = width }
        }
        // Hand every keystroke to the store, which debounces and asks the hosts.
        // Filtering `store.items` alone can't answer "search all my sessions" —
        // it only ever sees each host's newest 100 closed rows.
        .onChange(of: searchText) { _, q in store.setSearchQuery(q) }
        .navigationTitle("")
        // HIG "Toolbars" item groupings: common view controls in the center
        // area, search + actions on the trailing edge.
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    DesktopConnectionStatusBar(compact: !showsHostLabels)
                    // Center/trailing controls are macOS's first overflow
                    // victims in compact windows. Keep the primary creation
                    // action in the preserved leading cluster instead.
                    if isCompactToolbar { createSessionButton }
                }
            }
            .sharedBackgroundVisibility(.hidden)
            // A centered item costs twice the wider side's width in reserved
            // space, which a narrow window can't spare — so in compact the
            // grouping control joins the trailing cluster instead.
            if !isCompactToolbar {
                ToolbarItem(placement: .principal) {
                    groupPicker
                }
            }
            if isCompactToolbar {
                ToolbarItem(placement: .primaryAction) {
                    groupPicker
                }
                .sharedBackgroundVisibility(.hidden)
            }
            // A display control, so it sits beside the grouping control rather
            // than in Settings, and it is also the feature's disclosure — a
            // filter you can't see is one you forget you set. Only in the
            // full-size toolbar: compact has no room for a fifth item, so it
            // reaches the same panel through the grouping menu.
            if !isCompactToolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showDirectoryFilter.toggle()
                    } label: {
                        Image(systemName: store.hiddenLiveCount > 0 ? "eye.slash.fill" : "eye.slash")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help(directoryFilterLabel)
                    .accessibilityIdentifier("directory_filter_button")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
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
            }
            // Adjacent items in one placement share a glass capsule by
            // default; hide it so refresh is its own circle beside search.
            .sharedBackgroundVisibility(.hidden)
            if isCompactToolbar {
                ToolbarItem(placement: .primaryAction) {
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
                    .help(compactSearchShown ? "Hide search" : "Search sessions")
                    .accessibilityIdentifier("compact_search_toggle")
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search sessions", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    // 150pt (not wider): at the 640pt minWidth the centered
                    // pill + this cluster must fit without collapsing into ».
                    // No custom glass here — the system toolbar item background
                    // is the only container around the field.
                    .frame(width: 150, height: 30)
                }
            }
            if !isCompactToolbar {
                // Mirrors iOS's search-then-plus reading order when there is
