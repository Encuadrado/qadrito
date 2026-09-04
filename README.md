# Qadrito

A native macOS desktop app for Encuadrado engineers to manage their PR review queue.

![Uploading image.png…]()


## Overview

QAdrito is a SwiftUI macOS application that displays your GitHub PR review queue from the Encuadrado organization. It provides smart filtering, sorting, and stack detection to help you prioritize and manage your code reviews efficiently.

## Features

- View all PRs waiting for your review
- Filter by author (GitHub username or Slack name) and repository
- View modes: All, Easiest 5, Oldest 5
- Automatic stack detection for consecutive PRs
- Secure GitHub PAT storage in macOS Keychain
- Offline cache of last fetch
- Display times in America/Santiago timezone

## Quick Start

See the [Qadrito app README](./Qadrito/README.md) for detailed setup instructions, including:

- How to create a GitHub OAuth App
- Building and running the app
- OAuth device flow authentication
- Configuration and usage
- Filter examples

## Project Structure

```
Qadrito/
├── Qadrito.xcodeproj/          # Xcode project
├── Qadrito/                     # Main app source
│   ├── Models/                  # Data models
│   ├── Views/                   # SwiftUI views
│   ├── ViewModels/             # View models (MVVM)
│   ├── Services/               # GitHub client, cache
│   ├── Utilities/              # Helpers and utilities
│   └── Assets.xcassets/        # App icons and assets
├── QadritoTests/               # Unit tests
└── README.md                   # Comprehensive documentation
```

## Requirements

- macOS 14.0+
- Xcode 15.0+
- GitHub OAuth App (Client ID required for authentication)

## License

Copyright © 2026 Encuadrado. All rights reserved.
