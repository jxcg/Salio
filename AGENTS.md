# AGENTS.md

## Build

- Use familiar words in the app: call the list a feed, and label it Nearby.
- Build native SwiftUI for iOS only. Borrow behavior from Vybe, not its web UI, AI services, or enrichment workflows.
- Use MapKit first. Rely on public APIs; don’t scrape or assume Place Card data is available to app code.
- Prefer removing code to adding layers. Add dependencies or network calls only when the feature needs them. Measure before claiming a speedup.
- Test with fixed samples. Run relevant backend tests and check changed iOS flows in Simulator (Mac satellite in Amp).

## Ship

- Issue first. Reuse related issues; give new ones an outcome title and testable acceptance criteria.
- One PR per issue on `ft/ref-<number>`. Never commit or push to `main`. Merge only after approval.
- Use Conventional Commit titles for commits and PRs. Commit body: `Refs #<number>`. No AI attribution or private tool metadata.
- PR body: exactly three bullets (what, why, quoted issue requirement), then `Addresses GH issue: #<number>`.
