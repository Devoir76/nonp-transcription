# NONP Transcription

**Transcription locale, fidèle, sans limite.**

Application macOS **libre et open source** qui transcrit vos fichiers **audio et vidéo** en texte et
sous-titres (TXT, SRT, VTT), **entièrement sur votre Mac**. Aucune donnée n'est envoyée sur Internet,
aucun abonnement, aucune limite de durée.

Elle repose sur [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (modèle Whisper *large-v3*
par défaut, ou *large-v3-turbo*, accélérés par Metal) et [FFmpeg](https://ffmpeg.org), tous deux
embarqués dans l'application.

> **Pourquoi « open source » compte ici.** Le code est public : n'importe qui peut vérifier que la
> transcription se fait **100 % localement** et que **rien ne quitte votre Mac**. Pour des enregistrements
> sensibles — témoignages, entretiens — cette promesse de confidentialité est ainsi **vérifiable**, pas
> seulement affirmée.

## Fonctions
- **Transcription locale** d'audio et de vidéo (MP4, MOV, MKV, AVI, MP3, WAV, M4A).
- **Formats de sortie** au choix : **TXT** (texte), **SRT** et **VTT** (sous-titres horodatés).
- **Langue** : détection automatique ou choix explicite (mémorisé).
- **Qualité** : « Qualité maximale » (*large-v3*, par défaut) ou « Rapide » (*large-v3-turbo*).
- **Fidélité** : le texte produit par Whisper n'est jamais réécrit ni reformulé.
- **Intégrité des modèles** : empreinte SHA-256 vérifiée (un modèle corrompu est refusé).
- **Sans abonnement, sans limite de durée, 100 % hors ligne** une fois le modèle installé.

## Prérequis
- **macOS 14 (Sonoma)** ou plus récent.
- **Mac Apple Silicon (M1 ou plus récent).**
- Environ **3,1 Go** d'espace disque pour le modèle (téléchargé une seule fois au premier lancement),
  ou **1,6 Go** avec le préréglage « Rapide ».

## Installation
1. Téléchargez la dernière version depuis la page
   **[Releases](https://github.com/Devoir76/nonp-transcription/releases/latest)** du dépôt
   ou depuis **[nonp.fr](https://nonp.fr/)** (fichier `.zip`) — les deux servent la même
   archive, empreinte SHA-256 publiée à côté.
2. Décompressez-le et glissez **NONP Transcription** dans votre dossier **Applications**.
3. **Premier lancement.** L'application étant distribuée librement et gratuitement (sans certificat Apple
   payant), macOS affiche un avertissement de sécurité au premier lancement. C'est normal. Pour l'autoriser :
   - ouvrez **Réglages Système → Confidentialité et sécurité** ;
   - descendez jusqu'au message concernant « NONP Transcription » et cliquez sur **« Ouvrir quand même »**.

   *(Sur macOS Sequoia et versions ultérieures, ce passage par les Réglages Système remplace l'ancien
   « clic droit → Ouvrir ».)*
4. *(Optionnel, recommandé.)* Vérifiez l'intégrité de votre téléchargement avec l'empreinte SHA-256
   publiée à côté du fichier :

   ```
   shasum -a 256 "NONP Transcription.zip"
   ```
5. Au premier lancement, l'application télécharge le modèle de transcription **une seule fois** :
   **~3,1 Go** pour « Qualité maximale » (*large-v3*, réglage par défaut), **~1,6 Go** pour « Rapide »
   (*large-v3-turbo*). Ensuite, tout fonctionne **hors ligne**.

## Utilisation
1. Glissez un fichier audio ou vidéo dans la fenêtre.
2. Choisissez la **langue** et le(s) **format(s)** de sortie.
3. Cliquez sur **Transcrire**. Les fichiers sont générés à côté du média (ou dans le dossier de votre choix).

## Confidentialité
Toute la transcription se déroule **sur votre Mac**. L'application n'envoie aucune donnée sur Internet : la
seule connexion réseau est le **téléchargement initial du modèle**. Ensuite, elle fonctionne entièrement
hors ligne.

## Licence
NONP Transcription est distribué sous **MPL-2.0** (voir [`LICENSE`](LICENSE)). Il embarque
FFmpeg (LGPL-2.1 ou ultérieure), whisper.cpp (MIT) et le modèle Whisper (MIT) — voir
[`THIRD_PARTY_NOTICES`](THIRD_PARTY_NOTICES.md).

## Construire depuis les sources
L'application se compile sans Xcode, avec SwiftPM (macOS 14+) :

```
./Scripts/build_app.sh            # build de développement
./Scripts/build_app.sh --release  # build de production
```

Détails (architecture, dépendances embarquées, mise à jour des binaires, tests `--selftest`) :
voir [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Origine
NONP Transcription est né du projet mémoriel **NONP** ([nonp.fr](https://nonp.fr/)), pour aider à
transcrire fidèlement des témoignages. Il est proposé gratuitement à toutes et tous.

## Contribuer
Les contributions sont bienvenues — voir [`CONTRIBUTING.md`](CONTRIBUTING.md).
