# third_party/ffmpeg — emplacement de la source correspondante

Ce dossier accueillera la **copie archivée de l'archive source FFmpeg** utilisée
pour construire le binaire redistribué, au titre de l'obligation **LGPL-2.1 §4**.

## Hébergement retenu

| | |
|---|---|
| Fichier | `ffmpeg-8.1.2.tar.xz` |
| Taille | ~11,7 Mo |
| SHA-256 | `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c` |
| URL amont | https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz |
| **Source hébergée** | **https://nonp.fr/transcription** — section « Licences » |

L'archive est publiée **avec le paquet de l'application**, sur la page stable
`nonp.fr/transcription`. Le dépôt ne porte donc pas les 11,7 Mo de l'archive :
ce dossier ne garde qu'un pointeur, et la recette de reconstruction vit dans
[`../../docs/BUILDING_FFMPEG.md`](../../docs/BUILDING_FFMPEG.md).

Contrepartie assumée : **le lien doit rester vivant aussi longtemps que le
binaire est distribué** — c'est ce qu'exige la LGPL. Toute refonte de
`nonp.fr` doit préserver cette URL, ou mettre à jour les deux emplacements
ci-dessous.

## Reste à faire à l'étape paquet

- [ ] Déposer l'archive à l'adresse ci-dessus, en même temps que le ZIP de
      l'application — **la page `nonp.fr/transcription` n'existe pas encore**.
- [ ] Vérifier que l'URL sert bien le fichier et que son empreinte correspond.

Tant que ce dépôt n'est pas fait, la conformité repose sur
[`../../docs/BUILDING_FFMPEG.md`](../../docs/BUILDING_FFMPEG.md) — version
exacte, URL amont, empreinte SHA-256, ligne `configure` et script de build —
ce qui suffit tant que l'amont FFmpeg reste accessible. La copie archivée est la
garantie qui rend l'obligation **indépendante** de l'amont.

```sh
curl -fL -o ffmpeg-8.1.2.tar.xz https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
shasum -a 256 ffmpeg-8.1.2.tar.xz
# doit afficher 464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c
```

## Les deux emplacements à tenir à jour

Si l'URL change, corriger **les deux** :

1. ce fichier (table ci-dessus) ;
2. [`../../THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md), section FFmpeg.
