import Foundation

/// Artist pages, search filters, the library's albums and artists, and radio panels: the rest of the
/// desktop `parse` and `browse` modules.
extension YouTubeParser {
    // MARK: Artists

    static func artist(in response: JSON, id: String) -> YouTubeArtist? {
        let header = ["musicImmersiveHeaderRenderer", "musicVisualHeaderRenderer", "musicHeaderRenderer"]
            .lazy.compactMap { response.find($0).first }.first
        guard let header else { return nil }
        let name = header["title"].runText ?? ""
        let description = header["description"].runText
            ?? response.find("musicDescriptionShelfRenderer").first?["description"].runText
        let subscribers = header.at("subscriptionButton", "subscribeButtonRenderer", "subscriberCountText").runText
            ?? header["subscriptionButton"]["subscribeButtonRenderer"]["subscriberCountText"].runText

        let top = (response.find("musicShelfRenderer").first?["contents"].array ?? []).compactMap(track)
        var albums: [Album] = []
        var singles: [Album] = []
        for carousel in response.find("musicCarouselShelfRenderer") {
            let label = carousel.at("header", "musicCarouselShelfBasicHeaderRenderer", "title").runText ?? ""
            let found = carousel["contents"].array.compactMap(twoRowAlbum)
            switch label {
            case "Albums": albums += found
            case "Singles", "Singles & EPs", "Singles and EPs": singles += found
            default: break
            }
        }
        // An artist's own page leaves the artist out of each release's subtitle.
        func credited(_ list: [Album]) -> [Album] {
            list.map { album in
                var album = album
                if album.artists.isEmpty { album.artists = name }
                return album
            }
        }
        return YouTubeArtist(
            id: id,
            name: name,
            description: description?.isEmpty == false ? description : nil,
            subscribers: subscribers,
            artworkURL: widest(in: header),
            topTracks: top,
            albums: credited(albums),
            singles: credited(singles)
        )
    }

    /// Artists from the library page or a search, whatever renderer they come in.
    static func artists(in response: JSON) -> [SavedArtist] {
        let renderers = response.find("musicTwoRowItemRenderer") + response.find("musicResponsiveListItemRenderer")
        return renderers.compactMap { renderer -> SavedArtist? in
            let first = renderer.at("flexColumns", "0", "musicResponsiveListItemFlexColumnRenderer", "text")
            guard let id = renderer.at("navigationEndpoint", "browseEndpoint", "browseId").string
                    ?? first.at("runs", "0", "navigationEndpoint", "browseEndpoint", "browseId").string,
                  id.hasPrefix("UC"),
                  let name = renderer["title"].runText ?? first.runText else { return nil }
            return SavedArtist(id: id, name: name, artworkURL: widest(in: renderer))
        }
    }

    // MARK: Albums and playlists

    static func libraryAlbums(in response: JSON) -> [Album] {
        response.find("musicTwoRowItemRenderer").compactMap(twoRowAlbum)
    }

