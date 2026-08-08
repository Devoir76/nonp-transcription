# ADR-0005 — FFmpeg reconstruit en LGPL, licence du projet en MPL-2.0

- **Statut** : Proposé — **ligne `configure` validée et build de vérification réussi**
  (2026-08-08, en scratchpad, hors dépôt). En attente de validation avant intégration.
- **Date** : 2026-08-08
- **Supersède** : [ADR-0003](0003-licence-gplv3.md) (Licence du projet : GPL-3.0-or-later)
- **Déclencheur** : préparation de la page de téléchargement sur `nonp.fr`. L'audit
  du FFmpeg embarqué confirme que le verrou GPL est **hérité du paquet Homebrew**,
  non d'un besoin fonctionnel. ADR-0003 avait classé le rebuild LGPL en
  « alternative écartée pour l'instant » ; deux faits nouveaux le remettent au
  premier plan (gain de taille réel, fenêtre de relicensing qui se referme).

## Contexte

### Ce que l'application demande réellement à FFmpeg

Deux invocations, vérifiées sur l'ensemble des sources Swift :

1. `AudioExtractor.swift:42` — seul appel du pipeline de transcription :
   `ffmpeg -hide_banner -nostdin -y -i <entrée> -vn -ac 1 -ar 16000 -c:a pcm_s16le <sortie.wav>`
