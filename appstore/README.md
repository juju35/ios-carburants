# App Store

What App Store Connect asks for, kept with the code. Texts in `fr-FR/` are pasted as they are.

| Field | File / value | Limit |
| --- | --- | --- |
| Name | `fr-FR/name.txt` | 30 |
| Subtitle | `fr-FR/subtitle.txt` | 30 |
| Promotional text | `fr-FR/promotional_text.txt` | 170 |
| Description | `fr-FR/description.txt` | 4000 |
| Keywords | `fr-FR/keywords.txt` (comma separated, no spaces) | 100 |
| What's New | `fr-FR/release_notes.txt` (not asked for the first version) | 4000 |
| Support URL | https://github.com/juju35/ios-carburants/issues | |
| Privacy Policy URL | https://github.com/juju35/ios-carburants/blob/main/PRIVACY.md | |
| Category | Navigation (secondary: Travel) | |
| Age rating | 4+ (no objectionable content) | |
| Copyright | 2026 juju35 | |
| Price | Free | |

## Images

| What | Where | Size |
| --- | --- | --- |
| App icon | In the build (`Carburants/Assets.xcassets/AppIcon.appiconset`, default, dark and tinted) | 1024 × 1024 |
| iPhone screenshots | `screenshots/iphone-6.9/` | 1320 × 2868 (6.9", required; App Store Connect scales it to the smaller iPhones) |
| iPad screenshots | `screenshots/ipad-13/` | 2064 × 2752 (13", required for an app that runs on iPad) |
| iPhone Duo screenshots | `screenshots/iphone-duo/` | cover and inner screens, half folded (for the README; App Store Connect has no iPhone Duo slot of its own so far) |

They are taken by `scripts/screenshots.sh` from the app's demo mode (made-up prices around Rennes) on fresh
simulators, status bar at 9:41, and committed again by the Screenshots workflow when the app changes. Upload them in
order (01, 02…). CarPlay and widgets have no screenshot slot of their own in App Store Connect.

## App Privacy

Suggested answers (check them against Apple's definitions when filling in the questionnaire):

- **Data collection: none.** The location goes, without any identifier, to the public data.economie.gouv.fr API
  to find stations and is not kept or seen by the developer; nothing else leaves the device except public
  lookups (station coordinates to OpenStreetMap, brand identifiers to Wikidata). No account, analytics, ads or
  crash reporting.
- **Tracking: no.**

## App Review notes

> The app shows nearby fuel stations in France and their prices (public government data, no account). To review
> outside France, set the simulated location to a French city (for example Rennes, 48.11, -1.68). CarPlay uses the
> Fueling category (entitlement com.apple.developer.carplay-fueling).
