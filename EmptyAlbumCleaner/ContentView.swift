import SwiftUI

struct ContentView: View {
    @State private var model = CleanerViewModel()
    @State private var showConfirm = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Album Cleaner")
                .toolbar { toolbar }
        }
        .task {
            if model.phase == .idle { await model.scan() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Pick up permission changes made in Settings.
            if newPhase == .active {
                Task { await model.refreshAuthorization() }
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .needsPermission:
            PermissionView(
                icon: "photo.on.rectangle.angled",
                title: "Find Empty Albums",
                message: "Album Cleaner scans your albums and folders for ones with nothing in them. It never modifies or deletes your photos.",
                buttonTitle: "Allow Photo Access"
            ) { Task { await model.requestAccess() } }

        case .limitedAccess:
            PermissionView(
                icon: "exclamationmark.lock",
                title: "Full Access Required",
                message: "With limited access, iOS only shows this app the photos you picked, so every album would look empty. Grant “Full Access” in Settings to scan safely.",
                buttonTitle: "Open Settings"
            ) { openSettings() }

        case .denied:
            PermissionView(
                icon: "lock.slash",
                title: "No Photo Access",
                message: "Enable Full Access for Album Cleaner in Settings → Privacy & Security → Photos.",
                buttonTitle: "Open Settings"
            ) { openSettings() }

        case .idle, .scanning:
            ProgressView("Scanning albums…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .deleting:
            ProgressView("Deleting…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .results:
            resultsView
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        if model.allItems.isEmpty {
            ContentUnavailableView {
                Label("No Empty Albums", systemImage: "checkmark.circle")
            } description: {
                VStack(spacing: 8) {
                    if let message = model.lastMessage { Text(message).bold() }
                    Text("Scanned \(model.result.totalAlbumsScanned) albums. Nothing to clean up.")
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                }
            } actions: {
                Button("Scan Again") { Task { await model.scan() } }
            }
        } else {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        if let message = model.lastMessage {
                            Text(message).font(.subheadline.bold()).foregroundStyle(.green)
                        }
                        if let error = model.errorMessage {
                            Text(error).font(.subheadline).foregroundStyle(.red)
                        }
                        Text("Found \(model.allItems.count) empty of \(model.result.totalAlbumsScanned) albums scanned. Deleting an album never deletes photos.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !model.result.emptyAlbums.isEmpty {
                    Section("Empty Albums (\(model.result.emptyAlbums.count))") {
                        ForEach(model.result.emptyAlbums) { row($0) }
                    }
                }

                if !model.result.emptyFolders.isEmpty {
                    Section {
                        ForEach(model.result.emptyFolders) { row($0) }
                    } header: {
                        Text("Empty Folders (\(model.result.emptyFolders.count))")
                    } footer: {
                        Text("Only folders with nothing inside are listed.")
                    }
                }
            }
            .refreshable { await model.scan() }
            .safeAreaInset(edge: .bottom) { deleteBar }
            .confirmationDialog(
                "Delete \(model.selection.count) empty item(s)?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete \(model.selection.count)", role: .destructive) {
                    Task { await model.deleteSelected() }
                }
            } message: {
                Text("Only the empty albums/folders are removed. iOS will ask you to confirm once more.")
            }
        }
    }

    private func row(_ item: EmptyCollection) -> some View {
        Button {
            model.toggle(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(model.selection.contains(item.id) ? Color.accentColor : .secondary)
                Image(systemName: item.kind == .album ? "rectangle.stack" : "folder")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).foregroundStyle(.primary)
                    if !item.path.isEmpty {
                        Text(item.path).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var deleteBar: some View {
        Button(role: .destructive) {
            showConfirm = true
        } label: {
            Label(model.selection.isEmpty ? "Select Albums to Delete" : "Delete \(model.selection.count) Selected",
                  systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(model.selection.isEmpty)
        .padding()
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.phase == .results && !model.allItems.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                if model.selection.count == model.allItems.count {
                    Button("Select None") { model.selectNone() }
                } else {
                    Button("Select All") { model.selectAll() }
                }
            }
        }
        if model.phase == .results {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.scan() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Rescan")
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct PermissionView: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
}
