# Politique de confidentialité — Carburants (iOS)

*Dernière mise à jour : 24 octobre 2026*

Carburants (`me.jstephan.carburants`) est une application iPhone, iPad et CarPlay publiée par juju35.
Elle ne demande aucun compte, n'affiche aucune publicité et ne contient aucun outil de mesure d'audience,
de suivi ou de rapport de plantage.

## Position

L'application utilise la position de l'appareil (pendant son utilisation, sur l'iPhone ou dans CarPlay ;
pour le widget, si vous l'autorisez) uniquement pour trouver les stations-service proches.

- Les coordonnées sont envoyées, chiffrées (HTTPS), dans la requête de recherche adressée à l'API publique
  de data.economie.gouv.fr, qui renvoie les stations autour de ce point. Aucun identifiant n'accompagne la requête.
- Le lieu de la dernière recherche est gardé sur l'appareil, dans l'espace partagé avec le widget, pour que
  celui-ci affiche les stations proches. Il n'est transmis à aucun autre service.

## Autres services contactés

| Service | Ce qui est envoyé |
| --- | --- |
| raw.githubusercontent.com (GitHub) | Rien : téléchargement de fichiers publics (noms des stations, liste des enseignes), au plus une fois par semaine |
| overpass-api.de (OpenStreetMap) | Les coordonnées des stations affichées (pas celles de l'appareil) |
| wikidata.org, commons.wikimedia.org | Les identifiants Wikidata des enseignes |

Comme tout serveur web, ces services peuvent journaliser l'adresse IP de la connexion, selon leurs propres
politiques de confidentialité.

## Données enregistrées sur l'appareil

Vos choix (carburants, tri), le lieu et la liste de la dernière recherche, et des caches (noms, enseignes, logos).
Supprimer l'application supprime tout.

## Contact

https://github.com/juju35/ios-carburants/issues

---

# Privacy policy — Carburants (English)

No account, no ads, no analytics, tracking or crash reporting. The device's location is used only to find nearby
fuel stations: it is sent over HTTPS, with no identifier, in the search request to the public data.economie.gouv.fr
API. The place of the last search is kept on the device for the widget and sent nowhere else. The app also downloads
public files from GitHub, sends the coordinates of the stations shown (not the device's) to overpass-api.de, and brand
identifiers to Wikidata and Wikimedia Commons. Deleting the app removes everything it stored.
Contact: https://github.com/juju35/ios-carburants/issues
