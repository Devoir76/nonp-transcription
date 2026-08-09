# Checklist de release

Documentation uniquement. Décrit la procédure de release et les vérifications à
effectuer avant de poser un tag de version. Aucune automatisation ici.

## Séquence de release (ordre impératif)

1. **Validation d'usage** de la version candidate (tests réels).
2. **Fusion** de la branche de fonctionnalité dans `main`.
3. **Compilation propre depuis `main`** (`./Scripts/build_app.sh --release`).
4. **Vérification du `.app` final** (voir checklist ci-dessous).
5. **Test rapide** du binaire compilé (lancement + une transcription courte).
6. **Tag de version** posé **exactement sur le commit** ayant produit le binaire vérifié.

> Le tag n'est posé qu'à la toute fin, sur le commit exact du binaire validé —
> jamais en amont de la compilation depuis `main`.

## Vérification du `.app` compilé (avant le tag)

À contrôler sur le **bundle réellement compilé**, pas sur les sources :

- [ ] Version affichée (« À propos », `CFBundleShortVersionString`) = la version cible.
- [ ] `CFBundleVersion` (numéro de build) cohérent et croissant.
- [ ] Identifiant de bundle attendu (production, `--release`).
- [ ] Commit ayant produit le binaire identifié sans ambiguïté.
- [ ] Tag de version posé exactement sur ce commit.

### Cas V1.2.1 (release courante)

- [ ] Version affichée = **`1.2.1`**
- [ ] `CFBundleVersion` = **`6`** (croissant depuis le build 5 de la 1.2.0)
- [ ] Identifiant de bundle = **`com.nonp.transcription`** (production, `--release`)
- [ ] Commit du binaire validé = le **commit de préparation de la release 1.2.1**,
      identifié sans ambiguïté
- [ ] Tag **`v1.2.1`** posé exactement sur ce commit

## Test de mise à niveau depuis V1.0 (release production uniquement)

À exécuter sur le `.app` de release (`--release`, identifiant
`com.nonp.transcription`), **jamais** sur le build `.test`. Vérifie qu'une
installation existante en V1.0 passe proprement à la V1.1.

Ordre impératif :

1. [ ] **Archiver la V1.0 d'abord — ne pas la supprimer.** Créer une archive
   **ZIP non exécutable** de `/Applications/NONP Transcription.app`, conservée
   pour permettre un retour arrière.
2. [ ] **Installer réellement la V1.1** dans `/Applications`, en remplacement effectif
   de la V1.0.
3. [ ] **Lancer la bonne version** : « À propos » = `1.1.0`, identifiant de bundle
   = `com.nonp.transcription` (production).
4. [ ] **Absence de redirection** vers une ancienne copie : LaunchServices ouvre bien
   la V1.1 de `/Applications` (aucune copie V1.0 résiduelle ne prend la main).
5. [ ] **Valeurs par défaut correctes** : la V1.0 n'ayant aucun réglage, la V1.1 doit
   démarrer sur ses défauts (sortie « à côté de la vidéo », ouverture automatique
   activée). Ce test vérifie les défauts, pas une reprise de réglages inexistants.
6. [ ] **Reconnaissance du modèle existant** : le modèle déjà téléchargé
   (`~/Library/Application Support/NONP Transcription/Models/`) est reconnu ;
   **aucun téléchargement de 3,1 Go** n'est déclenché.

Test séparé (persistance des nouveaux réglages) :

7. [ ] **Persistance après relance** : modifier un réglage dans la V1.1, **quitter
   (⌘Q) puis relancer** → le réglage est conservé.

En cas d'anomalie : **restaurer la V1.0 depuis l'archive ZIP** (retour arrière).

## Règle de versionnement

À partir de **V1.1**, le **tag Git** et `CFBundleShortVersionString` **doivent
toujours coïncider**. Toute divergence bloque la release jusqu'à correction.

## Note historique — omission de version `v1.0.0`

Fait, sans justification rétroactive :

Le tag `v1.0.0` pointe vers le commit `68c5d09877c6b152a70678c47fedc6c7d024d788`,
dont le binaire affiche `CFBundleShortVersionString = 0.1.0` (build `1`). Le nom du
tag et la version interne de l'application **ne coïncident pas**.

Il s'agit d'une **omission au moment du tag**. Elle n'est **pas** corrigée, afin de
ne pas réécrire un tag déjà publié. `v1.0.0` reste un **jalon historique**. L'alignement
entre tag et version affichée commence à partir de V1.1.