    /// Albums from a search for albums, which come as list rows rather than cards.
    static func searchAlbums(in response: JSON) -> [Album] {
        response.find("musicShelfRenderer").flatMap { $0["contents"].array }.compactMap { item in
            let renderer = item["musicResponsiveListItemRenderer"]
            guard renderer.exists, pageType(of: renderer) == "MUSIC_PAGE_TYPE_ALBUM",
                  let id = renderer.at("navigationEndpoint", "browseEndpoint", "browseId").string else { return nil }
            let columns = renderer["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"] }
            guard let title = columns.first?["text"].runText else { return nil }
            let texts = (columns.dropFirst().first?["text"]["runs"].array ?? []).compactMap { $0["text"].string }
            let labels: Set<String> = ["Album", "Single", "EP", "Compilation", " • ", ", ", " & "]
            let year = texts.compactMap { Int($0) }.first { (1900...2100).contains($0) } ?? 0
            let names = texts.filter { !labels.contains($0) && Int($0) == nil }
            return Album(
                id: id, title: title, artists: names.joined(separator: ", "),
                artworkURL: widest(in: renderer), year: year, trackCount: 0
            )
        }
    }

    static func searchPlaylists(in response: JSON) -> [Playlist] {
        response.find("musicShelfRenderer").flatMap { $0["contents"].array }.compactMap { item in
            let renderer = item["musicResponsiveListItemRenderer"]
            guard renderer.exists, pageType(of: renderer) == "MUSIC_PAGE_TYPE_PLAYLIST",
                  let browse = renderer.at("navigationEndpoint", "browseEndpoint", "browseId").string else { return nil }
            let columns = renderer["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"] }
            guard let title = columns.first?["text"].runText else { return nil }
            let texts = (columns.dropFirst().first?["text"]["runs"].array ?? []).compactMap { $0["text"].string }
            let owner = texts.first { $0 != " • " && !$0.hasPrefix("Playlist") && !$0.contains("song") && !$0.contains("view") } ?? ""
            return Playlist(
                id: browse.hasPrefix("VL") ? String(browse.dropFirst(2)) : browse,
                title: title, owner: owner, artworkURL: widest(in: renderer), trackCount: 0
            )
        }
    }

    static func searchArtists(in response: JSON) -> [SavedArtist] {
        response.find("musicShelfRenderer").flatMap { $0["contents"].array }.flatMap { artists(in: $0) }
    }

    // MARK: Radio

    /// The songs of a radio panel and the token that continues the station.
    static func radio(in response: JSON, continued: Bool) -> (tracks: [Track], next: String?) {
        let key = continued ? "playlistPanelContinuation" : "playlistPanelRenderer"
        guard let panel = response.find(key).first else { return ([], nil) }
        let tracks = panel["contents"].array.compactMap(panelTrack)
        let next = panel["continuations"].array
            .compactMap { $0.at("nextRadioContinuationData", "continuation").string }
            .first
        return (tracks, next)
    }

    private static func panelTrack(_ item: JSON) -> Track? {
        let wrapper = item.at("playlistPanelVideoWrapperRenderer", "primaryRenderer", "playlistPanelVideoRenderer")
        let renderer = item["playlistPanelVideoRenderer"].exists
            ? item["playlistPanelVideoRenderer"]
            : (wrapper.exists ? wrapper : item)
        guard let videoID = renderer["videoId"].string, let title = renderer["title"].runText else { return nil }
        let runs = renderer["longBylineText"]["runs"].array
        var artists: [ArtistReference] = []
        var album = ""
        var albumID: String?
        for run in runs {
            guard let name = run["text"].string,
                  let id = run.at("navigationEndpoint", "browseEndpoint", "browseId").string else { continue }
            if id.hasPrefix("UC") {
                artists.append(ArtistReference(name: name, id: id))
            } else if id.hasPrefix("MPR"), album.isEmpty {
                album = name
                albumID = id
            }
        }
        if artists.isEmpty, let name = runs.first?["text"].string {
            artists = [ArtistReference(name: name, id: nil)]
        }
        let clock = renderer["lengthText"].runText
        let seconds = clock.map { $0.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 } } ?? 0
        return Track(
            title: title,
            artists: artists.map(\.name).joined(separator: ", "),
            artistReferences: artists,
            album: album,
            albumID: albumID,
            artworkURL: widest(in: renderer),
            duration: TimeInterval(seconds),
            source: .youtube(videoID)
        )
    }

    // MARK: Helpers

    private static func pageType(of renderer: JSON) -> String? {
        renderer.at(
            "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
            "browseEndpointContextMusicConfig", "pageType"
        ).string
    }

    private static func widest(in node: JSON) -> URL? {
        let list = node.find("thumbnails").first?.array ?? []
        let best = list.max { ($0["width"].int ?? 0) < ($1["width"].int ?? 0) }
        return best?["url"].string.flatMap(URL.init(string:))
    }
}
