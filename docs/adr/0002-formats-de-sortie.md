# ADR-0002 — Choix des formats de sortie

- **Statut** : Accepté
- **Date** : 2026-07-23
- **Déclencheur** : chantier V1.2 nº2. L'utilisateur veut parfois un seul format
  de sortie, pas systématiquement les deux.

## Contexte

Aujourd'hui l'export produit **systématiquement** `.srt` **et** `.txt` : le
comportement est **codé en dur** dans `SubtitleExporter` (`export()` génère les
deux contenus via `makeSRT`/`makeTXT`, et `writePair` écrit toujours le couple).

Or les usages diffèrent : le **SRT** sert à sous-titrer (import en montage), le
**TXT** à lire, citer, archiver. Selon le fichier, un seul des deux suffit.

Le résultat canonique est `[TranscriptSegment]` (intervalle + texte exact),
**neutre** vis-à-vis du format. Tout format en dérive par une fonction **pure**.
Conséquence essentielle : **ajouter ou retirer un format ne relance jamais la
transcription** — on régénère depuis les segments déjà en mémoire.

Ce chantier relève du garde-fou « export : ne pas modifier sans décision
explicite » : le présent ADR **est** cette décision. Elle ne couvre **que** le
choix du format — ni le moteur, ni les paramètres whisper, ni le parsing, ni les
timecodes ne sont touchés.

## Décision

1. **Enum `OutputFormat`** (`rawValue` String), dans le style d'`OutputMode` :
   source unique de vérité pour les formats disponibles, leur extension et leur
   libellé.

2. **Réglage `selectedFormats`**, persistant, **défaut `{SRT, TXT}`** — le
   comportement V1 reste **strictement inchangé** au premier lancement. Stocké
   en `UserDefaults` comme **tableau de `rawValue`** (un `Set` n'y va pas
   directement) ; relu vers un `Set`, avec repli sur le défaut si la valeur
   stockée est absente ou corrompue (jamais un ensemble vide).

3. **Type de retour de l'export.** Le tuple `(srt: URL, txt: URL)` devient une
   **collection ordonnée `[ExportedOutput]`** (`{format, url}`). L'ordre est
   **canonique** (celui d'`OutputFormat.allCases`), indépendant de l'ordre de
   stockage. Se répercute sur `TranscriptionCoordinator.Phase.finished`,
   `TranscriptionDoneView` et les assertions `SelfTest`.

4. **Écriture conditionnelle.** `SubtitleExporter` **itère** sur les formats
   choisis. L'anti-collision et le rollback « pas d'orphelin » sont
   **généralisés à N fichiers** :
   - un radical est « pris » si **l'un** des formats choisis existe déjà (le
     même suffixe `_2, _3, …` est appliqué à **tous** les formats, qui restent
     donc appariés) ;
   - si une écriture échoue en cours de tour, **tous** les fichiers déjà écrits
     ce tour-ci sont retirés (aucune sortie partielle).

5. **UI (Réglages).** Une section « Formats de sortie », **une case à cocher par
   format**. **Garde-fou** : au moins un format reste toujours coché — le
   **dernier** format actif **ne peut pas** être décoché, et il n'y a **aucun
   re-cochage silencieux** d'un autre format à sa place.

6. **Fidélité.** Ne touche **ni** le moteur, **ni** le parsing, **ni** les
   timecodes. `makeVTT` (phase 2) **réutilisera** la logique de timecode
   existante : même calcul, entête `WEBVTT`, séparateur « . » au lieu de « , ».

7. **Rigueur (BUG-006).** `selectedFormats` reçoit des assertions de persistance
   — **même process** et **cross-process** — au même niveau que les trois clés
   existantes (`outputMode`, `customFolderPath`, `openFolderWhenDone`).

## Phasage

- **Phase 1 — TXT + SRT** : le **mécanisme complet** (enum, réglage, écriture
  conditionnelle, refactor du type de retour, UI à 2 cases, garde-fou,
  assertions). Non-régression : avec le défaut `{SRT, TXT}`, le comportement est
  **strictement identique** à aujourd'hui → les **33 assertions restent vertes**
  après adaptation mécanique du type de retour dans le harnais.

- **Phase 2 — VTT** : ajout **isolé** — `makeVTT`, un `case .vtt` dans l'enum, et
  une 3ᵉ case à cocher. Aucune reprise du mécanisme.

## Non-régression

La condition des 33 assertions vertes tient à une équivalence **au comportement
près** quand `selectedFormats == {SRT, TXT}` :

- les contenus sont produits par les **mêmes** `makeSRT`/`makeTXT`, inchangés —
  identité **octet pour octet** ;
- l'ordre d'écriture (SRT puis TXT) et la règle d'anti-collision (radical pris
  si `.srt` **ou** `.txt` existe) reproduisent exactement `writePair` ;
- le rollback à N fichiers, avec deux formats, se réduit au rollback binaire
  actuel (SRT retiré si le TXT échoue) ;
- la sélection dossier demandé / repli est inchangée.

Le harnais est adapté **mécaniquement** : les accès `out.srt`/`out.txt`
deviennent `out.url(for: .srt)`/`out.url(for: .txt)`, et chaque appel d'export
passe explicitement `formats: [.srt, .txt]` (stable même après l'ajout de VTT).

## Conséquences

- L'utilisateur choisit ses formats ; le défaut préserve l'expérience V1.
- `SubtitleExporter` reste **sans dépendance** aux frameworks Apple (cohérent
  avec la future extraction `NONPCore`, ADR-0001) : les formats lui sont
  **passés en paramètre**, il n'observe pas `Preferences`.
- Le type de retour devient extensible : ajouter un format n'impacte plus la
  signature.
- Coût : le refactor du type de retour traverse exporter → coordinator → vue de
  fin → harnais ; c'est un chantier **plus large que deux fichiers**, assumé.

## Alternatives écartées

- **Garder le tuple et ajouter des `URL?` optionnelles par format** — ne passe
  pas à l'échelle (un champ par format futur) et disperse la logique « présent
  ou non » chez chaque appelant.
- **Régénérer les formats après coup depuis l'écran de fin** — exigerait de
  conserver les `segments` au-delà de l'export ; hors périmètre. Le choix se
  fait **avant** lancement.
- **Stocker un `Set` via un bitmask entier** — moins lisible dans `UserDefaults`
  et dans les traces que des `rawValue` explicites.
- **Re-cocher automatiquement un format quand on décoche le dernier** — masque
  l'intention de l'utilisateur ; on **bloque** le décochage du dernier à la place.

## Séquencement

Branche `v1.2-format-sortie` depuis `main` (`af3a304`). ADR enregistré **avant**
l'implémentation. Phase 1 puis, séparément, Phase 2 (VTT).
