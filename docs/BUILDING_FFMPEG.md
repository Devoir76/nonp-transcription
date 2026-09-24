# Reconstruire le FFmpeg embarqué (source correspondante — LGPL §4)

Ce document est la **source correspondante** du binaire `Vendor/bin/ffmpeg`
redistribué avec NONP Transcription. Il existe pour satisfaire l'obligation de
la **LGPL-2.1 §4** : permettre à quiconque de remplacer FFmpeg par une version
modifiée et de reconstruire un binaire équivalent.

Contexte et justification de la stratégie de build :
[ADR-0005](adr/0005-ffmpeg-lgpl-et-licence-mpl.md).

## Ce qui est redistribué

| | |
|---|---|
| Version FFmpeg | **8.1.2** |
| Licence | **LGPL-2.1-or-later** (`ffmpeg -L` le confirme) |
| Lien | **statique** — exécutable unique, pas de `lib/` |
| External libraries | **`zlib` uniquement**, fournie par macOS (`/usr/lib/libz.1.dylib`) |
| Cible de déploiement | **macOS 14.0** — `MACOSX_DEPLOYMENT_TARGET`, fixée dans le script (voir ci-dessous) |
| SDK de compilation | celui que choisit `Scripts/sdk_macos.sh`, le même que l'application |
| Architecture | **arm64** (Apple Silicon) |
| Taille | 5 438 328 octets |
| SHA-256 | `00de24977c33329f3f9d9aad416fa4fe0fdda052f77e53c8ecc4b4d33d860675` |

## Source amont

| | |
|---|---|
| Archive | `ffmpeg-8.1.2.tar.xz` |
| URL | https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz |
| SHA-256 | `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c` |
| Dépôt | https://git.ffmpeg.org/ffmpeg.git (tag `n8.1.2`) |

> **Copie archivée — source hébergée : https://nonp.fr/transcription**
> (section « Licences »). Une copie de cette archive y est publiée avec le paquet
> de l'application, afin que la source reste disponible même si l'amont devient
> inaccessible.
> Suivi du dépôt : [`../third_party/ffmpeg/README.md`](../third_party/ffmpeg/README.md).

## Reconstruire

```sh
./Scripts/build_ffmpeg_lgpl.sh /chemin/vers/dossier-de-travail
```

Le script télécharge l'archive (ou réutilise une copie locale), **vérifie son
SHA-256**, configure, compile, et contrôle que le binaire produit est bien
LGPL et sans dépendance non système. Il n'installe rien et ne touche pas au
dépôt : le binaire est laissé dans le dossier de travail.

Prérequis : macOS arm64, les outils en ligne de commande Xcode (`clang`, `make`).
Ni Homebrew, ni `pkg-config`, ni `nasm` ne sont nécessaires.

## Cible de déploiement et SDK — fixés dans le script

> ⚠️ **Mesuré le 24/09, et corrigé depuis.** Le binaire redistribué avec la
> 1.2.3 déclarait **`minos 26.0`** dans son `LC_BUILD_VERSION` — la version de la
> machine qui l'avait compilé — alors que l'application déclare `14.0` et que la
> page de téléchargement promet « macOS 14 ou plus récent ». **Personne ne
> l'avait décidé** : aucune cible n'était fixée, et le compilateur avait pris
> celle du système.
>
> Le script fixe désormais les deux **dans son propre texte**, et non dans
> l'environnement :
>
> - `MACOSX_DEPLOYMENT_TARGET=14.0` ;
> - le SDK, choisi par la même logique que l'application (`Scripts/sdk_macos.sh`),
>   pour que les trois Mach-O du bundle soient compilés contre le même.
>
> Il **s'arrête** si le binaire produit ne porte pas la cible demandée, et
> `Scripts/build_app.sh` refuse d'assembler un bundle dont un Mach-O déclare
> autre chose que le `LSMinimumSystemVersion` de l'`Info.plist`.
>
> *Cela ne garantit pas que le binaire FONCTIONNE sur macOS 14 — cela ne se
> mesure que sur une machine de cette version. Cela garantit que le bundle dit
> d'une seule voix ce qu'il exige.*

## Ligne `configure` exacte

Elle est **gravée dans le binaire livré** — `ffmpeg -version` l'affiche
intégralement. C'est la référence qui fait foi ; ce qui suit en est la copie
lisible.

