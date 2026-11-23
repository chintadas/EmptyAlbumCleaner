import Photos

/// A deletable, empty album or folder discovered in the user's photo library.
struct EmptyCollection: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case album, folder }

    let id: String          // PhotoKit localIdentifier
    let title: String
    let path: String        // Parent folder path, e.g. "Trips / 2019" (empty for top level)
    let kind: Kind
}

struct ScanResult: Sendable {
    var emptyAlbums: [EmptyCollection] = []
    var emptyFolders: [EmptyCollection] = []
    var totalAlbumsScanned = 0
}

enum PhotoLibraryService {

    // MARK: - Authorization

    static var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: - Scanning

    /// Walks every user-created album and folder (including nested ones) and returns those
    /// that are deletable and contain nothing.
    ///
    /// Requires *full* library access: with limited access, PhotoKit only exposes the photos
    /// the user picked, so albums would wrongly look empty.
    static func scan() -> ScanResult {
        var result = ScanResult()
        let topLevel = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        walk(topLevel, path: [], into: &result)

        let sort: (EmptyCollection, EmptyCollection) -> Bool = {
            ordered(($0.path, $0.title), ($1.path, $1.title))
        }
        result.emptyAlbums.sort(by: sort)
        result.emptyFolders.sort(by: sort)
        return result
    }

    private static func walk(_ collections: PHFetchResult<PHCollection>,
                             path: [String],
                             into result: inout ScanResult) {
        for index in 0..<collections.count {
            let collection = collections.object(at: index)
            let title = collection.localizedTitle ?? "Untitled"

            if let album = collection as? PHAssetCollection {
                guard album.assetCollectionType == .album else { continue }
                result.totalAlbumsScanned += 1

                // Skip shared/synced albums and anything PhotoKit says can't be deleted.
                guard album.assetCollectionSubtype == .albumRegular,
                      album.canPerform(.delete),
                      isEmpty(album) else { continue }

                result.emptyAlbums.append(EmptyCollection(
                    id: album.localIdentifier,
                    title: title,
                    path: path.joined(separator: " / "),
                    kind: .album))

            } else if let folder = collection as? PHCollectionList {
                let children = PHCollection.fetchCollections(in: folder, options: nil)

                // Only offer folders that are *completely* empty. Deleting a folder in Photos
                // also deletes the albums inside it, so we never touch non-empty folders.
                if children.count == 0 {
                    if folder.canPerform(.delete) {
                        result.emptyFolders.append(EmptyCollection(
                            id: folder.localIdentifier,
                            title: title,
                            path: path.joined(separator: " / "),
                            kind: .folder))
                    }
                } else {
                    walk(children, path: path + [title], into: &result)
                }
            }
        }
    }

    /// Accurate emptiness check. `estimatedAssetCount` can be stale or `NSNotFound`, and it
    /// ignores hidden items, so we do a real fetch that includes hidden assets.
    private static func isEmpty(_ album: PHAssetCollection) -> Bool {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.fetchLimit = 1
        return PHAsset.fetchAssets(in: album, options: options).count == 0
    }

    // MARK: - Deleting

    /// Deletes the given albums/folders in a single change request, so iOS shows only one
    /// confirmation prompt. Items are re-validated right before deletion.
    static func delete(_ items: [EmptyCollection]) async throws -> Int {
        let albumIDs = items.filter { $0.kind == .album }.map(\.id)
        let folderIDs = items.filter { $0.kind == .folder }.map(\.id)

        // Re-fetch and re-check emptiness in case something changed since the scan.
        var albums: [PHAssetCollection] = []
        if !albumIDs.isEmpty {
            PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: albumIDs, options: nil)
                .enumerateObjects { album, _, _ in
                    if album.canPerform(.delete) && isEmpty(album) { albums.append(album) }
                }
        }

        var folders: [PHCollectionList] = []
        if !folderIDs.isEmpty {
            PHCollectionList.fetchCollectionLists(withLocalIdentifiers: folderIDs, options: nil)
                .enumerateObjects { folder, _, _ in
                    if folder.canPerform(.delete),
                       PHCollection.fetchCollections(in: folder, options: nil).count == 0 {
                        folders.append(folder)
                    }
                }
        }

        guard !albums.isEmpty || !folders.isEmpty else { return 0 }

        try await PHPhotoLibrary.shared().performChanges {
            if !albums.isEmpty {
                PHAssetCollectionChangeRequest.deleteAssetCollections(albums as NSArray)
            }
            if !folders.isEmpty {
                PHCollectionListChangeRequest.deleteCollectionLists(folders as NSArray)
            }
        }
        return albums.count + folders.count
    }
}

private func ordered(_ a: (String, String), _ b: (String, String)) -> Bool {
    let first = a.0.localizedStandardCompare(b.0)
    if first != .orderedSame { return first == .orderedAscending }
    return a.1.localizedStandardCompare(b.1) == .orderedAscending
}
