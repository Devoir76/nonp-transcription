# ADR-0003 — Licence du projet : GPL-3.0-or-later

- **Statut** : **Superseded by [ADR-0005](0005-ffmpeg-lgpl-et-licence-mpl.md)** (2026-08-08)
- **Date** : 2026-07-23
- **Déclencheur** : préparation de la publication open source. La reco initiale
  (mémoire active / roadmap) était **MPL-2.0** ; l'audit du FFmpeg embarqué la
  remet en cause.

## Contexte

Le cap est de publier NONP Transcription **en open source, gratuit, en
téléchargement libre** sur `nonp.fr`. La licence n'était pas arrêtée (cf.
ADR-0001, qui laisse explicitement la question ouverte) et la reco de départ
était **MPL-2.0**.

L'audit du **FFmpeg embarqué** (paquet Homebrew, v8.1.2) tranche la question :

- La ligne `configuration:` contient `--enable-gpl` **et** `--enable-version3` ;
  `ffmpeg -L` renvoie « GPL version 3 or later ».
- Liaisons GPL confirmées : **libx264** et **libx265** (encodeurs vidéo). Une
  **seule** bibliothèque GPL suffit à imposer la GPL au binaire ; il y en a
  **deux**.
- Pas de `--enable-nonfree` → le binaire **est redistribuable** (aucun blocage,
  pas besoin de rebâtir pour publier).

Ces encodeurs vidéo **ne sont pas utilisés** par l'application, qui se contente
de **décoder l'audio** pour Whisper. La GPL est donc **héritée du paquet
Homebrew**, non d'un besoin fonctionnel.

Les autres composants embarqués sont permissifs :

- **whisper.cpp** = **MIT** ; binaire `whisper-cli` **autonome**, non lié à
  FFmpeg (`otool -L` : seulement des frameworks système Apple).
- **Modèle Whisper** (`ggml-large-v3` / `-turbo`) = **MIT** (modèles OpenAI dont
  les GGML héritent).

**Aucun fichier de licence n'est présent aujourd'hui** — ni dans le dépôt, ni
dans le bundle `.app`.

Conséquence : **distribuer un binaire GPLv3 (FFmpeg) dans le même produit impose
la GPLv3 à l'ensemble redistribué**. MPL-2.0 est **incompatible en l'état**.

## Décision

1. **Licencier NONP Transcription sous `GPL-3.0-or-later`**, en cohérence avec la
   contrainte du FFmpeg embarqué et avec le cap « libre et vérifiable ».

2. **Obligations à remplir** (chantiers de la prépa open source) :
   - `LICENSE` : le texte intégral de la **GPLv3** ;
   - `THIRD_PARTY_NOTICES` : **FFmpeg** (GPLv3) + **libx264 / libx265** (GPL) ;
     **whisper.cpp** (MIT) ; **modèle Whisper** (MIT) ;
   - **publication du code source correspondant** (dépôt public), au titre de
     l'obligation GPL de fourniture de la source.

3. **Portée des obligations** : les **utilisateurs** ne sont **pas contraints**
   (usage libre, gratuit). Les obligations portent sur la
   **redistribution / modification** : garder le code **ouvert et sous GPL**.

## Alternative écartée (pour l'instant)

**Rebâtir un FFmpeg LGPL** — sans `--enable-gpl`, sans libx264/libx265, en se
limitant au **décodage audio** (seul besoin réel de l'app). Cela permettrait une
licence **permissive** (MPL-2.0) et un binaire **plus léger**.

Écartée pour la **première publication** : le chantier suppose rebuild +
ré-embarquement + re-test du pipeline audio et de la durée MKV/AVI +
re-packaging. Elle reste la **porte de sortie** si une version
permissive/commerciale devient souhaitée.

## Conséquences

- **(+)** Publication **rapide et légale** ; l'outil reste **libre et ouvert
  durablement** ; argument fort « **open source = vérifiable** » pour la
  confidentialité des témoignages.
- **(−)** Pas de version **propriétaire/fermée** de cette build tant que FFmpeg
  reste GPL. Les contributions externes seraient **en GPLv3** ; un futur passage
  permissif exigerait **à la fois** le rebuild FFmpeg LGPL **et** l'accord des
  contributeurs — d'où l'intérêt d'un **DCO/CLA** si des contributions sont
  acceptées.
- La revendication « open source » n'est **vraie qu'une fois le dépôt rendu
  public** : **annonce et publication du dépôt vont de pair**.
