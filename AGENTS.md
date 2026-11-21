# AGENTS.md

## Product boundaries

- Salio is a new native iOS app with a separate backend in the same repository. Build screens in SwiftUI with native Apple frameworks; do not embed the Vybe web frontend or rebuild it inside a web view.
- Carry over useful, provider-independent behavior from Vybe only when it serves the current issue. Do not port Mistral, Voxtral, or the venue and image enrichment workflows. Keep Le Chonk as an optional Easter egg, not a model dependency or public brand.
- Evaluate Apple MapKit first for place search, walking directions, and native Place Cards. Treat provider fields not exposed by public APIs as unavailable to custom UI and ranking. Do not scrape Maps or assume photos, reviews, or opening hours can be read from a search result.
- Keep changes independently reviewable. Test new product behavior with deterministic sample data before depending on live provider coverage.

## GitHub workflow

- Start with an issue. Search for a related issue before opening one; put small follow-ups on the closest existing issue. Give new issues a short, outcome-based title and describe the problem, context, and observable acceptance criteria.
- Work on `ft/ref-<issue-number>` (for example, `ft/ref-12`), never directly on `main`. Keep one PR per issue.
- Use Conventional Commits and include `Refs #<issue-number>` in the commit body. Do not add AI attribution or private tool metadata to published commits or PRs.
- Use a Conventional Commit-style PR title. Write exactly three bullets: what changed; why it matters; and how it addresses the issue, quoting the relevant requirement. End with `Addresses GH issue: #<issue-number>`.
- Build and run affected iOS flows on a simulator, and run the relevant backend checks before opening the PR. Wait for approval before merging.
