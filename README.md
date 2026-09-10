# macOS personal configuration

## Hammerspoon

`hammerspoon/init.lua` contains the current global hotkeys and the Codex quota menu-bar integration.

Install it with:

```sh
mkdir -p ~/.hammerspoon
cp hammerspoon/init.lua ~/.hammerspoon/init.lua
pkill -x Hammerspoon || true
open -a Hammerspoon
```

## Apps

- `apps/CodexQuota` is the source for the Codex quota menu-bar tool and its detailed dashboard.
- `apps/Kopilka` is the source for the quick-capture notes app.

Both directories contain source code and build scripts only. Generated app bundles, build products, caches, and local agent state are intentionally excluded.
