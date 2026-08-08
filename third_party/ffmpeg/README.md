# third_party/ffmpeg — emplacement de la source correspondante

Ce dossier accueillera la **copie archivée de l'archive source FFmpeg** utilisée
pour construire le binaire redistribué, au titre de l'obligation **LGPL-2.1 §4**.

## État : emplacement réservé, archive non encore déposée

| | |
|---|---|
| Fichier attendu | `ffmpeg-8.1.2.tar.xz` |
| Taille | ~11,7 Mo |
| SHA-256 | `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c` |
| URL amont | https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz |
| **Source hébergée** | **[à compléter]** |

L'archive et l'URL de l'offre écrite se décident à l'**étape paquet**, parce
qu'elles dépendent de l'hébergement retenu pour le ZIP de l'application.

## Décision en attente : où vit l'archive

Deux options, à trancher avec l'hébergement du paquet :

1. **Dans le dépôt** (ici même). La source voyage avec le code, rien à
   maintenir. Coût : +11,7 Mo dans l'historique Git, définitivement.
2. **À côté du paquet distribué** (même hébergement que le ZIP), ce dossier ne
   gardant qu'un pointeur. Dépôt léger, mais un lien à maintenir vivant — et la
   LGPL demande que la source reste disponible aussi longtemps que le binaire
   est distribué.

Tant que la décision n'est pas prise, la conformité repose sur
[`../../docs/BUILDING_FFMPEG.md`](../../docs/BUILDING_FFMPEG.md) : il donne la
version exacte, l'URL amont, l'empreinte SHA-256, la ligne `configure` et le
script de build. C'est suffisant tant que l'amont reste accessible ; la copie
archivée est la garantie qui rend l'obligation indépendante de l'amont.

## Quand l'archive sera déposée

```sh
curl -fL -o third_party/ffmpeg/ffmpeg-8.1.2.tar.xz \
  https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
shasum -a 256 third_party/ffmpeg/ffmpeg-8.1.2.tar.xz
# doit afficher 464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c
```

Renseigner ensuite « Source hébergée » ici **et** dans
[`../../THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md).
