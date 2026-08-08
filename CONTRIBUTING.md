# Contribuer à NONP Transcription

Merci de l'intérêt que vous portez au projet. NONP Transcription est un logiciel **libre et open source**
(MPL-2.0), né du projet mémoriel NONP.

## Signaler un bug ou proposer une idée
Ouvrez une *issue* en décrivant le problème (ou l'idée), votre version de macOS, et — pour un bug — les
étapes pour le reproduire.

## Proposer du code (pull request)
1. Créez une branche à partir de `main`.
2. Gardez les changements **ciblés** : une fonctionnalité ou un correctif par pull request.
3. Compilez et lancez les tests avant de soumettre (voir [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md),
   mode `--selftest`).
4. Ouvrez la pull request en expliquant le *pourquoi* du changement.

## Principes à respecter (le cœur du projet)
Toute contribution doit préserver les invariants du produit :
- **Fidélité** : le texte transcrit n'est jamais réécrit, reformulé, corrigé ni « nettoyé » automatiquement.
- **100 % local** : aucune donnée envoyée sur Internet, aucune télémétrie, aucun appel réseau en dehors du
  téléchargement du modèle.
- **Sobriété** : une fonctionnalité doit justifier sa valeur au regard de sa complexité et de son coût de
  maintenance.

## Certificat d'origine (DCO)
Ce projet utilise le **Developer Certificate of Origin**. En signant vos commits, vous certifiez que vous
avez le droit de soumettre votre contribution sous la licence du projet (MPL-2.0).

Signez vos commits avec l'option `-s` :

```
git commit -s -m "votre message"
```

Cela ajoute une ligne `Signed-off-by: Votre Nom <email>`. Le texte complet du DCO est disponible sur
https://developercertificate.org.

## Licence
En contribuant, vous acceptez que votre contribution soit distribuée sous la licence du projet,
**MPL-2.0**.