2. `MediaDurationProbe.swift:22` — repli d'affichage de durée pour MKV/AVI :
   `ffmpeg -hide_banner -nostdin -i <entrée>` (lecture d'entête, **aucun décodage**)

Le besoin se réduit à : démuxer un conteneur, décoder **une piste audio**,
rééchantillonner, encoder en `pcm_s16le`, muxer en WAV. Le `-vn` est décisif :
**aucune vidéo n'est jamais décodée, encore moins encodée.**

Formats acceptés en entrée (`MediaFile.swift:21`) : `mp4, mov, avi, mkv, mp3,
wav, m4a` — sept extensions. FLAC et Opus ne sont pas acceptés comme fichiers
déposés ; ils restent possibles comme **pistes internes** d'un MKV.

### Pourquoi le verrou GPL n'a aucune contrepartie fonctionnelle

Vérifié sur le binaire embarqué (FFmpeg 8.1.2, Homebrew) :

- `ffmpeg -encoders` liste `libx264` et `libx265` comme **encodeurs uniquement**.
  L'application n'encode aucune vidéo.
- `ffmpeg -decoders` montre que H.264 et HEVC sont décodés par les décodeurs
  **natifs** (`h264`, `hevc`), pas par x264/x265. Retirer les deux bibliothèques
  GPL ne retire **aucune capacité de lecture** — et `-vn` les court-circuite de
  toute façon.
- Tous les décodeurs audio susceptibles d'apparaître sont **natifs, donc LGPL** :
  `aac`, `aac_latm`, `mp3`, `mp2`, `ac3`, `eac3`, `alac`, `flac`, `opus` (natif —
  `libopus` est superflu), `vorbis`, `dca` (DTS), `wmav2`, famille `pcm_*`.

**Aucun décodeur audio de notre périmètre n'est GPL-only.** Le GPL provient pour
l'essentiel d'encodeurs et de filtres **vidéo** dont l'application n'utilise rien.

> **Précision issue de la validation (2026-08-08).** L'affirmation « aucun décodeur
> audio n'est GPL-only » était trop absolue : FFmpeg 8.1.2 en compte **neuf**, que
> `configure` refuse en LGPL (`lgpl_gpl`) — `adpcm_circus`, `adpcm_ima_escape`,
> `adpcm_ima_hvqm2`, `adpcm_ima_hvqm4`, `adpcm_ima_magix`, `adpcm_ima_pda`,
> `adpcm_n64`, `adpcm_psxc`, et `ahx` (via son bitstream filter `ahx_to_mp2`,
> lui-même GPL). Ce sont des codecs ADPCM de **consoles et jeux vidéo rétro**
> (N64, PlayStation, HVQM, Magix). **Aucun ne peut apparaître dans un MP4, MOV,
> AVI, MKV, MP3, WAV ou M4A grand public** : la perte est nulle pour le périmètre
> de l'application, mais elle est réelle et doit être consignée.

### Le poids vient de la vidéo, pas du GPL

Répartition mesurée du bundle installé (42 Mo au total) :

| Élément | Taille |
|---|---|
| `Resources/lib/` (18 dylibs FFmpeg) | **37 Mo** |
| `Resources/bin/whisper-cli` | 3,26 Mo |
| `MacOS/NONPTranscription` (code app) | 1,39 Mo |
| `Resources/bin/ffmpeg` | 0,44 Mo |
| Icône et logo | 0,23 Mo |

Dans les 37 Mo de `lib/`, la part **vidéo** domine : `libx265` (7,48), `libcrypto`
+ `libssl` (5,73 — aucun réseau utilisé), `libSvtAv1Enc` (3,06), `libvpx` (1,75),
`libx264` (1,27), `libvmaf` (0,91), `libdav1d` (0,84), plus la part vidéo de
`libavcodec` (9,64 Mo au total).

Retirer x264 et x265 seuls ne gagnerait que ~8,75 Mo. **Retirer tout le codec
vidéo gagne environ 30 Mo** — et ce gain est peu risqué, puisque rien de vidéo
n'est appelé.

### Fenêtre de relicensing

Le dépôt n'est **pas encore public** et le projet n'a **pas de contributeur
externe**. Relicencier ne demande aujourd'hui que l'accord de l'auteur. Dès
qu'une première contribution externe est fusionnée sous GPL-3.0, il faudrait
l'accord de chaque contributeur. **Le coût du changement de licence n'est pas
constant dans le temps : il augmente brutalement à l'ouverture du dépôt.**

### Ce que la GPLv3 fermerait durablement

- **Le Mac App Store est incompatible avec la GPLv3** : les conditions Apple
  imposent des restrictions d'usage et de nombre d'installations que la licence
  interdit (précédent VLC). Cela écarte la voie qui réglerait d'un coup la
  signature et le contournement Gatekeeper.
- Toute version fermée ou payante serait exclue tant que FFmpeg GPL est embarqué.

### Sous-processus, et pourquoi le LGPL lève l'ambiguïté

L'application n'établit **aucun lien** avec FFmpeg : elle lance `ffmpeg` par
`Process` (fork/exec), les échanges se font par arguments et fichiers
(`ProcessRunner.swift`). C'est la configuration la plus favorable à la thèse de
l'agrégation plutôt que de l'œuvre dérivée, et le protocole `AudioExtractor`
isole déjà la dépendance.

Cette lecture est défendable, mais elle reste **une lecture** : elle demanderait
à être expliquée et tenue. Passer FFmpeg en LGPL supprime la question au lieu de
l'argumenter — plus rien à défendre, quelle que soit l'interprétation retenue.

## Décision

1. **Reconstruire FFmpeg en LGPL-2.1-or-later**, sans `--enable-gpl`, sans
   `--enable-version3`, sans `--enable-nonfree`, sans aucun codec vidéo.
2. **Licencier NONP Transcription sous MPL-2.0**, ce que le point 1 rend possible.
3. **ADR-0003 est superseded** — sa décision (GPL-3.0-or-later) ne s'applique plus.
   Son analyse du FFmpeg Homebrew reste exacte et sert de point de départ ici.

### Stratégie de build : sûreté avant taille

Principe directeur : **le gain de taille vient du retrait de la vidéo ; la sûreté
vient d'une couverture audio large.** Ces deux objectifs ne s'opposent pas, parce
que les décodeurs audio sont petits.

- **Vidéo : tout retirer.** x264/x265 (GPL), mais aussi AV1 (aom, SVT-AV1, dav1d),
  VP8/VP9 (vpx), Theora, et les décodeurs vidéo natifs. Gain massif, risque nul :
  `-vn` garantit qu'aucun n'est appelé, et la durée est lue par démuxage.
- **Audio : rester large.** Ne **pas** énumérer au plus juste. Un MKV peut porter
  une piste AC-3, DTS, Opus ou WMA ; un décodeur manquant produirait un échec
  chez l'utilisateur, pas au build. On accepte du poids mort côté audio.

**Méthode retenue pour la liste audio — génération, pas rédaction.** Le binaire
actuellement en production expose **222 décodeurs audio**. Les recopier à la main
serait la principale source d'oubli. La liste est donc **générée depuis le binaire
GPL actuel**, ce qui garantit par construction une **couverture audio identique à
celle de la version en production** : aucune régression audio n'est structurellement
possible.

```sh
# Depuis la racine du dépôt — liste des décodeurs audio du binaire ACTUEL.
# Filtres : '=' (séparateur du tableau), '_at' (wrappers AudioToolbox, doublons
# des décodeurs natifs), 'lib*' (décodeurs externes — on ne veut aucune lib tierce).
# Le sed traduit les 12 noms d'AFFICHAGE qui diffèrent du nom de COMPOSANT attendu
# par configure (voir table ci-dessous) : sans lui, configure ÉCHOUE.
./Vendor/bin/ffmpeg -hide_banner -decoders \
  | awk '/^ A/{print $2}' | grep -Ev '^(=|lib)' | grep -v '_at$' \
  | sed -e 's/^8svx_exp$/eightsvx_exp/'   -e 's/^8svx_fib$/eightsvx_fib/' \
        -e 's/^acelp\.kelvin$/acelp_kelvin/' -e 's/^atrac3plus$/atrac3p/' \
        -e 's/^atrac3plusal$/atrac3pal/'  -e 's/^g722$/adpcm_g722/' \
        -e 's/^g726$/adpcm_g726/'         -e 's/^g726le$/adpcm_g726le/' \
        -e 's/^interplayacm$/interplay_acm/' -e 's/^real_144$/ra_144/' \
        -e 's/^real_288$/ra_288/'         -e 's/^wavesynth$/ffwavesynth/' \
  | sort -u > audio-dec.txt
AUDIO_DEC=$(paste -sd, - < audio-dec.txt)

# Garde-fou : tout nom inconnu de configure doit être signalé AVANT le build.
./configure --list-decoders | tr -s ' \t' '\n' | sed '/^$/d' | sort -u > known.txt
comm -23 audio-dec.txt known.txt   # doit ne rien afficher
```

**Table de correspondance — noms d'affichage ≠ noms de composants** (12 cas,
tous détectés par la validation du 2026-08-08) :

