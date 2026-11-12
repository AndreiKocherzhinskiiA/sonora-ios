import Foundation

/// Home shelves, library playlists and playlist pages: the browse side of the desktop `parse`
/// module, as an extension of the search parser.
extension YouTubeParser {
    private static let badge = "MUSIC_EXPLICIT_BADGE"

    // MARK: Shelves

    /// A card of a home shelf: a playlist or album it leads to, or a song with a play button.
    /// Artist cards are left out, since the app has no artist page yet.
    static func shelfItem(_ node: JSON) -> YouTubeItem? {
        if let playlist = twoRowPlaylist(node) { return .playlist(playlist) }
        if let album = twoRowAlbum(node) { return .album(album) }
        let target = node["musicTwoRowItemRenderer"].at("navigationEndpoint", "browseEndpoint", "browseId").string
        if target?.hasPrefix("UC") == true { return nil }
        if let track = track(node) ?? twoRowTrack(node) { return .track(track) }
        return nil
    }

    /// The titled carousels of a home response, in the order YouTube lists them.
    static func shelves(in response: JSON) -> [YouTubeShelf] {
        response.find("musicCarouselShelfRenderer").map { shelf in
            YouTubeShelf(
                title: shelf.at("header", "musicCarouselShelfBasicHeaderRenderer", "title").runText ?? "",
                items: shelf["contents"].array.compactMap(shelfItem)
            )
        }
    }

    /// The token for the next lot of home shelves.
    static func continuation(in response: JSON) -> String? {
        response.find("nextContinuationData").compactMap { $0["continuation"].string }.first
    }

    // MARK: Cards

