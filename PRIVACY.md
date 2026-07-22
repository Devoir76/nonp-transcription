# Confidentialité

NONP Transcription fonctionne **entièrement hors ligne**. Aucune donnée ne quitte
votre Mac : ni les médias, ni les transcriptions, ni les réglages, ni les journaux.
L'application n'effectue aucune requête réseau, hormis le téléchargement initial du
modèle de transcription, que vous déclenchez vous-même.

## Journalisation de diagnostic

L'application écrit quelques lignes dans la **journalisation unifiée de macOS**, le
mécanisme système que l'on consulte avec Console.app ou la commande `log`.

Ces lignes servent à diagnostiquer un défaut connu de mémorisation des réglages.
Elles enregistrent, à chaque lancement et à chaque modification d'un réglage :

- le mode de sortie choisi (à côté de la vidéo, ou dossier fixe) ;
- l'état de l'option d'ouverture automatique du dossier ;
- si chaque réglage a bien été retrouvé au démarrage, ou s'il manquait ;
- si une valeur qui vient d'être écrite se relit correctement.

### Le chemin de votre dossier n'est jamais écrit en clair

Seules une **empreinte tronquée et non réversible** (4 octets) et la longueur du
chemin sont visibles. L'empreinte permet de vérifier qu'une valeur écrite et une
valeur relue sont bien la même, sans jamais révéler laquelle.

La valeur brute est marquée `private` : macOS la masque — elle apparaît comme
`<private>` — dans toute collecte de journaux ordinaire, y compris celles que vous
pourriez transmettre à un tiers.

### Rien n'est conservé durablement

Ces journaux restent locaux, dans le tampon circulaire du système, et macOS les
efface automatiquement au fil du temps. **L'application ne crée aucun fichier de
diagnostic** et n'envoie rien nulle part.

### Les consulter

Les lignes sont regroupées sous un sous-système qui est **l'identifiant de
l'application** — aujourd'hui `com.nonp.transcription` — et sous la catégorie
`preferences`. Si l'application est un jour renommée, l'identifiant change et le
sous-système suit automatiquement : la commande ci-dessous s'adapte en remplaçant
l'identifiant par le nouveau.

```
log show --last 1h --predicate 'subsystem == "com.nonp.transcription"'
```

Pour ne suivre que les réglages :

```
log show --last 1h --predicate 'category == "preferences"'
```

Pour **exclure** ces lignes d'un partage de journaux, filtrez sur ce même
sous-système.
