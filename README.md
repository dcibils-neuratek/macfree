# MacFree

A small native macOS app that shows what's using your disk and lets you clear it.

```bash
./scripts/build-app.sh
open build/MacFree.app
```

Run the tests with `swift test`.

For a complete scan, add `build/MacFree.app` under System Settings > Privacy & Security > Full Disk Access. The app is ad-hoc signed, so macOS may ask again after a rebuild.
