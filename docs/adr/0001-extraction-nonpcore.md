# ADR-0001 — Extraction d'un cœur indépendant des frameworks Apple (`NONPCore`)

- **Statut** : Accepté
- **Date** : 2026-07-17
- **Déclencheur** : ajout de l'objectif multiplateforme (macOS + Windows), l'application
  restant locale. L'ouverture du code est **envisagée** ; la licence **n'est pas arrêtée**.

## Contexte

NONP Transcription est un exécutable SwiftPM unique mêlant logique métier et interface
SwiftUI. La valeur du produit est la **fidélité** de la transcription. Un objectif
multiplateforme rend souhaitable que la logique qui décide de cette fidélité — arguments
whisper, parsing, timecodes, export — soit **unique et partagée**.

Un cœur unique **réduit une source majeure de divergence** entre systèmes ; il ne suffit
pas, à lui seul, à garantir des résultats identiques : l'arithmétique flottante, les
bibliothèques système et les versions exactes des binaires embarqués peuvent encore
introduire des écarts. La parité effective entre plateformes sera **établie par
benchmark**, pas postulée.

Mesure : **10 fichiers (~660 lignes)** sont déjà sans dépendance à un framework Apple
(Foundation seul). Une vérification a corrigé une estimation initiale trop large :
`ModelDownloader` dépend de Combine (`ObservableObject`/`@Published`) et reste hors
périmètre.

## Décision

1. **Extraction mécanique.** Déplacer ces 10 fichiers dans un module SwiftPM `NONPCore`,
   au sein du **même paquet** que l'application, **sans modification fonctionnelle**
   (déplacement + passage en visibilité `package`, rien d'autre).

2. **Visibilité `package`.** L'accès inter-cibles utilise le niveau `package` (vérifié
   fonctionnel dans l'environnement), non `public` : le cœur reste interne au paquet,
   sans API publique à maintenir.

3. **Refactor séparé et justifié.** Après l'extraction mécanique, un commit distinct
   extrait le décodage JSON de whisper (aujourd'hui inline dans `transcribe()`) dans une
   fonction testable `package static func decodeSegments(from:) throws -> [TranscriptSegment]`.
   Ce refactor est limité, préserve le comportement, et n'est motivé que par la
   **testabilité du parseur**. Il constitue le seul écart au principe « déplacer,
   rendre `package`, rien d'autre », et il est explicitement décidé, non improvisé.

4. **Qualification.** Le module est qualifié d'**indépendant des frameworks Apple** —
   et **non** de « multiplateforme ». Ce dernier statut ne sera acquis qu'après
   **compilation et exécution réelles sous Windows**, tests de caractérisation à l'appui.
   Aucune technologie d'interface Windows n'est choisie à ce stade.

## Vérification de non-régression

La non-régression est **vérifiée sur les cas couverts par le golden et les fixtures de
caractérisation** — elle n'est pas « garantie » dans l'absolu. Elle repose conjointement
sur quatre moyens :

- **Diff mécanique** : après extraction, retirer les modificateurs `package`/`public`
  ajoutés et comparer à `HEAD` → diff attendu **vide** (aucune ligne de logique modifiée).
- **Fixtures JSON synthétiques** (écrites par le projet) : caractérisent le parsing —
  plusieurs segments, Unicode, ponctuation, timecodes, et **entrée invalide**. Le test
  d'entrée invalide vérifie **l'échec ou une catégorie d'erreur stable** (le cas
  `jsonUnreadable`), sans dépendre d'un message textuel fragile — sauf si ce message
  constitue volontairement un contrat.
- **Segments synthétiques** (en dur dans `NONPCoreCheck`) : caractérisent le formatage,
  les timecodes et les noms de fichiers (`makeSRT` / `makeTXT` / `timecode` /
  `availableBaseName`).
- **Golden bout-en-bout** (audio sinusoïdal synthétique) : caractérise l'enchaînement
  ffmpeg → whisper → parsing → export. Égalité au bit près, avant/après, **sur la même
  machine** — sans préjuger de la parité inter-plateformes.

Les deux passes identiques observées lors de la préparation établissent une
**répétabilité observée dans l'environnement testé**, non un déterminisme garanti.

## Tests — contrainte d'environnement

Swift Testing **et** XCTest sont indisponibles sans Xcode complet (les deux vérifiés :
`no such module`). Les tests de caractérisation prennent donc la forme d'un exécutable
`NONPCoreCheck`, cohérent avec le choix du projet de se passer d'Xcode. `NONPCoreCheck`
est une cible distincte, **jamais embarquée dans l'application distribuée** (vérifié :
`build_app.sh` ne copie que le binaire de l'app).

## Fixtures — droits

Toutes les fixtures sont **écrites ou générées par le projet**, sans aucun média tiers :
fixtures JSON synthétiques, segments en dur, et un `fixture.wav` synthétique généré par
ffmpeg (`sine`). Elles relèvent de la **licence (future) du dépôt** ; aucune dédicace
CC0 n'est supposée — elle ne serait affirmée que si un fichier de dédicace explicite
l'accompagnait. Un `Bench/golden/README.md` documentera source, licence, arguments de
génération, versions et SHA-256, **capturés au moment exact de la génération** (les
valeurs préparatoires ne sont pas figées).

## Conséquences

- Le cœur devient **testable sans interface** — un manque actuel comblé.
- Un portage futur devient **délimité et vérifiable** : périmètre connu (~660 lignes),
  les fixtures de caractérisation formant une **spécification exécutable** contre laquelle
  une réimplémentation se validera. Le portage reste un travail d'ingénierie réel.
- Aucune décision irréversible : ni technologie Windows, ni licence.
- Deux cibles à maintenir dans le paquet.
- **Nuance `package`** : si `NONPCore` devient un jour un *paquet séparé* (dépôt distinct,
  réutilisation externe), ses symboles devront être promus `public`.

## Alternatives écartées

- **Ne rien faire** — le coût d'extraction croît à mesure que l'UI se couple à la logique
  (ampleur non chiffrée).
- **Choisir Tauri / Avalonia / Qt maintenant** — prématuré, sans donnée réelle sur le
  portage ni licence arrêtée.
- **Réécrire l'UI en multiplateforme** — jetterait un SwiftUI qui reste juste pour macOS.
- **`public` plutôt que `package`** — exposerait une API publique inutile à ce stade.

## Séquencement

L'extraction ne démarre qu'après : validation de la V1.1 par l'usage réel → fusion dans
`main` → tag `v1.1.0` → branche `refactor-nonpcore` depuis `main`. Le présent ADR est
enregistré **avant** l'extraction, indépendamment du gel du code.
