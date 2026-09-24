# Stacker News for Apple Watch

A read-only watchOS client for [stacker.news](https://stacker.news). Stage 1: no login,
no zaps, no posting. Open the app, a post fills the screen, turn the Digital Crown to
move to the next one, tap to read the whole thing. Made for reading a few paragraphs in bed.

## What it does

- **Feeds**: Hot (default), Recent, Top this week. Text posts only by default; link posts
  can be switched on in the feed picker.
- **Tiles**: one post per page in a vertical pager. The crown or a swipe moves between posts.
- **Reader**: tap a tile for the full post, rendered from markdown, followed by the top-level
  comments. The crown scrolls.
- **Surprise me**: bottom-left button opens a random post from the year's top discussions.
- **Instant launch**: the last feed is cached on disk, so a post appears before the network
  answers. Cached posts are readable offline.
- **Dark**: black background, stacker.news yellow accent. watchOS has no light mode.

## Layout

```
watchos/
  SNKit/          Swift package, Foundation only: GraphQL client, models, paging, markdown, cache.
                  Unit tests run on macOS and Linux with `swift test`.
  StackerWatch/   watchOS SwiftUI app (XcodeGen spec + sources + assets).
```

The app talks to the public GraphQL endpoint at `https://stacker.news/api/graphql` with two
queries: `items(...)` for feeds and `item(id:)` for a post with its comments. No API key.

## Build on a Mac

Requirements: Xcode 15 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd watchos/StackerWatch
xcodegen generate
open StackerWatch.xcodeproj
```

In Xcode pick your team under Signing & Capabilities (or set `DEVELOPMENT_TEAM` in
`project.yml` and regenerate), choose an Apple Watch simulator running watchOS 10 or newer,
and run. For a real watch, pair it with your iPhone in Xcode first.

The generated `.xcodeproj` and `Info.plist` are git-ignored. Edit `project.yml` and regenerate
instead of editing the project in Xcode.

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
