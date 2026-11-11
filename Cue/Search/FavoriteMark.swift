import SonosKit
import SwiftUI

/// The mark after a favorite's title: a star for Apple Music, a heart for
/// Plex and Subsonic. Those services carry favorite state on the item (a
/// rating, a starred date, `inFavorites`), so none needs a fetch to know;
/// one changed here shows at once through `FavoriteRatingCache`. Shared by
/// the rows, the cover tiles and the artist tiles, so all three agree, and a
/// view of its own, so a rating changing redraws the mark, not the row.
struct FavoriteMark: View {
    let item: PlayableContent
    var font: Font = .caption

    @Environment(FavoriteRatingCache.self) private var favoriteRatingCache

    private var isFavorite: Bool {
        [.plex, .subsonic, .apple].contains(item.content.service)
            && (favoriteRatingCache.ratings[item.id] ?? item.metadata?.userRating ?? 0) > 0
    }

    var body: some View {
        if isFavorite {
            Image(systemName: item.content.service == .apple ? "star.fill" : "heart.fill")
                .font(font)
                .foregroundStyle(item.content.service.brandColor)
                .accessibilityLabel("Favorite")
        }
    }
}
