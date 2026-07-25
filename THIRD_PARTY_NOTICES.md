# THIRD_PARTY_NOTICES

NONP Transcription est distribué sous **GPL-3.0-or-later** (voir `LICENSE`). Il embarque et redistribue
les composants tiers ci-dessous, sous leurs licences respectives.

## FFmpeg — GPL-3.0-or-later
Version 8.1.2 (build Homebrew). Construit avec `--enable-gpl --enable-version3`, liant notamment
**libx264** et **libx265** (tous deux GPL) : l'ensemble redistribué est donc sous GPL v3.
- Texte de licence : voir `LICENSE` (GNU GPL v3).
- Source correspondante (obligation GPL §6) : FFmpeg — https://ffmpeg.org (v8.1.2) ; x264 —
  https://www.videolan.org/developers/x264.html ; x265 — https://www.videolan.org/developers/x265.html ;
  formule de build : Homebrew `ffmpeg`.
- Autres bibliothèques liées (permissives) : libopus (BSD), libvpx (BSD), libdav1d (BSD), libSvtAv1 (BSD),
  libmp3lame (LGPL-2.1+), OpenSSL/libcrypto (Apache-2.0), libvmaf (BSD-2-Patent).

## whisper.cpp — MIT
Bibliothèque de transcription (binaire `whisper-cli`), autonome (non lié à FFmpeg).
Source : https://github.com/ggerganov/whisper.cpp

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

## Modèle Whisper (ggml-large-v3, ggml-large-v3-turbo) — MIT
Poids GGML dérivés des modèles OpenAI Whisper (licence MIT).
Source des poids : https://huggingface.co/ggerganov/whisper.cpp

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