| `ffmpeg -decoders` | `--enable-decoder=` |
|---|---|
| `8svx_exp` / `8svx_fib` | `eightsvx_exp` / `eightsvx_fib` |
| `acelp.kelvin` | `acelp_kelvin` |
| `atrac3plus` / `atrac3plusal` | `atrac3p` / `atrac3pal` |
| `g722` | `adpcm_g722` |
| `g726` / `g726le` | `adpcm_g726` / `adpcm_g726le` |
| `interplayacm` | `interplay_acm` |
| `real_144` / `real_288` | `ra_144` / `ra_288` |
| `wavesynth` | `ffwavesynth` |

**Caveat sur le filtre `lib*`.** Écarter les décodeurs externes suppose qu'un
équivalent **natif** existe. C'est vrai pour tous nos médias, mais ce ne serait
pas vrai d'un codec sans implémentation native. Vérification faite : le binaire
actuel n'expose qu'**un seul** décodeur audio `lib*`, `libopus`, dont le natif
`opus` est présent. Speex, GSM, AMR (NB/WB) et iLBC — souvent cités comme
dépendants d'une bibliothèque externe — sont ici **natifs et conservés**. Aucune
perte, mais le filtre resterait à réexaminer si une future version de FFmpeg
déplaçait un codec vers une lib externe.

### Ligne `configure` proposée

À exécuter dans les sources FFmpeg 8.1.2 (`git checkout n8.1.2` ou tarball
`ffmpeg-8.1.2.tar.xz`), sur macOS arm64, avec clang. `--disable-everything`
doit précéder les `--enable-*` : l'ordre est significatif.

