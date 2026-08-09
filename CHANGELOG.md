# Journal des modifications

Toutes les évolutions notables de NONP Transcription.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/) ;
règle de versionnement : le tag Git est égal à `CFBundleShortVersionString`.

## [1.2.3] — 2026-08-09

Conformité des licences. **Aucun changement fonctionnel.**

### Ajouté
- **Textes de licence embarqués dans le bundle** (`Contents/Resources/Licenses/`) :
  `LICENSE` (MPL-2.0), `COPYING.LGPLv2.1` (texte complet de la LGPL-2.1, repris des
  sources FFmpeg 8.1.2) et `THIRD_PARTY_NOTICES.md`. Jusqu'à la 1.2.2 incluse, ces
  textes ne vivaient que dans le dépôt et sur la page de téléchargement : l'archive
  distribuée n'en contenait aucun, alors que l'avis interne du binaire FFmpeg
  (`ffmpeg -L`) renvoie explicitement à une copie que l'utilisateur « doit avoir
  reçue ». La source correspondante de FFmpeg, elle, était déjà publiée (LGPL-2.1 §4).
- **Garde-fou au build** : `Scripts/build_app.sh` échoue si l'un des trois textes est
  manquant ou vide, ou si `Contents/Resources/Licenses/` finit vide. Les fichiers du
  dépôt restent l'unique source de vérité — aucune copie n'est maintenue en parallèle.

> Fidélité : aucune ligne de code applicatif ne change. Moteur, paramètres
> whisper-cli, extraction FFmpeg, parsing, timecodes, formats d'export et interface
> sont identiques à la 1.2.2. Les binaires embarqués sont **identiques au bit près**
> à ceux de la 1.2.2 publiée (`ffmpeg` `660f3b68…`, `whisper-cli` `9c950af9…`),
> vérifié par comparaison SHA-256 avec l'archive en ligne. Non-régression : 67/67.

## [1.2.2] — 2026-08-08

Licence et composants embarqués. **Aucun changement fonctionnel.**

### Modifié
- **FFmpeg reconstruit en LGPL-2.1 ou ultérieure** : binaire **statique**, sans aucun
  composant GPL (`--disable-gpl`, sans `--enable-version3`) et sans codec vidéo —
  l'application n'a jamais décodé de vidéo, elle n'extrait que l'audio. Les 18
  bibliothèques dynamiques embarquées (dont x264 et x265, qui imposaient la GPL)
  disparaissent : il ne reste qu'un exécutable ne dépendant que de frameworks Apple et
  de `libz` du système. La couverture des décodeurs audio est **identique** à celle de
  la 1.2.1. (ADR-0005)
- **Licence du projet passée en MPL-2.0**, que le point précédent rend possible.
  `THIRD_PARTY_NOTICES` réécrit sur les seuls composants réellement redistribués.
- **Taille du bundle : 42 Mo → 9,8 Mo** (archive de distribution 4,7 Mo).

### Ajouté
- **`docs/BUILDING_FFMPEG.md`** et **`Scripts/build_ffmpeg_lgpl.sh`** : source
  correspondante et build reproductible du FFmpeg embarqué, au titre de l'obligation
  LGPL-2.1 §4 (droit de relink).

> Fidélité : l'extraction audio transmise à Whisper est **identique bit à bit** à celle
> de la 1.2.1, vérifiée par comparaison SHA-256 des WAV produits sur MP4, MOV, AVI, MKV,
> MP3, WAV, M4A et sur des MKV à pistes AC-3, DTS et Opus. Transcription, timecodes,
> formats d'export et interface sont inchangés. Non-régression : 67/67.

## [1.2.1] — 2026-08-04

Clarté de l'interface. Aucune évolution du moteur.

### Ajouté
- **Nom des exports suffixé par la langue** : chaque fichier porte le code ISO 639-1 de
  la langue de l'audio avant son extension — `entretien_fr.srt`, `interview_en.txt`,
  `entrevista_es.vtt`. Le code vient du résultat de transcription (langue détectée en
  mode automatique, ou langue choisie), jamais de la demande. Langue indisponible : le
  nom reste nu, sans placeholder. L'extension continue de distinguer le format
  (ADR-0002), le suffixe distingue la langue ; l'anti-collision `_2`, `_3`… s'applique
  au nom complet et n'écrase jamais un fichier existant. (ADR-0004)

### Modifié
- **Sélecteur de langue clarifié** : le menu « Langue » pouvait se lire comme une cible
  de traduction. Il devient « **Langue de l'audio** », avec deux options explicites —
  « Détecter automatiquement » (défaut inchangé) ou « Préciser : » suivi du menu des
  langues — et une ligne d'aide : « Choisissez la langue parlée dans le fichier.
  NONP Transcription la retranscrit fidèlement — il ne traduit pas. »
- **Nouvelle icône d'application** et logo repris dans l'en-tête de la fenêtre.
  L'icône est désormais un jeu de fichiers versionné (`Resources/AppIcon.iconset`) au
  lieu d'être dessinée par code ; `Scripts/generate_icon.swift` est neutralisé pour
  ne plus l'écraser.

> Fidélité : rien de ce qui précède ne touche au texte transcrit. Le moteur, les
> paramètres whisper-cli, le parsing, les timecodes et le contenu des fichiers exportés
> sont inchangés — le résultat de Whisper est identique. Seul le **nom** des fichiers
> de sortie évolue. La persistance du choix de langue (défaut « Auto ») est préservée.

## [1.2.0] — 2026-07-23

Durcissement de la fiabilité et petites fonctions cohérentes. macOS, 100 % local.

### Ajouté
- **Choix des formats de sortie** : cases à cocher TXT / SRT / VTT (au moins un format
  toujours coché ; défaut TXT + SRT). Export WebVTT avec échappement conforme. (ADR-0002)
- **Nom du fichier média** affiché dans la fenêtre de progression — prévient l'erreur
  « mauvaise vidéo transcrite ».
- **Durée des fichiers MKV/AVI** dans l'interface : repli sur le FFmpeg embarqué quand
  AVFoundation ne sait pas lire le conteneur.
- **Persistance du choix de langue** entre les lancements (défaut « Auto »).

### Sécurité / fiabilité
- **Vérification d'intégrité des modèles par empreinte SHA-256** : contrôle obligatoire
  après téléchargement et bouton « Vérifier maintenant ». Un modèle non conforme est
  refusé et la transcription bloquée — évite les transcriptions silencieusement fausses
  dues à un modèle corrompu (taille exacte mais contenu altéré).

> Fidélité : aucune de ces évolutions ne modifie le moteur de transcription, le parsing,
> les timecodes ni l'export — le résultat de Whisper reste inchangé.

## [1.1.0] — 2026-07-22

Fiabilité du dossier de sortie.

### Corrigé
- **BUG-007** : repli vers le dossier de la vidéo quand le dossier fixe est inaccessible
  en écriture.
- **BUG-008** : le message d'erreur nomme le dossier réellement tenté.

### Connu
- **BUG-006** (mémorisation du dossier fixe) : intermittent, jamais reproduit sur
  6 cycles contrôlés, cause non établie — non corrigé mais **instrumenté** (journalisation
  os_log) et couvert par des tests. Défaut connu non bloquant.

## [1.0.0] — 2026-07-15

Version initiale. Transcription locale d'audio/vidéo en texte et sous-titres (SRT/TXT)
via whisper.cpp (large-v3, Metal) et FFmpeg embarqués. 100 % local, sans abonnement,
sans réécriture du résultat de Whisper.
