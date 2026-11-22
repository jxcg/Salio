# Salio

A native iOS app for finding things to do nearby. The Nearby feed uses fictional places from a FastAPI backend. No live search or location permissions yet.

Salio borrows one idea from Vybe: show when to leave so you have an hour at a place before it closes. The feed shows the earliest deadlines first.

On iPhone Duo, Nearby stays on the outer display and moves to the trailing pane when the phone opens. The leading pane shows additional timing details for the same selected place. This uses the native SwiftUI split view, not a separate screen for each pose. Build with the iOS 27.1 SDK or later to exercise the Duo layout. The client targets iOS only; the Mac is a development host, not an app destination.

## Run locally

Start the API from the repository root with Python 3.12+ and uv:

```sh
uv run --project backend uvicorn main:app --app-dir backend --port 8765
```

On a Mac with Xcode and XcodeGen, build and launch on a booted iOS simulator:

```sh
cd ios
xcodegen generate
BUNDLE_ID=org.example.salio.dev
xcodebuild -project Salio.xcodeproj -scheme Salio -sdk iphonesimulator \
  -derivedDataPath build SALIO_BUNDLE_ID="$BUNDLE_ID" CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Salio.app
SIMCTL_CHILD_SALIO_API_URL=http://127.0.0.1:8765 xcrun simctl launch booted "$BUNDLE_ID"
```

When the API runs off the Mac, forward port 8765 to it or set `SALIO_API_URL` to a reachable HTTPS endpoint. `GET /v1/sample-feed` uses a fixed sample time. Pass `at` (ISO 8601) to try a different time.

Run the API tests with `uv run --project backend pytest backend`.

## Next slice

Try nearby search and native Apple Place Cards with a few real venues. Check what a Place Card displays separately from what MapKit exposes to our own UI or backend. No Mistral models, voice, or enrichment workflows are part of this starter.
