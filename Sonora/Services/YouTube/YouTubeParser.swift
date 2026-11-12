import Foundation

/// Reads songs out of YouTube Music responses, the Swift form of `parse::list_item_track`.
enum YouTubeParser {
    private static let explicitBadge = "MUSIC_EXPLICIT_BADGE"

    /// The songs of every `musicShelfRenderer` in a search response.
    static func songs(in response: JSON) -> [Track] {
        response.find("musicShelfRenderer")
            .flatMap { $0["contents"].array }
            .compactMap(track)
    }

    /// A song row, or nil for one without a video id, which cannot be played.
    static func track(_ item: JSON) -> Track? {
        let renderer = item["musicResponsiveListItemRenderer"].exists
            ? item["musicResponsiveListItemRenderer"] : item
        let columns = renderer["flexColumns"].array
            .map { $0["musicResponsiveListItemFlexColumnRenderer"] }
            .filter(\.exists)
        guard let first = columns.first, let title = first["text"].runText else { return nil }

        let videoID = renderer.at("playlistItemData", "videoId").string
            ?? first.at("text", "runs", "0", "navigationEndpoint", "watchEndpoint", "videoId").string
            ?? renderer.at(
                "overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer",
                "playNavigationEndpoint", "watchEndpoint", "videoId"
            ).string
        guard let videoID else { return nil }

        var artists: [ArtistReference] = []
        var album = ""
        var albumID: String?
        for column in columns.dropFirst() {
            let runs = column["text"]["runs"].array
            for run in runs {
                guard let name = run["text"].string,
                      let id = browseID(of: run) else { continue }
                if id.hasPrefix("UC") {
                    artists.append(ArtistReference(name: name, id: id))
                } else if id.hasPrefix("MPR"), album.isEmpty {
                    album = name
                    albumID = id
                }
            }
        }
        if artists.isEmpty, columns.count > 1 {
            artists = plainArtists(columns[1]["text"]["runs"].array)
        }

        let clock = renderer["fixedColumns"][0]
            .at("musicResponsiveListItemFixedColumnRenderer", "text").runText
            ?? columns.dropFirst().lazy.compactMap { column in
                column["text"]["runs"].array.compactMap { $0["text"].string }.first(where: isClock)
            }.first

        return Track(
            title: title,
            artists: artists.map(\.name).joined(separator: ", "),
            artistReferences: artists,
            album: album,
            albumID: albumID,
            artworkURL: thumbnail(in: renderer),
            duration: clock.flatMap(seconds) ?? 0,
            explicit: renderer.find("musicInlineBadgeRenderer")
                .contains { $0.at("icon", "iconType").string == explicitBadge },
            source: .youtube(videoID)
        )
    }

    private static func browseID(of run: JSON) -> String? {
        run.at("navigationEndpoint", "browseEndpoint", "browseId").string
    }

    /// Artists named only by text, up to the first run that looks like a duration.
    private static func plainArtists(_ runs: [JSON]) -> [ArtistReference] {
        var artists: [ArtistReference] = []
        for run in runs {
            let text = run["text"].string ?? ""
            if ["", " • ", ", ", " & "].contains(text) { continue }
            if isClock(text) { break }
            artists.append(ArtistReference(name: text, id: browseID(of: run)))
        }
        return artists
    }

    private static func isClock(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ":") }
    }

    /// `3:45` or `1:02:03` as seconds.
    private static func seconds(_ clock: String) -> TimeInterval? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        return TimeInterval(parts.reduce(0) { $0 * 60 + $1 })
    }

    /// The widest thumbnail under a node.
    private static func thumbnail(in node: JSON) -> URL? {
        let list = node.find("thumbnails").first?.array ?? []
        let widest = list.max { ($0["width"].int ?? 0) < ($1["width"].int ?? 0) }
        return widest?["url"].string.flatMap(URL.init(string:))
    }
}
