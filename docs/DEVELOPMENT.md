# NONP Transcription — Documentation développeur
_Doc mainteneur (architecture, dépendances, build, tests). Pour l'usage, voir le README à la racine._

# NONP Transcription

Application macOS native, locale et sans abonnement, qui génère des fichiers
**SRT** et **TXT** extrêmement fidèles à partir de vidéos ou de fichiers audio.
Aucune donnée n'est envoyée sur Internet : tout le traitement se fait sur votre
Mac. Aucune limite de durée.

Conçue pour Apple Silicon (testée sur MacBook Air / Apple M3, macOS 26).

---

## Sommaire

- [Présentation](#présentation)
- [Architecture générale](#architecture-générale)
- [Dépendances embarquées](#dépendances-embarquées-et-versions)
- [Formats pris en charge](#formats-pris-en-charge)
- [Compilation](#compilation)
- [Lancement](#lancement)
- [Emplacement du modèle téléchargé](#emplacement-du-modèle-téléchargé)
- [Mise à jour des binaires et du modèle](#mise-à-jour-des-binaires-et-du-modèle)
- [Tests automatiques (`--selftest`)](#tests-automatiques---selftest)
- [Limites connues](#limites-connues)

---

## Présentation

Le principe est volontairement minimal :

1. Ouvrir l'application.
2. Glisser une vidéo (ou un fichier audio).
3. Choisir la langue et la qualité.
4. Cliquer sur **Transcrire**.
5. Obtenir automatiquement, **à côté du fichier source** :
   - `nom_original.srt`
   - `nom_original.txt`
6. Le dossier contenant les résultats s'ouvre automatiquement.

**Fidélité garantie** : la transcription n'est jamais reformulée, résumée,
corrigée ni « nettoyée » de ses hésitations. Les timecodes sont conservés
exactement tels que produits par le moteur. Aucune traduction n'est effectuée.

---

## Architecture générale

Interface SwiftUI très fine au-dessus d'un cœur métier découplé par
**protocoles** (points d'extension pour les futures versions).

```
UI (SwiftUI)                    ContentView, DropZoneView, FileInfoView,
                                ModelStatusView, TranscriptionProgressView,
                                TranscriptionDoneView
        │
Coordination                    TranscriptionCoordinator
        │                       (extraction → transcription → export → ouverture)
        │
Cœur métier (protocoles)        AudioExtractor  ◄── FFmpegAudioExtractor
                                TranscriptionEngine ◄── WhisperCppEngine
                                SubtitleExporter (SRT + TXT)
                                EmbeddedTools (localise ffmpeg / whisper)
        │
État & modèles                  AppState, ModelStore, ModelDownloader,
                                WhisperModel, MediaFile, TranscriptSegment
        │
Outils système                  ProcessRunner (sous-processus + progression)
```

Principe clé d'évolutivité : chaque futur besoin (traduction, traitement par
lots, découpage intelligent) s'ajoutera comme **nouvelle implémentation d'un
protocole existant**, sans réécrire l'application.

### Arborescence

```
NONP-Transcription/
├── Package.swift               Définition SwiftPM (macOS 14+)
├── README.md
├── .gitignore
├── Sources/NONPTranscription/
│   ├── NONPTranscriptionApp.swift   Point d'entrée (@main)
│   ├── ContentView.swift            Vue principale
│   ├── SelfTest.swift               Harnais de test headless
│   ├── Models/                      MediaFile, WhisperModel, TranscriptSegment, …
│   ├── State/                       AppState, ModelStore, ModelDownloader, Coordinator
│   ├── Engine/                      ProcessRunner, AudioExtractor, TranscriptionEngine,
│   │                               SubtitleExporter, EmbeddedTools
│   └── Views/                       DropZoneView, FileInfoView, ModelStatusView, …
├── Resources/
│   ├── Info.plist                   Carte d'identité du bundle
│   └── AppIcon.icns                 Icône de l'application
├── Vendor/                          Binaires embarqués (voir ci-dessous)
│   ├── bin/  ffmpeg, whisper-cli
│   └── lib/  bibliothèques de ffmpeg (relocalisées)
├── Scripts/
│   ├── build_app.sh                 Compile + assemble le .app
│   └── generate_icon.swift          Génère l'icône
└── dist/
    └── NONP Transcription.app       Application finale (produite par le build)
```

---

## Dépendances embarquées et versions

Tout est **embarqué dans le `.app`** : aucune installation requise côté
utilisateur, aucune utilisation du Terminal.

| Composant | Version | Rôle | Emplacement dans l'app |
|---|---|---|---|
| **whisper.cpp** | commit `080bbbe` (2026-07-11), ggml 0.16.0 | Moteur de transcription, compilé **statique** avec accélération **Metal** | `Contents/Resources/bin/whisper-cli` |
| **FFmpeg** | 8.1.2 | Extraction/conversion audio (→ WAV 16 kHz mono) | `Contents/Resources/bin/ffmpeg` (+ `lib/`) |
| **Modèle Whisper** | `ggml-large-v3.bin` (3 095 033 483 octets) | Poids du modèle | **hors de l'app** (voir plus bas) |

> Le modèle n'est pas embarqué (≈ 3,1 Go) : il est téléchargé une seule fois
> au premier usage, depuis le dépôt officiel Hugging Face
> `ggerganov/whisper.cpp`.

Modèles utilisés selon la qualité choisie :

| Qualité | Modèle | Taille | Décodage |
|---|---|---|---|
| **Qualité maximale** (défaut) | `large-v3` | 3,1 Go | beam search (`-bs 5`) |
| **Rapide** | `large-v3-turbo` | 1,6 Go | glouton (greedy) |

Outils requis :
- **Pour compiler l'application** : uniquement les **Command Line Tools**
  Xcode (Swift 5.9 ou plus récent). Les binaires sont déjà fournis dans `Vendor/`.
- **Pour régénérer les binaires embarqués** (optionnel) : `cmake` (4.4.0) et
  `dylibbundler`, via Homebrew. *Non nécessaires* pour construire l'app.

---

## Formats pris en charge

**Vidéo** : MP4, MOV, AVI, MKV
**Audio** : MP3, WAV, M4A

Langues proposées : Auto (détection), Anglais, Allemand, Espagnol, Français,
Italien.

---

## Compilation

**Seul prérequis pour compiler l'application** : les outils de ligne de commande
Xcode (qui fournissent Swift). Sur un Mac neuf, une seule commande :

```bash
xcode-select --install
```

Les binaires `ffmpeg` et `whisper-cli` sont **déjà fournis** dans `Vendor/` :
aucune autre installation n'est nécessaire pour construire l'application.
(`cmake` et `dylibbundler` ne servent QU'À régénérer ces binaires — voir
« Mise à jour des binaires » — et ne sont pas requis pour compiler l'app.)

Compiler l'application :

```bash
cd "NONP-Transcription"
./Scripts/build_app.sh            # compile en release + assemble le .app
./Scripts/build_app.sh --run      # idem puis lance l'application
./Scripts/build_app.sh --debug    # compilation debug (itération plus rapide)
```

Le résultat est produit dans :

```
NONP-Transcription/dist/NONP Transcription.app
```

Le script effectue automatiquement : compilation SwiftPM → assemblage du bundle
→ copie des binaires embarqués et de l'icône → **signature ad-hoc locale**
(suffisante pour un usage personnel, évite les blocages au lancement).

---

## Lancement

**Sans Terminal** : double-cliquer sur `NONP Transcription.app` dans le Finder.

Vous pouvez déplacer le `.app` dans `/Applications` (glisser-déposer dans le
Finder) : l'application reste fonctionnelle car elle est **relocalisable**
(whisper-cli est autonome ; ffmpeg référence ses bibliothèques en chemin
relatif `@executable_path/../lib` ; le modèle est stocké dans votre dossier
utilisateur).

---

## Emplacement du modèle téléchargé

Le modèle est stocké **hors du projet** (donc hors synchronisation cloud) et
survit aux reconstructions de l'app :

```
~/Library/Application Support/NONP Transcription/Models/ggml-large-v3.bin
```

Pour libérer de l'espace, il suffit de supprimer ce fichier : l'application
reproposera son téléchargement au besoin.

---

## Mise à jour des binaires et du modèle

### Mettre à jour le modèle

Supprimer le fichier du modèle puis le re-télécharger depuis l'application
(bouton **Télécharger**) :

```bash
rm "~/Library/Application Support/NONP Transcription/Models/ggml-large-v3.bin"
```

Pour changer de version de modèle, ajuster les URL et tailles dans
`Sources/NONPTranscription/Models/WhisperModel.swift` (le champ `sizeBytes` doit
correspondre exactement à la taille du fichier officiel — il sert au contrôle
d'intégrité).

### Mettre à jour whisper.cpp (binaire)

```bash
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
      -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
      -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF
cmake --build build -j --config Release --target whisper-cli
cp build/bin/whisper-cli "…/NONP-Transcription/Vendor/bin/whisper-cli"
```

### Mettre à jour FFmpeg (binaire + bibliothèques)

```bash
brew upgrade ffmpeg
mkdir -p ffbundle/bin ffbundle/lib
cp "$(realpath "$(brew --prefix)/bin/ffmpeg")" ffbundle/bin/ffmpeg
chmod u+w ffbundle/bin/ffmpeg
dylibbundler -cd -b -of -x ffbundle/bin/ffmpeg -d ffbundle/lib/ \
             -p "@executable_path/../lib/"
cp ffbundle/bin/ffmpeg "…/NONP-Transcription/Vendor/bin/ffmpeg"
rm -f "…/NONP-Transcription/Vendor/lib/"*.dylib
cp ffbundle/lib/*.dylib "…/NONP-Transcription/Vendor/lib/"
```

Puis reconstruire : `./Scripts/build_app.sh`.

---

## Tests automatiques (`--selftest`)

L'application intègre un mode de test headless qui exécute **exactement** le
même pipeline que l'interface (extraction → transcription → export), sans
ouvrir de fenêtre. Utile pour valider une version après modification.

```bash
APP="dist/NONP Transcription.app/Contents/MacOS/NONPTranscription"

# Test complet : produit SRT + TXT, vérifie le nettoyage et l'intégrité source
"$APP" --selftest "/chemin/vers/fichier.mp4" [--lang-en]

# Test d'annulation : lance puis annule, vérifie l'absence de processus résiduel
"$APP" --selftest-cancel "/chemin/vers/audio_long.wav"
```

Le mode complet affiche notamment : nombre de segments, chemins SRT/TXT,
nettoyage du fichier temporaire, et confirmation que le fichier source est
resté intact.

---

## Limites connues

- **Durée MKV/AVI** : lue via AVFoundation, avec repli automatique sur le FFmpeg embarqué quand
  AVFoundation ne gère pas le conteneur (depuis la V1.2). La durée s'affiche donc pour ces formats.
- **Chargement Metal** : ~7 s de chargement de la bibliothèque Metal au début de
  chaque transcription (coût fixe, négligeable sur les fichiers longs).
- **Estimation du temps restant** : approximative en début de traitement, elle
  se stabilise au fil de la progression.
- **Silences longs** : comme tout modèle Whisper, `large-v3` peut occasionnellement
  produire du texte parasite sur de longs silences. La détection d'activité
  vocale (VAD) est un candidat pour une future version.
- **Un fichier à la fois** : le traitement par lots est prévu pour une V2.
- **Application non notarisée** : signée en local (ad-hoc). Parfaite pour un
  usage personnel ; une distribution large nécessiterait un compte développeur
  Apple et la notarisation.
