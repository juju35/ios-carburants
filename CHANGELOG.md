# Changelog

## Unreleased

### Improvements
- CarPlay: « Y aller » ouvre directement l'application de navigation choisie dans les réglages (Plans si elle
  n'est pas installée), sans demander laquelle utiliser
- CarPlay: le bouton « Y aller » affiche la durée de trajet, comme le bouton Itinéraire sur iPhone

## 1.3.0

### Improvements
- CarPlay: restored brand logos on the points-of-interest map screen
- CarPlay: provide station pins and selected pins at native CarPlay dimensions
- Keyboard: added toolbar dismiss button and interactive scroll dismissal on station list

### Fixes
- MapKit: resolved Metal API validation crash during split-view and window resizing
- Performance: memoized visible stations and cheapest price lookups in StationsModel
- Concurrency: thread-safe date parsing and fixed widget location continuation leaks
- Stability: safe bounds checking on station opening days and proper fallback for navigation URLs

## 1.2.0

### Fixes
- README: fixed two sentences that ran together without a separator in the "Map + list" bullet

## 1.1.0

### New
- iPhone Duo half folded: the list in a glass panel on one half of the screen, the map on the other, nothing on the
  hinge; the map runs under the side status bar of the cover screen
- Liquid Glass side panel with rounded corners on iPad and iPhone Duo open
- Approximate location: the list says distances are indicative and offers to use the exact position
- Widgets: opening statuses change at the right minute ("ferme à 21:00" turns to "Fermé" at 21:00)

### Fixes
- The search started from a cached position, possibly hours old: reopened elsewhere, the app showed the stations
  around the old place
- Names and logos arriving late could bring back the prices and distances of an older search
- No refresh after 10 minutes when standing still (app open or CarPlay at a stop)
- CarPlay rebuilt every screen on each update: the open place card closed and the list went back to the top
- A tap on a widget could open "Station introuvable" with several widgets on different fuels
- "Rupture" shown for a fuel that just had no price; failed refreshes and location errors went unnoticed
- The position is sent to the price API at about 100 m instead of 10 cm
- The app could not be signed before Apple grants CarPlay Fueling: CarPlay is now opt-in in the build settings

## 1.0.0

- Map and list of nearby stations with the prices of your fuels, cheapest in green; station card with directions
  (Plans, Google Maps, Waze), hours and services
- Layout for compact and regular widths: sheet on iPhone, side panel on iPhone Duo unfolded and iPad; Split View
- CarPlay (Fueling): map, list sorted by price or distance, station details, fuel picker
- Widgets: small, medium, large, extra large and Lock Screen, per fuel or following the app's choice