```sh
./configure \
  --disable-gpl --disable-nonfree \
  --disable-autodetect --enable-zlib \
  --enable-static --disable-shared \
  --disable-doc --disable-debug --disable-network \
  --disable-ffplay --disable-ffprobe \
  --disable-avdevice \
  --disable-videotoolbox --disable-audiotoolbox --disable-sdl2 \
  --disable-everything \
  --enable-demuxer=mov,matroska,avi,mp3,wav,aac,ac3,eac3,dts,flac,ogg,asf,mpegts,mpegps,flv,aiff,au,caf,w64,wv,ape,tta,amr,mpc,mpc8,dsf,voc,rm,iff \
  --enable-decoder="$AUDIO_DEC" \
  --enable-parser=aac,aac_latm,ac3,dca,flac,mpegaudio,opus,vorbis,cook,dolby_e,gsm,mlp,sbc,tak,xma,amr,misc4 \
  --enable-bsf=aac_adtstoasc,extract_extradata,null \
  --enable-filter=aresample,aformat,anull,atrim,aselect,channelmap,pan,volume \
  --enable-muxer=wav,pcm_s16le \
  --enable-encoder=pcm_s16le,pcm_f32le,pcm_s24le,pcm_u8 \
  --enable-protocol=file,pipe
```

`$AUDIO_DEC` est la liste des **220 décodeurs audio**, figée dans
[`../Scripts/ffmpeg-audio-decoders.txt`](../Scripts/ffmpeg-audio-decoders.txt)
et jointe par des virgules par le script.

### Pourquoi ces options

| Option | Raison |
|---|---|
| `--disable-gpl` | aucun composant GPL — c'est l'objet même du rebuild |
| pas de `--enable-version3` | vise **LGPL-2.1**+ et non LGPL-3 |
| `--disable-everything` + réactivation ciblée | seule façon de retirer les décodeurs vidéo, qui n'ont pas de drapeau de catégorie |
| `--enable-zlib` | **obligatoire** : `--disable-autodetect` désactive zlib, dont Matroska a besoin pour les entêtes et pistes compressées |
| `--disable-autodetect` | empêche `configure` de capter des bibliothèques présentes sur la machine de build ; garantit un résultat reproductible et sans lib tierce |
| `--enable-static --disable-shared` | binaire unique, ni `lib/` ni relocalisation `dylibbundler` |
| `--disable-network` | l'application ne fait aucun accès réseau ; retire OpenSSL |
| `libswscale` **non** désactivé | le programme `ffmpeg` en dépend au lien ; `--disable-swscale` casse la compilation |
| `--disable-audiotoolbox` | les décodeurs `*_at` doublonnent les décodeurs natifs déjà activés |
| **pas de `--prefix`** | on ne fait pas `make install` ; l'omettre évite d'inscrire un chemin de machine dans la chaîne de configuration gravée — chaîne publique, que `ffmpeg -version` affiche |

### Composants audio refusés en LGPL

Neuf décodeurs de la liste sont **GPL-only** ; `configure` les désactive et
l'avertit. C'est **attendu** :

```
adpcm_circus, adpcm_ima_escape, adpcm_ima_hvqm2, adpcm_ima_hvqm4,
adpcm_ima_magix, adpcm_ima_pda, adpcm_n64, adpcm_psxc, ahx
```

Ce sont des codecs ADPCM de consoles et jeux vidéo rétro. Aucun ne peut
apparaître dans un MP4, MOV, AVI, MKV, MP3, WAV ou M4A grand public : la perte
est sans effet sur le périmètre de l'application.

## Reproductibilité

Le script reconstruit un binaire **fonctionnellement équivalent** — c'est ce
qu'exige la LGPL §4.

La chaîne de configuration gravée dans le binaire ne contient **aucun chemin de
machine** (`--prefix` est omis), si bien que la ligne ci-dessus est exactement
celle qu'affiche `ffmpeg -version` sur le binaire livré. Elle est donc
directement comparable.

Le script ne garantit pas pour autant une reproduction **bit à bit** : le
résultat dépend de la version exacte de `clang` et du SDK macOS utilisés. Pour
comparer un binaire reconstruit à celui qui est livré, comparer la ligne
`configure` et les **capacités** (`ffmpeg -decoders`, `-demuxers`, `-L`) plutôt
que les empreintes.

## Vérifier un binaire reconstruit

```sh
./ffmpeg -L | head -5                       # doit dire « Lesser General Public », version 2.1
./ffmpeg -version | grep -c enable-gpl      # doit afficher 0
./ffmpeg -buildconf | grep -A2 'External'   # doit ne lister que zlib
otool -L ./ffmpeg | grep -v '/usr/lib/\|/System/Library/'   # ne doit rien afficher
```

Test fonctionnel, avec la commande exacte utilisée par l'application
(`Sources/NONPTranscription/Engine/AudioExtractor.swift`) :

```sh
./ffmpeg -hide_banner -nostdin -y -i <média> -vn -ac 1 -ar 16000 -c:a pcm_s16le sortie.wav
```