    static func twoRowPlaylist(_ node: JSON) -> Playlist? {
        let renderer = node["musicTwoRowItemRenderer"].exists ? node["musicTwoRowItemRenderer"] : node
        guard let browse = renderer.at("navigationEndpoint", "browseEndpoint", "browseId").string,
              browse.hasPrefix("VL"), let title = renderer["title"].runText else { return nil }
        let parts = (renderer["subtitle"].runText ?? "").components(separatedBy: " • ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let owner = parts.filter { $0 != "Playlist" && songCount(in: $0) == nil }.joined(separator: " • ")
        return Playlist(
            id: String(browse.dropFirst(2)),
            title: title,
            owner: owner,
            artworkURL: cardCover(in: renderer),
            trackCount: parts.compactMap(songCount(in:)).first ?? 0
        )
    }

    static func twoRowAlbum(_ node: JSON) -> Album? {
        let renderer = node["musicTwoRowItemRenderer"].exists ? node["musicTwoRowItemRenderer"] : node
        guard let browse = renderer.at("navigationEndpoint", "browseEndpoint", "browseId").string,
              browse.hasPrefix("MPR") || browse.hasPrefix("FEmusic_library"),
              let title = renderer["title"].runText else { return nil }
        let runs = renderer["subtitle"]["runs"].array
        let linked = runs.compactMap { run -> String? in
            let id = run.at("navigationEndpoint", "browseEndpoint", "browseId").string
            return id?.hasPrefix("UC") == true ? run["text"].string : nil
        }
        let texts = runs.compactMap { $0["text"].string }
        let labels: Set<String> = ["Album", "Single", "EP", "Compilation", " • ", ", ", " & "]
        let year = texts.compactMap { text -> Int? in
            guard text.count == 4, let value = Int(text), (1900...2100).contains(value) else { return nil }
            return value
        }.first
        let names = linked.isEmpty ? texts.filter { !labels.contains($0) && Int($0) == nil } : linked
        return Album(
            id: browse,
            title: title,
            artists: names.joined(separator: ", "),
            artworkURL: cardCover(in: renderer),
            year: year ?? 0,
            trackCount: 0
        )
    }

    /// A song or video card that plays rather than browses.
    static func twoRowTrack(_ node: JSON) -> Track? {
        let renderer = node["musicTwoRowItemRenderer"]
        guard renderer.exists else { return nil }
        let page = renderer.at(
            "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
            "browseEndpointContextMusicConfig", "pageType"
        ).string
        if page == "MUSIC_PAGE_TYPE_ALBUM" || page == "MUSIC_PAGE_TYPE_PLAYLIST" { return nil }
        guard let videoID = renderer.at(
            "thumbnailOverlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer",
            "playNavigationEndpoint", "watchEndpoint", "videoId"
        ).string, let title = renderer["title"].runText else { return nil }

        let runs = renderer["subtitle"]["runs"].array
        let linked = runs.compactMap { run -> ArtistReference? in
            guard let id = run.at("navigationEndpoint", "browseEndpoint", "browseId").string,
                  id.hasPrefix("UC"), let name = run["text"].string else { return nil }
            return ArtistReference(name: name, id: id)
        }
        let skipped: Set<String> = [", ", " & ", "Song", "Video"]
        let plain = runs.compactMap { $0["text"].string }
            .prefix { $0 != " • " }
            .filter { !skipped.contains($0) && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { ArtistReference(name: $0, id: nil) }
        let artists = linked.isEmpty ? plain : linked
        return Track(
            title: title,
            artists: artists.map(\.name).joined(separator: ", "),
            artistReferences: artists,
            artworkURL: cardCover(in: renderer),
            explicit: renderer.find("musicInlineBadgeRenderer").contains { $0.at("icon", "iconType").string == badge },
            source: .youtube(videoID)
        )
    }

    // MARK: Library and pages

    /// The playlists of the library page, without the liked songs, which the app lists itself.
    static func libraryPlaylists(in response: JSON) -> [Playlist] {
        response.find("musicTwoRowItemRenderer")
            .compactMap(twoRowPlaylist)
            .filter { $0.id != "LM" && $0.id != "SE" }
    }

    /// The songs of a playlist or album page, or of one of its continuations.
    static func listTracks(in response: JSON) -> [Track] {
        var items = response.find("musicPlaylistShelfRenderer").flatMap { $0["contents"].array }
        if items.isEmpty { items = response.find("musicShelfRenderer").flatMap { $0["contents"].array } }
        if items.isEmpty {
            items = response.find("appendContinuationItemsAction").flatMap { $0["continuationItems"].array }
            let continued = response.find("musicPlaylistShelfContinuation") + response.find("musicShelfContinuation")
            items += continued.flatMap { $0["contents"].array }
        }
        return items.compactMap(track)
    }

    /// The token for the next page of a playlist.
    static func nextPage(in response: JSON) -> String? {
        let shelves = response.find("musicPlaylistShelfRenderer") + response.find("musicShelfRenderer")
            + response.find("musicPlaylistShelfContinuation") + response.find("musicShelfContinuation")
        for shelf in shelves {
            if let token = shelf.at("continuations", "0", "nextContinuationData", "continuation").string {
                return token
            }
        }
        return response.find("continuationItemRenderer")
            .compactMap { $0.at("continuationEndpoint", "continuationCommand", "token").string }
            .first
    }

    // MARK: Helpers

    /// `12 songs` as 12, and nil for any other text.
    private static func songCount(in text: String) -> Int? {
        let words = text.split(separator: " ")
        guard words.count >= 2, words[1].hasPrefix("song") || words[1].hasPrefix("track") else { return nil }
        return Int(words[0].replacingOccurrences(of: ",", with: ""))
    }

    /// A thumbnail wide enough for a card: the first at 300 pixels or more, else the widest.
    private static func cardCover(in node: JSON) -> URL? {
        let list = (node.find("thumbnails").first?.array ?? [])
            .sorted { ($0["width"].int ?? 0) < ($1["width"].int ?? 0) }
        let pick = list.first { ($0["width"].int ?? 0) >= 300 } ?? list.last
        return pick?["url"].string.flatMap(URL.init(string:))
    }
}
