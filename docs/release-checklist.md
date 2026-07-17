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

### Cas V1.1.0 (prochaine release)

- [ ] Version affichée = **`1.1.0`**
- [ ] `CFBundleVersion` **≥ 2**
- [ ] Commit du binaire validé, identifié sans ambiguïté
- [ ] Tag `v1.1.0` posé exactement sur ce commit

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
