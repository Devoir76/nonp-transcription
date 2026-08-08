# THIRD_PARTY_NOTICES

NONP Transcription est distribué sous **MPL-2.0** (voir [`LICENSE`](LICENSE)).
Il embarque et redistribue les composants tiers ci-dessous, sous leurs licences
respectives.

Depuis la reconstruction de FFmpeg en LGPL (voir
[ADR-0005](docs/adr/0005-ffmpeg-lgpl-et-licence-mpl.md)), l'application
n'embarque plus **aucune** bibliothèque dynamique : les deux exécutables sont
liés statiquement et ne dépendent que de frameworks Apple et de `libz` du
système.

Contenu redistribué :

```
NONP Transcription.app/Contents/Resources/bin/
├── ffmpeg        (LGPL-2.1-or-later)
└── whisper-cli   (MIT)
```

---

## whisper.cpp — MIT

Moteur de transcription, exécutable `whisper-cli`. Compilé **statiquement** avec
accélération **Metal**. Autonome : ne dépend d'aucune bibliothèque tierce
(`otool -L` ne montre que des frameworks Apple).

- Version : **1.9.1** — commit **`080bbbe`** (2026-07-11)
- Composant **ggml** inclus : **0.16.0**
- Source : https://github.com/ggerganov/whisper.cpp

```
MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Modèles Whisper (`ggml-large-v3`, `ggml-large-v3-turbo`) — MIT

Poids GGML dérivés des modèles **OpenAI Whisper**. Les modèles ne sont **pas**
inclus dans l'application : ils sont téléchargés par l'utilisateur au premier
lancement et vérifiés par empreinte SHA-256 (voir
[`docs/MODEL_MANIFEST.md`](docs/MODEL_MANIFEST.md)).

- Source des poids : https://huggingface.co/ggerganov/whisper.cpp
- Modèle amont : https://github.com/openai/whisper

```
MIT License

Copyright (c) 2022 OpenAI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## FFmpeg — LGPL-2.1-or-later

Extraction et conversion audio (média d'entrée → WAV 16 kHz mono), et lecture de
durée pour les conteneurs que AVFoundation ne sait pas ouvrir (MKV, AVI).

- Version : **8.1.2**
- Licence : **LGPL-2.1-or-later** — le binaire le déclare lui-même via `ffmpeg -L`
- Lien : **statique**, un exécutable unique
- **External libraries : `zlib` uniquement** (fournie par le système, voir
  section suivante)
- Construit **sans `--enable-gpl`**, **sans `--enable-version3`**, **sans
  `--enable-nonfree`**, et **sans aucun codec vidéo**
- Source amont : https://ffmpeg.org — https://git.ffmpeg.org/ffmpeg.git

### Ligne `configure` exacte

Elle est **gravée dans le binaire livré** et consultable à tout moment :

```
ffmpeg -version
```

Elle est également reproduite, avec le script de build complet et la liste figée
des décodeurs, dans [`docs/BUILDING_FFMPEG.md`](docs/BUILDING_FFMPEG.md).

Résumé : `--disable-gpl --disable-nonfree --disable-autodetect --enable-zlib
--enable-static --disable-shared --disable-network --disable-everything`, puis
réactivation ciblée des démuxeurs de conteneurs, de 220 décodeurs **audio**, des
parsers, du muxer `wav` et de l'encodeur `pcm_s16le`.

### Obligation LGPL (§4) — source disponible et droit de relink

FFmpeg étant lié **statiquement**, la LGPL-2.1 §4 impose de permettre à
quiconque de **remplacer FFmpeg par une version modifiée** et de reconstruire un
binaire équivalent. Cette obligation est remplie ainsi :

1. **FFmpeg reste un exécutable séparé.** L'application ne se lie pas à FFmpeg :
   elle le lance en sous-processus (`fork`/`exec`), les échanges passent par
   arguments de ligne de commande et fichiers. Le code de NONP Transcription
   n'est donc pas une œuvre dérivée des bibliothèques FFmpeg, et sa licence
   MPL-2.0 est sans effet sur la présente obligation, qui porte sur le seul
   binaire `ffmpeg`.
2. **La source correspondante est mise à disposition** — version amont exacte,
   empreinte SHA-256, ligne `configure` et script de build : voir
   [`docs/BUILDING_FFMPEG.md`](docs/BUILDING_FFMPEG.md).
3. **Le relink est réalisable** en suivant ce document : il reconstruit un
   binaire fonctionnellement équivalent, à partir de sources FFmpeg modifiées si
   l'utilisateur le souhaite.

> **Source hébergée : [à compléter]**
> Une copie de l'archive source amont sera déposée avec le paquet de
> distribution. L'URL sera renseignée ici à l'étape de mise en ligne — voir
> [`third_party/ffmpeg/README.md`](third_party/ffmpeg/README.md).

### Texte de licence

Le texte intégral de la **GNU Lesser General Public License, version 2.1** est
disponible auprès du projet FFmpeg (fichier `COPYING.LGPLv2.1` de l'archive
source) et sur https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html

```
FFmpeg is free software; you can redistribute it and/or modify it under the
terms of the GNU Lesser General Public License as published by the Free
Software Foundation; either version 2.1 of the License, or (at your option)
any later version.

FFmpeg is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
details.

You should have received a copy of the GNU Lesser General Public License along
with FFmpeg; if not, write to the Free Software Foundation, Inc., 51 Franklin
Street, Fifth Floor, Boston, MA 02110-1301 USA
```

---

## zlib — bibliothèque **système**, non redistribuée

`ffmpeg` utilise zlib (décompression d'entêtes et de pistes Matroska). Elle
n'est **pas embarquée** dans l'application : le binaire se lie à
**`/usr/lib/libz.1.dylib`**, fournie par macOS. Aucun fichier zlib n'est
redistribué ici ; cette mention est un simple *acknowledgment*.

- Projet : https://zlib.net — licence zlib

```
zlib License

(C) 1995-2024 Jean-loup Gailly and Mark Adler

This software is provided 'as-is', without any express or implied warranty. In
no event will the authors be held liable for any damages arising from the use
of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim
   that you wrote the original software. If you use this software in a
   product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
```

---

## Vérification

L'absence de toute dépendance non système est **vérifiée au build** :
`Scripts/build_app.sh` échoue si un binaire embarqué référence autre chose que
`/usr/lib/` ou `/System/Library/`. Contrôle manuel :

```sh
otool -L "NONP Transcription.app/Contents/Resources/bin/ffmpeg"
otool -L "NONP Transcription.app/Contents/Resources/bin/whisper-cli"
```

## Empreintes des binaires redistribués

| Binaire | SHA-256 |
|---|---|
| `ffmpeg` (8.1.2, LGPL statique) | `660f3b68ed5626495b87a51b632f58f3cddd0a4a32b44c9e519d25fdcf300155` |
| `whisper-cli` (1.9.1) | `9c950af9234d1b3f41557650b78a161963c03e77e0979e7b00d0f196a7aee2fe` |
