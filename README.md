# Album Cleaner (`EmptyAlbumCleaner`)

An iOS 17+ SwiftUI app that scans your Apple Photos library using PhotoKit to find and safely delete empty user-created albums and empty folders—without ever modifying or deleting your photos.

## Safety & Behavior

- **Full Photo Library Access Required:** Refuses limited photo access so albums don't falsely appear empty when only a subset of photos is visible to the app.
- **Hidden Asset Check:** Performs an explicit asset fetch including hidden items (`includeHiddenAssets = true`) before treating an album as empty.
- **Completely Empty Folders Only:** Only lists folders with zero child collections, preventing accidental removal of folders that still contain albums.
- **Pre-Delete Re-Validation:** Re-fetches and re-verifies emptiness right before deletion, submitting a single PhotoKit change request so iOS displays one confirmation prompt.

## Requirements

- Xcode 16+
- iOS 17.0+

## Getting Started

1. Open `EmptyAlbumCleaner.xcodeproj` in Xcode.
2. Select the `EmptyAlbumCleaner` target and choose your **Development Team** under **Signing & Capabilities**.
3. Build and run on a simulator or iOS device.