```sh
./configure \
  --prefix="$PWD/../ffbuild-out" \
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

**Corrections apportées par la validation du 2026-08-08** (la version initiale de
cet ADR aurait échoué) :

- **`abuffer` et `abuffersink` retirés** : absents de `--list-filters`. Ce sont des
  filtres source/puits **internes**, toujours compilés avec `avfilter` et **non
  configurables**. Les demander faisait échouer `configure`. Les huit filtres
  restants sont tous confirmés présents.
- **`--disable-postproc` retiré** : l'option **n'existe plus** dans FFmpeg 8.
- **`ahx_to_mp2` non ajouté** aux `bsf` : ce filtre est lui-même GPL-only, donc
  inutile en LGPL (et le décodeur `ahx` qu'il servait est hors périmètre).
- Démuxeurs, parsers, bsfs, muxers, encodeurs et protocoles : **tous confirmés**
  présents dans les listes de FFmpeg 8.1.2, sans exception.

**Justification des options non évidentes :**

- `--disable-autodetect` : empêche `configure` d'attraper des bibliothèques
  Homebrew présentes sur la machine de build. Sans lui, le build n'est pas
  reproductible et pourrait ré-embarquer une lib tierce par accident.
- `--enable-zlib` : **obligatoire ici**. `--disable-autodetect` désactive zlib, or
  Matroska peut utiliser zlib pour la compression des entêtes et des pistes. Sans
  ce drapeau, certains MKV échoueraient — exactement le type de régression que la
  stratégie cherche à éviter.
- `--enable-static --disable-shared` : produit **un binaire unique**. Supprime le
  dossier `Resources/lib/` (37 Mo, 18 dylibs) et toute l'étape `dylibbundler` de
  relocalisation `@executable_path` décrite dans `docs/DEVELOPMENT.md:237-248`.
- `--disable-network` : aucun accès réseau n'est utilisé, et cela retire OpenSSL
  (5,73 Mo). Cohérent avec l'invariant « tout en local ».
- **`libswscale` n'est pas désactivé** : le programme `ffmpeg` en dépend au lien,
  et `--disable-swscale` casse historiquement la compilation de `ffmpeg.c`. On
  garde ces ~0,6 Mo plutôt que de risquer un build impossible.
- `--disable-audiotoolbox` : les décodeurs `*_at` sont des wrappers Apple qui
  **doublonnent** les décodeurs natifs déjà présents dans la liste générée. Aucune
  capacité perdue.

### Taille — chiffres réels (build de vérification, 2026-08-08)

| Élément | Aujourd'hui | Mesuré après rebuild |
|---|---|---|
| `Resources/lib/` (18 dylibs) | 37 Mo | **0** (supprimé) |
| `ffmpeg` | 0,44 Mo (dynamique) | **5,15 Mo** (statique) |
| `whisper-cli` | 3,10 Mo | inchangé |
| Code app + ressources | 1,54 Mo | inchangé |
| **Bundle `.app`** | **42 Mo** | **9,8 Mo** |
| **ZIP distribué** | ~40 Mo | **4,3 Mo** |

Résultat **meilleur que la fourchette estimée** (10–12 Mo). `--enable-small`
n'est donc pas nécessaire et n'est pas retenu : la vitesse de décodage est
préservée. Le binaire ne dépend d'**aucune bibliothèque tierce** — `otool -L` ne
montre que des frameworks Apple et `libz` du système.

### Vérification fonctionnelle (smoke test, 2026-08-08)

Neuf échantillons couvrant les conteneurs et codecs du périmètre ont été produits
avec l'**ancien** binaire GPL, puis passés dans la commande **exacte** de
`AudioExtractor.swift` avec les deux binaires. Les WAV produits ont été comparés
par SHA-256 :

| Échantillon | Résultat |
|---|---|
| AAC/M4A · MP3 · WAV · ALAC/M4A | identique **bit à bit** |
| MKV à piste AC-3 · FLAC · Opus | identique **bit à bit** |
| MP4 H.264 + AAC · AVI MPEG-4 + MP2 | identique **bit à bit** |

**9 sur 9 identiques.** Le repli de durée (`MediaDurationProbe`) renvoie également
`Duration: 00:00:03.00` sur MKV, AVI, MP4 et M4A.

Ce test ne remplace pas la campagne de non-régression sur médias réels (voir
Conséquences), mais il confirme que la sortie transmise à Whisper est **strictement
inchangée** — l'invariant de fidélité n'est pas touché.

### Lien de conformité : pourquoi un binaire statique reste LGPL-conforme ici

La LGPL est plus permissive que la GPL, mais elle protège une liberté précise :
**pouvoir remplacer la bibliothèque par une version modifiée**. Un binaire lié
**statiquement** rend cette substitution impossible sans relinker — le §4 de la
LGPL-2.1 exige donc que le distributeur fournisse de quoi le faire.

La conformité repose ici sur **deux conditions cumulatives**, dont aucune n'est
facultative :

1. **`ffmpeg` reste un exécutable séparé.** Le code de l'application ne se lie
   pas à FFmpeg : il le lance par `Process` (fork/exec), les échanges passent par
   arguments et fichiers. Le code de l'application n'est donc **pas** une œuvre
   dérivée des bibliothèques FFmpeg, et sa licence (MPL-2.0) est sans effet sur
   l'obligation. Le §4 porte sur le **binaire `ffmpeg` seul**.
2. **Le droit de relink est effectivement assuré.** Pour le binaire `ffmpeg`
   statique, il faut fournir : la **source FFmpeg 8.1.2 exacte** utilisée, la
   **ligne `configure` exacte**, et le **script de build** permettant de
   reproduire et de relinker.

**Conséquence opérationnelle : la fourniture de la source FFmpeg devient
OBLIGATOIRE, pas optionnelle.** C'est le point à ne pas manquer — le passage de
GPL à LGPL allège la portée (le code de l'app cesse d'être contaminé) mais
**n'efface pas** l'obligation de source sur FFmpeg lui-même. Concrètement, la
page de téléchargement de `nonp.fr` devra proposer, à côté du ZIP :

- l'archive source `ffmpeg-8.1.2.tar.xz` (ou une offre écrite valable trois ans) ;
- la ligne `configure` exacte — également lisible via `ffmpeg -version` dans le
  binaire livré, ce qui la rend auto-documentée ;
- le script de build reproductible ;
- le texte de la **LGPL-2.1** dans le ZIP, aux côtés de la MPL-2.0 de l'app.

Une alternative existe — lier FFmpeg **dynamiquement** — qui allégerait le §4
(remplacer une dylib suffit à relinker). Elle est écartée : elle ramènerait le
dossier `Resources/lib/`, l'étape `dylibbundler` et une partie du poids, pour une
obligation qui reste de toute façon simple à satisfaire.

## Conséquences

- **(+)** Plus aucune obligation GPL, plus aucune ambiguïté sur la portée de la
  licence. MPL-2.0 devient possible ; l'App Store et une éventuelle version
  fermée cessent d'être fermés par construction.
- **(+)** Téléchargement divisé par environ six sur un ZIP auto-hébergé.
- **(+)** Pipeline de packaging simplifié : plus de `lib/`, plus de `dylibbundler`.
- **(−)** LGPL n'est pas « aucune obligation » : une build **statique** relève du
  §4 (permettre le relinking). La fourniture de la source FFmpeg, de la ligne
  `configure` et du script de build est **obligatoire** — voir « Lien de
  conformité » ci-dessus.
- **(−)** Le composant est **gelé** par `CLAUDE.md` (« extraction FFmpeg : ne pas
  modifier sans décision explicite »). Le présent ADR **est** cette décision, mais
  elle engage une campagne de non-régression : rejouer les 58/58 **et** tester à
  la main les 7 formats d'entrée, plus des MKV à pistes AC-3, DTS et Opus
  qu'aucun test automatisé ne couvre aujourd'hui.
- **(−)** Le risque résiduel est l'**oubli d'un composant**, pas une impossibilité
  de licence. Atténuation : la liste audio est générée, pas rédigée ; et un nom de
  composant inconnu fait **échouer `configure`** — le risque de faute de frappe est
  bruyant, seul l'oubli d'une catégorie entière serait silencieux.
- Les notices tierces seront **tranchées après le rebuild**, sur les composants
  réellement restants (décision de séquencement : ne pas documenter `libmpg123`
  si le rebuild le supprime, ce qui est probable).

## Alternative écartée

**Montage à deux licences** : code de l'application sous MPL-2.0, build assemblée
distribuée sous GPL-3.0 puisqu'elle embarque FFmpeg GPL. Légal et courant, sans
rebuild. Écarté parce qu'il demande d'être expliqué avec soin dans le dépôt pour
ne pas être lu comme un contournement, et qu'il conserve les inconvénients de la
GPL sur la build réellement distribuée (App Store, poids). Reste disponible comme
filet si la campagne de test s'éternise.

## Suites (hors périmètre de cet ADR)

1. ~~Valider les noms de composants contre `./configure --list-*`~~ — **fait le
   2026-08-08** : 12 noms de décodeurs corrigés, 2 filtres et 1 option retirés,
   tout le reste confirmé. `configure` retourne « License: LGPL version 2.1 or
   later ».
2. ~~Build et mesure de taille réelle~~ — **fait le 2026-08-08** (scratchpad, hors
   dépôt) : 5,15 Mo, bundle 9,8 Mo, ZIP 4,3 Mo, smoke test 9/9 identiques.
3. **Intégration** dans `Vendor/` + adaptation de `Scripts/build_app.sh` (retrait
   de l'étape `dylibbundler` et du dossier `lib/`) — **en attente de validation**.
4. Campagne de non-régression : 58/58 **et** les 7 formats sur médias réels, plus
   des MKV à pistes AC-3, DTS et Opus.
5. Bascule `LICENSE` en MPL-2.0, reprise des en-têtes de fichiers, ajout du texte
   LGPL-2.1 pour FFmpeg.
6. `THIRD_PARTY_NOTICES` refait sur les composants réellement restants (`libmpg123`
   notamment disparaît avec les dylibs).
7. Mise en place de l'offre de source FFmpeg sur la page de téléchargement.
8. **En parallèle et sans dépendance** : DCO dans `CONTRIBUTING.md`, à mettre en
   place avant l'ouverture du dépôt public.
