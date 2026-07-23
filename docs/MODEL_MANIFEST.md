# MODEL_MANIFEST — empreintes de référence des modèles Whisper

Empreintes SHA-256 servant de garde-fou d'intégrité. **La valeur qui fait foi au
runtime est celle codée dans `WhisperModel`** (`Sources/NONPTranscription/Models/WhisperModel.swift`) ;
ce document en trace la provenance.

Provenance : dépôt `ggerganov/whisper.cpp` sur Hugging Face, branche `main`.
L'OID git-LFS d'un fichier **est** son SHA-256 — récupéré via le pointeur LFS
(`https://huggingface.co/ggerganov/whisper.cpp/raw/main/<fichier>`), sans
télécharger les Go de données.

| Modèle          | Taille (octets) | SHA-256                                                            | Provenance                                                |
|-----------------|-----------------|-------------------------------------------------------------------|-----------------------------------------------------------|
| large-v3        | 3 095 033 483   | `64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2` | OID LFS HF **+ recoupé localement** (modèle installé sain) |
| large-v3-turbo  | 1 624 555 275   | `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69` | OID LFS HF                                                |

Relevé le 2026-07-23.

## Quand la vérification a lieu

- **Après téléchargement (obligatoire, destructif)** : taille puis SHA-256 ; un
  fichier non conforme est supprimé et l'UI invite à re-télécharger.
- **Bouton « Vérifier maintenant » (à la demande, non destructif)** : recalcule
  l'empreinte du modèle installé ; sur écart, le fichier n'est **pas** supprimé,
  l'état passe « non conforme » et la transcription est bloquée en amont.

Pas de vérification par transcription ni de re-vérification automatique par session
(le SHA-256 d'un modèle de ~3 Go coûte ~7 s).
