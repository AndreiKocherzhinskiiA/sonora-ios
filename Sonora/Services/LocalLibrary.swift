import AVFoundation
import Foundation
import Observation
import os

@Observable
final class LocalLibrary {
    private(set) var tracks: [Track] = []
    private(set) var isImporting = false
    var errorMessage: String?

    @ObservationIgnored private let logger = Logger(subsystem: "org.sonorahq.sonora", category: "library")
    @ObservationIgnored private let fileManager = FileManager.default

    private var libraryURL: URL {
        applicationSupportURL.appending(path: "library.json")
    }

    private var mediaURL: URL {
        applicationSupportURL.appending(path: "Media", directoryHint: .isDirectory)
    }

    private var applicationSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Sonora", directoryHint: .isDirectory)
    }

    func restore() async {
        do {
            let data = try Data(contentsOf: libraryURL)
            tracks = try JSONDecoder().decode([Track].self, from: data)
                .map(rebased)
                .filter { fileManager.fileExists(atPath: $0.sourceURL.path(percentEncoded: false)) }
            sweepOrphans()
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            tracks = []
        } catch {
            logger.error("cannot restore local library: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "The local library could not be restored.")
        }
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            try fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
            for sourceURL in urls {
                try Task.checkCancellation()
                let gainedAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if gainedAccess { sourceURL.stopAccessingSecurityScopedResource() }
                }

                let destination = uniqueDestination(for: sourceURL)
                try fileManager.copyItem(at: sourceURL, to: destination)
                tracks.append(await track(for: destination))
            }
            tracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            try persist()
        } catch is CancellationError {
            return
        } catch {
            logger.error("cannot import audio: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "One or more songs could not be imported.")
        }
    }

    /// Takes a song out of the library but keeps its file, so `restore` can put it back. Call
    /// `purge` once the removal is final. Returns where the song was, or nil if it was not there.
    @discardableResult
    func remove(_ track: Track) -> Int? {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return nil }
        tracks.remove(at: index)
        save()
        return index
    }

    /// Puts a removed song back where it was, as near as the list has since changed.
    func restore(_ track: Track, at index: Int) {
        guard !tracks.contains(where: { $0.id == track.id }),
              fileManager.fileExists(atPath: track.sourceURL.path(percentEncoded: false)) else { return }
        tracks.insert(track, at: min(index, tracks.count))
        save()
    }

    /// Deletes the file of a song whose removal was not undone.
    func purge(_ track: Track) {
        guard !tracks.contains(where: { $0.id == track.id }) else { return }
        try? fileManager.removeItem(at: track.sourceURL)
    }

    /// Deletes imported files no song refers to, left behind when the app quit before a removal
    /// was final.
    private func sweepOrphans() {
        let known = Set(tracks.map { $0.sourceURL.standardizedFileURL })
        let files = (try? fileManager.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil)) ?? []
        for file in files where !known.contains(file.standardizedFileURL) {
            try? fileManager.removeItem(at: file)
        }
    }

    /// The app's container moves on every install, so a saved file path is re-read against the
    /// current Media folder. Without this a reinstall drops every song and sweeps its file.
    private func rebased(_ track: Track) -> Track {
        guard case .local(let url) = track.source else { return track }
        var moved = track
        moved.source = .local(mediaURL.appending(path: url.lastPathComponent))
        return moved
    }

    private func save() {
        do {
            try persist()
        } catch {
            logger.error("cannot save local library: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "The local library could not be saved.")
        }
    }

    private func uniqueDestination(for sourceURL: URL) -> URL {
        let extensionName = sourceURL.pathExtension
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let suffix = extensionName.isEmpty ? "" : ".\(extensionName)"
        let filename = "\(stem)-\(UUID().uuidString)\(suffix)"
        return mediaURL.appending(path: filename)
    }

    private func track(for url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        let title = await metadata.string(for: .commonIdentifierTitle)
        let artist = await metadata.string(for: .commonIdentifierArtist)
        let album = await metadata.string(for: .commonIdentifierAlbumName)

        return Track(
            title: title ?? url.deletingPathExtension().lastPathComponent,
            artists: artist ?? "",
            artistReferences: artist.map { [ArtistReference(name: $0, id: nil)] } ?? [],
            album: album ?? "",
            duration: duration.isFinite ? duration : 0,
            source: .local(url)
        )
    }

    private func persist() throws {
        try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(tracks)
        try data.write(to: libraryURL, options: .atomic)
    }
}

private extension Array where Element == AVMetadataItem {
    func string(for identifier: AVMetadataIdentifier) async -> String? {
        guard let item = first(where: { $0.identifier == identifier }) else { return nil }
        return try? await item.load(.stringValue)
    }
}

