# Stacker News for Apple Watch

A read-only watchOS client for [stacker.news](https://stacker.news). Stage 1: no login,
no zaps, no posting. Open the app, a post fills the screen, turn the Digital Crown to
move to the next one, tap to read the whole thing. Made for reading a few paragraphs in bed.

## What it does

- **Screens**: up to 6 horizontal pages; swipe left/right between them. Each is either a
  site-wide feed (Hot, Recent, Top this week) or one territory with one sort, so
  `~bitcoin · Hot` and `~bitcoin · Recent` can both be their own page. A fresh install
  starts with the three site-wide feeds.
- **Tiles**: one post per page in a vertical pager. The crown or a swipe moves between posts.
  Each tile shows the territory and the poster; zaps are in the reader.
- **Reader**: tap a tile for the full post, rendered from markdown, followed by the top-level
  comments. The crown scrolls.
- **No waiting**: every screen refreshes in the background on launch and on foreground, so a
  sideways swipe lands on posts instead of a spinner.
- **Settings**: the leftmost page, one swipe right from the first feed. Long-press and drag to
  reorder screens, set the text size, toggle link posts, and open *Modify screens* to add or
  remove with check marks. Territories you have chosen sort to the top there, and the
  territory list is cached for a month rather than refetched on every visit. No toolbar
  buttons — on watchOS those render as tinted circles on top of the text.
- **Instant launch**: every screen is cached on disk, so a post appears before the network
  answers. Cached posts are readable offline.
- **Dark**: black background, stacker.news yellow accent. watchOS has no light mode.

## Layout

```
watchos/
  SNKit/          Swift package, Foundation only: GraphQL client, models, paging, markdown, cache.
                  Unit tests run on macOS and Linux with `swift test`.
  StackerWatch/   watchOS SwiftUI app (Xcode project + sources + assets).
```

The app talks to the public GraphQL endpoint at `https://stacker.news/api/graphql` with three
queries: `items(...)` for feeds (passing `sub` for a territory), `item(id:)` for a post with
its comments, and `topSubs(...)` to list territories in settings. No API key.

## Build on a Mac

Requirements: Xcode 15 or newer. No other tooling.

```sh
git clone -b claude/stacker-news-apple-watch-by88qp https://github.com/obvioussummer46/stacker.watch.git
open stacker.watch/watchos/StackerWatch/StackerWatch.xcodeproj
```

In Xcode pick your team under Signing & Capabilities, choose an Apple Watch simulator running
watchOS 10 or newer, and run. For a real watch, pair it with your iPhone in Xcode first.

The `SNKit` package is linked as a local package (the `Packages` group), so it builds as part
of the app with no extra setup.

## Tests

```sh
cd watchos/SNKit
swift test
```

The fixtures under `Tests/SNKitTests/Fixtures` are trimmed real responses. To refresh one:

```sh
curl -s https://stacker.news/api/graphql -H 'content-type: application/json' \
  -d '{"query":"...", "variables":{"type":"discussions","limit":5}}' | jq .
```

## App icon

`StackerWatch/StackerWatch/Assets.xcassets/AppIcon.appiconset/icon.png` is a 1024x1024 opaque
PNG rendered from `svgs/sn.svg` on the site's yellow. Replace it with any 1024x1024 PNG
without alpha if you want a different one.

## Not in stage 1

Login, zapping, posting, replying, notifications, complications, images inside posts
(they show as an "image" placeholder), nested comment threads.
