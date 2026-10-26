# Contributing

Thank you for helping.

## Bugs and ideas

Open an issue. For a bug, give your macOS version, your Mac, the AgentValley version, and what you saw.

## Build and test

```sh
./build-app.sh            # builds build/AgentValley.app
open build/AgentValley.app
swift test                # needs Xcode
```

Building needs macOS 15 or later and the Command Line Tools (`xcode-select --install`).

## Pull requests

- One change per pull request, with a test when it changes what the app does.
- `swift test` passes.
- AgentValley only reads. It never writes in `~/.claude` on its own and never answers for the person. The one command it runs into Claude Code is `claude plugin`, when the person presses Install the plugin. A change that breaks either will not be merged.
- The app's words stay short and plain, in English.

By contributing, you agree that your work is released under the MIT License.
