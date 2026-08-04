# ADR-0004 — Nommage des exports par langue

- **Statut** : Accepté
- **Date** : 2026-08-04
- **Déclencheur** : chantier V1.2.1. Plusieurs transcriptions d'un même sujet
  dans des langues différentes se distinguent mal une fois exportées.
- **Complète** : [ADR-0002](0002-formats-de-sortie.md) (choix des formats).

## Contexte

Depuis l'ADR-0002, un export produit un fichier par format choisi, tous nommés
d'après la source : `entretien.srt`, `entretien.txt`. L'**extension** distingue
le format ; rien ne distingue la **langue**.

L'application ne traduit pas — c'est un invariant, et le sélectionneur de langue
a justement été clarifié en « Langue de l'audio » (V1.2.1). Un suffixe de langue
ne peut donc désigner qu'une seule chose : la langue **parlée dans la source**.
Il n'y a aucune ambiguïté à lever entre langue source et langue cible, puisqu'il
n'y a pas de langue cible.

La langue du résultat était déjà disponible sans coût : whisper.cpp écrit dans
son JSON un bloc `result.language` (« fr »), distinct de `params.language` qui
ne reflète que la **demande** (« auto » en détection automatique). L'application
lisait le JSON sans exploiter ce champ.

Ce chantier relève du garde-fou « export : ne pas modifier sans décision
explicite ». Le présent ADR **est** cette décision, et elle ne porte que sur le
**nom** des fichiers. La fidélité couvre explicitement ce cas : le nom de fichier
de sortie n'est pas le contenu.

## Décision

1. **Forme** : `<base>_<code>.<ext>`, où `<code>` est un code **ISO 639-1** en
   minuscules — `entretien_fr.srt`, `interview_en.txt`, `entrevista_es.vtt`.

2. **Source du code** : le **résultat canonique** du moteur (`result.language`),
   c'est-à-dire la langue **détectée** en mode automatique, ou celle imposée par
   l'utilisateur. Jamais la demande.

3. **Pas de placeholder** : si le code est absent ou inexploitable (moteur muet,
   `auto`, code hors ISO 639-1 comme `yue`), le fichier garde son nom nu
   `<base>.<ext>`. Un `_unknown` affirmerait une langue non établie ; l'absence
   de suffixe, elle, n'affirme rien.

4. **Composition avec les formats** (ADR-0002) : les deux axes sont
   orthogonaux — l'extension porte le format, le suffixe porte la langue. Tous
   les formats d'un même export partagent le même suffixe.

5. **Anti-collision inchangée** : le suffixe de langue est calculé **avant**
   l'anti-collision, qui s'applique donc au nom complet (`entretien_fr_2.srt`).
   Le schéma numérique existant `_2`, `_3`… est conservé tel quel — il est
   documenté, testé (BUG-007/008) et déjà présent dans les fichiers produits par
   les versions antérieures. Aucun écrasement silencieux, écriture atomique.

6. **Un seul point de décision** : `Engine/ExportNaming.swift`, fonction pure et
   sans accès disque, donc testable sans lancer de transcription. Les vues ne
   construisent aucun nom.

## Conséquences

- Deux transcriptions d'un même média dans des langues différentes cohabitent
  naturellement, sans suffixe numérique : `entretien_fr.srt` et
  `entretien_en.srt` sont deux noms distincts.
- Le nom d'un média se terminant déjà par un code (`entretien_fr.mp4`) produit
  `entretien_fr_fr.srt`. Retiré à dessein : deviner qu'un suffixe existant
  désigne une langue reviendrait à corriger automatiquement le nom choisi par
  l'utilisateur, et resterait ambigu (`_it` peut être autre chose qu'italien).
- Les fichiers produits par les versions ≤ 1.2 gardent leur nom nu ; aucune
  migration, aucun renommage rétroactif.
- Le contenu des fichiers est rigoureusement identique avec ou sans suffixe —
  vérifié par assertion (SelfTest `--naming-cases`, N8).

Le suffixe reflète la décision du moteur, y compris lorsqu'elle est fausse : une
détection erronée produit un nom erroné (observé sur un échantillon espagnol de 3 s
détecté fr avec p = 0,99). Conditionner le suffixe à la langue choisie, ou à un seuil
de confiance, a été envisagé et écarté — la détection est fiable sur du contenu réel,
et un nom se corrige sans relancer la transcription.

## Alternatives écartées

- **`<base>.<code>.<ext>`** (style sous-titres, `film.fr.srt`) : convention
  répandue en sous-titrage, mais elle suggère précisément un fichier de
  sous-titres *traduits* accompagnant une vidéo — le contresens que ce chantier
  cherche à éviter.
- **Suffixe seulement en cas d'ambiguïté** (quand un fichier existe déjà dans
  une autre langue) : nommage imprévisible, dépendant de l'ordre des exports.
- **Toujours un suffixe, `_unknown` à défaut** : affirme une information que le
  moteur n'a pas fournie.
