# Crowy

**A free, open-source clipboard manager for macOS — a credible alternative to the best paid apps in the category.**

Crowy is designed to feel native: no Dock icon, no menu bar clutter. It runs quietly in the background and surfaces only when you summon it with a global shortcut — your clipboard history, instantly searchable, instantly pasteable.

## Features

- ⌨️ **Global hotkey** — `⌘⇧V` by default, fully customizable
- 🔍 **Instant search** — type to filter; narrow by source app or content kind (text / image / file / link)
- 🖼️ **Rich previews** — inline thumbnails for images, link previews for URLs
- 🔒 **Privacy-first** — respects the [nspasteboard.org](https://nspasteboard.org) convention: password managers, transient pasteboards, and concealed types are never captured
- 🚫 **Per-app blacklist** — exclude any app you don't want monitored
- 🗂️ **Smart retention** — keep clips for 24 hours / 1 week / 1 month / forever; configurable on-disk quota (default 5 GB)
- 🚀 **Native** — built with SwiftUI + AppKit, no Electron, no telemetry, no account
- 💯 **Free forever** — MIT-licensed, no trial, no in-app purchases

## Install

### Homebrew (recommended)

```sh
brew install --cask alexandretrichot/tap/crowy
```

### From GitHub Releases

Download the latest `.zip` from the [Releases page](https://github.com/alexandretrichot/crowy/releases), unzip, and drag `Crowy.app` to `/Applications`.

On first launch, macOS may show a Gatekeeper warning (the build is ad-hoc signed, not notarized — see [Building from source](#building-from-source) if you'd rather build it yourself).

## Requirements

- macOS Tahoe (26.0) or later
- Accessibility permission — required to send `⌘V` to the frontmost app. Crowy walks you through granting it on first launch.

## Usage

1. Copy anything, anywhere.
2. Press `⌘⇧V` to open the paste bar.
3. Type to search, or use `←` / `→` to navigate. Press `↩` to paste into the previously focused app.

Open **Settings** (`⌘,`) to change the hotkey, retention policy, quota, and app blacklist.

## Building from source

```sh
git clone https://github.com/alexandretrichot/crowy.git
cd crowy
make build
make run
```

You'll need Xcode 26+ and the macOS 26 SDK.

## Contributing

Issues and pull requests welcome. The codebase is small and approachable: SwiftUI views, an AppKit-bridged search bar, GRDB-backed SQLite store, and a `ClipboardMonitor` polling `NSPasteboard.changeCount`.

## License

MIT — see [LICENSE](LICENSE).
