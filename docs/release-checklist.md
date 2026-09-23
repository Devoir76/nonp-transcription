# Checklist de release

Documentation uniquement : la procédure et les vérifications à dérouler avant de
poser un tag. Aucune automatisation ici — un script qui coche des cases à votre
place ne prouve rien.

Chaque case de ce fichier a coûté un incident, mesuré, daté. Celles qui viennent
de NONP Habillage sont signalées : les deux applications partagent une machine,
une chaîne d'outils et un mode de distribution, et ce qui a mordu sur l'une
mordra sur l'autre.

> **Les binaires embarqués font la moitié de ce document.** FFmpeg et
> whisper.cpp voyagent dans le bundle : il y a donc une source correspondante à
> servir, des empreintes à tenir, des textes de licence à embarquer. Habillage
> n'a rien de tout cela — sa checklist est la même, moins cette moitié.

---

## La règle qui commande tout

> ⛔ **UN ZIP PUBLIÉ NE SE RÉGÉNÈRE JAMAIS.** Son empreinte est publiée et le
> build n'est pas reproductible (horodatages, signature ad-hoc) : régénérer
> produit un fichier **différent** sous le même nom, que les empreintes déjà
> annoncées n'authentifient plus. Toute correction, **même d'une ligne**, impose
> une **version nouvelle** — incrément, nouveau ZIP, nouvelle empreinte, page
> mise à jour.

> ⛔ **Ne jamais supprimer une release qui a distribué un binaire** sans
> republier sa source correspondante ailleurs. L'obligation LGPL §4 survit à la
> release qui l'a créée.

---

## Séquence de release (ordre impératif)

1. **Validation d'usage** de la version candidate, sur médias réels.
2. **Harnais au vert** : `./Scripts/test_bug007.sh` sans un échec, puis les
   modes qui exigent un média et le modèle (voir « Le harnais »). Une rubrique
   non exécutée n'est pas une rubrique réussie.
3. **Compilation sans un seul avertissement**, depuis un `.build` effacé.
   **Exceptions nommées**, et elles seules :
   - l'avertissement SwiftPM « `--build-system native` has been deprecated » —
     il vient de l'option que pose `Scripts/sdk_macos.sh`, pas du code, et
     partira avec ce contournement ;
   - les avertissements `Sendable` de `SelfTest.swift` sur `UserDefaults` —
     harnais de test, pas produit. Ils deviendront bloquants au passage au mode
     de langage Swift 6 ; ce jour-là, ils se corrigent, ils ne se tolèrent plus.

   Tout AUTRE avertissement reste bloquant.
4. **Fusion** de la branche dans `main`.
5. **Compilation propre depuis `main`** : `./Scripts/build_app.sh --release`.
6. **Vérification du `.app` final** (ci-dessous), sur le bundle réellement
   compilé, jamais sur les sources.
7. **Fiche de test manuelle**, déroulée sur le binaire exact qui sera publié.
8. **Le jour du tag, juste avant de le poser** — voir « Le jour du tag ».
9. **Tag de version** posé **exactement sur le commit** ayant produit le binaire
   vérifié — jamais en amont de la compilation depuis `main`.
10. **Distribution**, sur les deux canaux, dans la foulée.

---

## La fabrication — trois gestes, dans cet ordre

> Mesuré le 21/09/2026 sur la **1.2.3 publiée** : son exécutable portait
> **29 entrées de débogage `N_OSO`**, **88 entrées `N_SO`** et **58 occurrences
> du dossier personnel** de la machine de fabrication — toutes dans la table des
> chaînes de symboles, **aucune dans le code**. Les sources du dépôt étaient
> propres : la fuite naissait à la fabrication, et aucun contrôle ne la voyait,
> le harnais ne regardant que le binaire nu, jamais le `.app`.

1. **`dsymutil`** — extrait la table de débogage **avant** de la détruire. Après
   le strip elle est perdue, et plus aucun rapport de plantage ne sera
   symbolisable. Le dSYM va **hors dépôt**, jamais dans `dist/`, jamais dans le
   ZIP : il porte exactement les mêmes chemins.
2. **`strip -S`** — retire la table du binaire. Mesuré : 58 → 0 occurrences,
   117 → 0 entrées `OSO`/`SO`. Le strip complet ne retire rien de plus côté
   fuite.
3. **`codesign` EN DERNIER** — `strip` invalide la signature et le dit lui-même
   en avertissement. Signer avant le strip, c'est livrer un bundle que macOS
   déclare « endommagé ».

**Seul l'exécutable de l'application est strippé.** Les moteurs de
`Resources/bin` sont versionnés dans `Vendor/bin`, redistribués **à l'identique**
et leurs empreintes sont publiées : les modifier casserait
`THIRD_PARTY_NOTICES.md`. Mesuré : ils ne portent déjà aucune entrée de débogage
ni aucun chemin personnel.

---

## Les quatre gardes, et leurs témoins

`Scripts/build_app.sh` arrête la fabrication sur chacune. **Une garde dont on
n'a jamais vu l'échec n'est pas une garde** : l'option `--verifier <bundle.app>`
les braque sur un bundle existant, sans rien compiler ni modifier, pour le
prouver.

- [ ] **Chemins et entrées de débogage.** Aucune entrée `OSO`/`SO`, zéro
      occurrence du dossier personnel, sur **tous** les Mach-O du bundle —
      découverts, pas énumérés, pour que l'ajout d'un binaire à `Resources/bin`
      soit contrôlé sans qu'on y pense. La garde n'affiche jamais de valeur,
      seulement des comptes.
      *Témoin : elle doit échouer sur le bundle 1.2.3 publié.*
- [ ] **Langue déclarée.** `CFBundleDevelopmentRegion = fr` et
      `CFBundleLocalizations = ["fr"]` dans l'`Info.plist` du bundle **assemblé**
      — pas dans la source. Sans eux, macOS tient l'application pour anglaise et
      affiche en anglais **tous** les menus qu'il fournit : l'application n'en
      déclare aucun elle-même.
      *Témoin : elle doit échouer sur le bundle 1.2.3 publié, qui ne déclarait
      aucune langue.*
      Vérifié à l'écran le 23/09 sur la 1.2.4 : **ces deux clés suffisent**,
      aucun dossier `fr.lproj` n'est nécessaire — même résultat que sur
      Habillage la veille.
- [ ] **Signature.** `codesign --verify --deep --strict` après le strip.
      *Témoin : elle doit échouer sur un bundle strippé APRÈS signature —
      l'ordre fautif.*
- [ ] **Marquage SDK.** Le `sdk` inscrit dans `LC_BUILD_VERSION` doit être celui
      du SDK réellement choisi, sur le binaire nu **et** sur le bundle assemblé
      après strip.
      *Témoin : elle doit échouer sur un bundle marqué d'un autre SDK.*

---

## La chaîne d'outils — contrainte propre à cette machine

> **Constaté le 17/09/2026 sur Habillage, reproduit le 23/09 sur Transcription.**
> Les Command Line Tools 27.0 livrent un SDK où `@State` est une macro, mais pas
> le plugin `SwiftUIMacros` qui l'implémente — introuvable sur toute la machine,
> faute d'Xcode. Toute compilation SwiftUI échoue, sans que rien ait changé dans
> le dépôt.

- [ ] **`Scripts/sdk_macos.sh` est appelé par `build_app.sh`.** Il éprouve le SDK
      par défaut avec une sonde SwiftUI, replie sur le plus récent qui passe, et
      refuse en nommant les issues si aucun ne convient — au lieu d'une avalanche
      d'erreurs dont la vraie cause tient en une ligne.
- [ ] **Le système de build décide du marquage, et le marquage décide des
      métriques d'AppKit.** Mesuré sur Habillage le 17/09 : le système par défaut
      de SwiftPM inscrit `sdk 14.0` — la version minimale du projet — quand
      `--build-system native` inscrit le SDK réel. `--sdk` n'y change rien.
      Conséquence mesurée, même code, même machine : 15 points d'ascenseur contre
      17, et 8 points d'écart sur une disposition.
- [ ] **Le marquage attendu est celui de la version précédente publiée.** La
      1.2.3 publiée porte `sdk 26.5` ; une version de nettoyage qui porterait
      autre chose changerait les métriques en prétendant ne rien changer.
      Contrôle : `vtool -show-build` sur l'exécutable → `sdk` attendu, `minos`
      cohérent avec `LSMinimumSystemVersion`.
- [ ] **Le SDK de repli est un exemplaire unique.** Une copie de sauvegarde vit
      hors de `/Library`, faite par `ditto` (elle contient des milliers de liens
      symboliques qu'une copie naïve aplatirait), et **éprouvée par la sonde** —
      pas seulement comparée en taille. Le chemin de cette copie se passe en
      `SDKROOT` le jour où l'original disparaîtrait ; `sdk_macos.sh` respecte un
      `SDKROOT` posé et l'éprouve au lieu de le remplacer en silence.
- [ ] **Condition de retrait du contournement** : le jour où le script annonce
      « SDK par défaut… aucun contournement ». Retirer alors le repli, mais
      **garder la garde de marquage** tant que le système de build par défaut
      n'a pas fait ses preuves.

---

## Vérification du `.app` compilé (avant le tag)

À contrôler sur le **bundle réellement compilé**, jamais sur les sources.

- [ ] `CFBundleShortVersionString` = la version cible.
- [ ] `CFBundleVersion` (numéro de build) cohérent et **croissant**.
- [ ] Identifiant de bundle = celui de **production**, obtenu par `--release`.
      Une build de test porte le suffixe `.test` et ne s'installe **jamais** dans
      `/Applications`.
- [ ] `CFBundleDevelopmentRegion` et `CFBundleLocalizations` déclarent le
      français.
- [ ] **`LSMinimumSystemVersion` cohérent avec ce qui est annoncé au
      téléchargement** — et avec `Package.swift`. Trois endroits, une seule
      valeur.
- [ ] **`lipo -archs` sur chaque Mach-O du bundle** → `arm64` seul. Rien dans le
      bundle ne signale cette exigence à l'utilisateur **avant** le
      téléchargement : c'est la page qui doit le dire.
- [ ] **Les trois textes de licence sont dans le bundle**
      (`Contents/Resources/Licenses/`) : la licence de l'application, le texte
      complet de la LGPL-2.1, et `THIRD_PARTY_NOTICES.md`. La fabrication les
      copie depuis le dépôt et s'arrête si l'un manque ou est vide.
- [ ] **Les empreintes des moteurs embarqués sont celles annoncées** dans
      `THIRD_PARTY_NOTICES.md`. Elles authentifient les binaires redistribués :
      si elles bougent sans que le document bouge, il ment.
- [ ] **Le modèle n'est PAS dans le bundle** — plusieurs gigaoctets, téléchargés
      à la demande dans le dossier de support de l'application. Vérifier qu'aucun
      `.bin` n'a été embarqué par mégarde.
- [ ] `codesign --verify --deep --strict` passe. Ce contrôle ne dit **rien** de
      l'archive : l'aller-retour sur le ZIP est plus bas.
- [ ] Commit ayant produit le binaire identifié sans ambiguïté, et tag posé
      exactement dessus.

---

## L'écueil de l'identifiant partagé

> **Mesuré le 23/09.** Deux exemplaires portant le même `CFBundleIdentifier`
> tournaient en même temps — l'un depuis `/Applications` (version précédente),
> l'autre depuis `dist/`. LaunchServices ne les distingue pas ; un réglage écrit
> par l'un est relu par l'autre, et aucune observation à l'écran n'est fiable.

**Avant tout test à l'écran** :

- [ ] **Écarter toute autre copie installée** portant l'identifiant de
      production — la déplacer, jamais la supprimer. Vérifier ensuite qu'il n'en
      reste aucune à l'emplacement d'installation.
- [ ] **Un seul processus** : `pgrep -x` sur le nom de l'exécutable rend **un**
      PID, et le code de sortie est montré.
- [ ] **Le lancement se prouve par `lsof`** : l'inode de l'exécutable réellement
      exécuté, comparé à celui de l'exemplaire visé. Le chemin affiché par `ps`
      peut désigner un fichier qui a changé de place depuis.
- [ ] **Le CDHash du bundle testé est celui attendu** — `codesign -dvvv`. C'est
      lui qui identifie sans ambiguïté « le binaire exact » dont parle la fiche.
- [ ] **Les copies de travail hors `dist/` sont recensées.** Une arborescence de
      sauvegarde d'une version antérieure contient souvent, elle aussi, un
      bundle au même identifiant.

---

## Le scan des noms réels

> **Règle née d'un angle mort, le 20/09.** Un filet ne peut pas attraper un nom
> qu'il ne connaît pas : un « zéro » obtenu avec un filet incomplet ne dit rien.
> Le contrôle paraissait vert et ne regardait rien.

**Tout nom réel entrant dans une mesure, un banc d'essai ou une fixture s'ajoute
au filet LE JOUR MÊME**, et le scan est rejoué avec le filet élargi.

> ⛔ **La liste des noms ne figure pas dans ce dépôt et ne doit jamais y
> figurer.** L'écrire ici reviendrait à réintroduire en clair, dans un dépôt
> public, exactement ce qu'une réécriture d'historique en a retiré : **le filet
> deviendrait la fuite qu'il sert à détecter.** L'erreur a été commise une fois,
> et c'est le scan lui-même qui l'a trouvée, en se signalant sur son propre
> texte. Elle vient du réflexe sain de documenter ce qu'on vérifie : elle se
> reproduira si rien ne la nomme.

Le filet, le registre des collisions et le script vivent **hors du dépôt**, dans
les notes privées du projet, en droits restreints. Ce qui se documente ici, c'est
la **méthode**, jamais les unités.

### Les trois pièges, mesurés le 21/09

Chacun a produit, ce jour-là, un résultat qui paraissait bon et ne l'était pas.

- [ ] **Motifs filtrés des commentaires et des lignes vides, et compte affiché.**
      Le fichier du filet est commenté ; passé tel quel à une recherche
      littérale, **une ligne vide est un motif qui correspond à tout** — le scan
      remonte alors chaque ligne de chaque fichier, et aucun zéro honnête n'est
      possible.
- [ ] **`/usr/bin/grep` en chemin absolu, et `type grep` affiché en tête de
      scan.** Le `grep` de l'environnement peut être une fonction qui en
      enveloppe un autre : celle rencontrée le 21/09 sautait les fichiers ignorés,
      **ne pouvait pas lire les objets git**, et passait les binaires. Un scan
      lancé avec elle rend un zéro qui ne veut rien dire.
- [ ] **Prouver le matcher ET l'énumérateur, séparément.**
      - *Matcher* : cycle **0 → 1 → 0** sur un faux texte réaliste, écrit hors du
        dépôt, l'aiguille injectée **octet pour octet**. Un outil de recopie a
        déjà altéré une unité accentuée et fait accuser le filet.
      - *Énumérateur* : afficher les comptes par surface. Un énumérateur vide
        rend lui aussi zéro.

⛔ **L'aiguille du témoin n'entre JAMAIS dans un objet git** — ni sur une branche
jetable, ni dans un commit défait ensuite. Un objet git écrit reste servi par son
empreinte jusqu'à un ramassage qu'on ne déclenche pas.

### Trois façons de rater un nom présent

- [ ] **Casse** : la comparaison porte sur des octets. Chaque unité se décline en
      minuscules et capitales.
- [ ] **Unicode** : les noms venus de fichiers macOS arrivent en **NFD**. Chaque
      unité accentuée se décline en NFC **et** NFD.
- [ ] **Coupures** : un nom long est coupé par les retours à la ligne, à des
      endroits qui changent. D'où une passe sur le **texte aplati** et la
      recherche du nom de famille seul.
- [ ] **Unités courtes : mot entier.** Insensible à la casse, une unité de
      quatre caractères mord du texte anglais ordinaire — y compris dans un texte
      de licence. Le mot entier supprime le faux positif sans rendre la casse.
- [ ] **Registre des collisions connues**, hors dépôt, à côté du filet. Une
      collision est une occurrence mesurée qui n'est pas une fuite — chaîne
      amont, texte de licence. **La règle est le COMPTE, pas la présence** : un
      compte différent de celui inscrit redevient une alerte, sinon une vraie
      fuite se cacherait derrière une collision connue.
- [ ] **La méthode vit dans un script**, pas dans des commandes retapées. Il
      porte tout — `type grep` affiché, chemin absolu, motifs filtrés et comptés,
      casse, NFC/NFD, texte aplati, registre, témoins, comptes par surface — et
      **il refuse de scanner si un témoin est rouge**. Son code de sortie fait
      foi : 0 propre, 1 alerte, 2 témoin rouge.

### Les surfaces à scanner

Trois surfaces suffisaient tant qu'on ne regardait que le dépôt ; elles ne
suffisent plus dès qu'on distribue.

- [ ] **Le dépôt** : contenus de tous les objets, chemins, messages de commit —
      auteur et committer compris, **par commit**.
- [ ] **Le bundle compilé, fichier par fichier, Mach-O compris**, sur les octets
      bruts. C'est là qu'était la fuite de la 1.2.3.
- [ ] **Le contenu du ZIP extrait**, fichier par fichier. Ce n'est pas la même
      surface que le bundle : l'empaquetage ajoute des choses.
- [ ] **Les documents présents dans l'arbre du dépôt, même non suivis.** Un
      fichier non suivi n'est pas protégé : s'il n'est pas ignoré, il apparaît
      dans `git status` et part avec un ajout global. Ils vivent hors dépôt, en
      droits restreints.
- [ ] **La sortie des tests.** Le harnais imprime des noms de fichiers de
      travail : cette sortie n'a sa place ni dans un dépôt, ni dans un rapport,
      ni dans un ticket.
- [ ] **Les métadonnées** : attributs étendus, dossier `__MACOSX` d'une archive,
      horodatages nominatifs. Voir « Le paquet ».
- [ ] **AVANT CHAQUE POUSSÉE, pas seulement la première.** Le dépôt est public :
      une erreur qui y arrive est définitive. Un force-push ne suffit pas — un
      objet retiré reste servi par son empreinte jusqu'à un ramassage qu'on ne
      déclenche pas. Mesuré ailleurs : il a fallu supprimer un dépôt et le
      recréer.
- [ ] **Vérifier que le scan SAIT VOIR avant de croire ses zéros.** Un « zéro »
      par environnement cassé est indiscernable d'un « zéro » par absence.

---

## Le harnais

`Scripts/test_bug007.sh` compile en debug et enchaîne les modes qui ne demandent
ni média, ni modèle, ni moteur : repli du dossier de sortie, persistance des
réglages dans un même process, puis **entre deux process** — seul cas qui
exerce le vrai mode d'échec de la persistance adossée au disque. Quelques
secondes, dont l'essentiel est la compilation.

- [ ] **83 contrôles au total** dans le harnais. Aucun ne doit échouer, et
      **aucune rubrique ne doit rester non exécutée** — une rubrique sautée n'est
      pas une rubrique réussie.
- [ ] Les tests de persistance écrivent dans une suite de réglages **isolée**,
      jamais dans les réglages réels, et vérifient que le domaine standard est
      resté intact. Le refus de tourner en root est volontaire : les bits de
      permission y sont ignorés, et les cas « non inscriptible » deviendraient
      des faux négatifs.
- [ ] **Les deux modes pipeline exigent un média réel ET le modèle installé.**
      Ils n'utilisent pas les contrôles comptés ci-dessus : ils impriment un
      compte rendu — nombre de segments, chemins des exports, nettoyage du
      temporaire, intégrité de la source. Les dérouler tous les deux : le mode
      complet et le mode d'annulation.
- [ ] **Le harnais voit le bundle quand on le lance depuis le bundle.** Lancé sur
      l'exécutable du `.app`, il trouve les moteurs dans les ressources ; lancé
      sur le binaire nu, il retombe sur le dossier du dépôt. C'est le premier
      qu'il faut éprouver avant une release : c'est celui qui part.

---

## La fiche de test manuelle

Le harnais couvre le moteur ; ces points-là demandent un œil. **La fiche se
déroule sur le binaire exact qui sera publié**, identifié par son CDHash, jamais
sur « une build équivalente ».

- [ ] **Les menus, menu par menu, élément par élément**, sous-menus compris —
      menu de l'application, Édition, Présentation, Fenêtre, Aide — plus la
      fenêtre « À propos », les menus contextuels et tous les volets. Un seul mot
      d'anglais ailleurs que dans un panneau fourni par Apple est un échec.
      *Hors critère* : les panneaux d'ouverture et d'enregistrement, qui tournent
      hors de l'application et suivent la langue du système.
- [ ] **Un fichier refusé nomme sa vraie cause.** Déposer un dossier, un format
      non pris en charge, un fichier de zéro octet : des messages distincts, et
      aucun qui conseille une manipulation inutile.
- [ ] **Aucun fichier d'entrée n'est jamais remplacé**, même en visant
      volontairement le média source dans le panneau d'enregistrement. Si macOS
      demande « Voulez-vous le remplacer ? », répondre **Remplacer** : ce dialogue
      est celui de macOS. C'est **après** lui que l'application doit refuser
      d'elle-même. S'arrêter avant, c'est laisser macOS protéger le fichier et ne
      rien prouver.
- [ ] **Une annulation ne laisse rien derrière elle** : ni export partiel, ni
      fichier temporaire. Vérifier le dossier de destination **fichiers cachés
      compris** — un temporaire oublié commence souvent par un point.
- [ ] **Aucun mot du texte transcrit n'a bougé** : c'est l'invariant du produit.
      Empreinte du fichier source comparée **avant et après**.
- [ ] **Vérifier l'effet, jamais le message.** Aucune confiance à un « ✓ »
      affiché : une option inexistante peut afficher l'aide et sortir en code 0.
      Ne pas filtrer la sortie d'une fabrication — le filtre peut masquer un
      plantage. Contrôler l'état résultant.

### Borner un retest sans le refaire en entier

Quand un binaire est refabriqué en cours de campagne, tout n'est pas à refaire —
mais il faut le **prouver**, pas le supposer.

- [ ] **Comparer l'identité de l'exécutable hors signature** : retirer la
      signature de deux copies, comparer octet pour octet et par empreinte. Si
      elles sont identiques et que seuls l'`Info.plist` et la signature intégrée
      diffèrent, **les contrôles déjà déroulés restent acquis** — on ne refait que
      ceux que le changement touche.
- [ ] **Sinon, tout est à refaire.** Et la fiche note quels binaires sont
      devenus caducs, avec leur empreinte : sans cela, personne ne sait plus sur
      quoi un résultat a été obtenu.

---

## Le paquet

Structure retenue (alignée sur Habillage) : un **dossier** portant le nom et la
version, contenant l'application **et** les textes de licence à sa racine — la
licence se lit sans ouvrir le paquet de l'application, en plus de la copie déjà
présente dans le bundle.

- [ ] **Travailler sur une copie de préparation, jamais sur `dist/`.** `dist/`
      reste intact : c'est la référence des tests.
- [ ] **Attributs étendus retirés de la copie** (`xattr -cr`) **avant**
      l'archivage. Mesuré sur le ZIP 1.2.3 publié : il contient un dossier
      `__MACOSX` avec un attribut étendu de la machine de fabrication. Ce ne sont
      pas des données de l'application, la signature ne les couvre pas, et les
      retirer ne change ni le contenu ni le CDHash.
- [ ] **Archive créée avec `ditto -c -k --sequesterRsrc --keepParent`** —
      **jamais** un zip ordinaire : il casse liens symboliques et métadonnées,
      donc la signature du bundle, et l'utilisateur reçoit « l'application est
      endommagée ».
- [ ] **Vérification aller-retour sur l'archive réellement produite** :
      décompresser le ZIP final, puis `codesign -v --deep --strict` **et** le
      Designated Requirement sur l'application **extraite**. Vérifier le bundle
      avant compression ne prouve rien sur l'archive.
- [ ] **Aucun attribut étendu sur les fichiers extraits**, et **aucun dossier
      `__MACOSX`** dans l'archive : c'est la preuve que le nettoyage a porté sur
      ce qui part.
- [ ] **Le contenu de l'archive est listé et relu** : rien de plus que ce qui
      doit s'y trouver.
- [ ] **Empreinte SHA-256 calculée sur l'archive réellement déposée**, pas sur un
      brouillon.

---

## Le contrôle Gatekeeper

Ce contrôle a une façon particulière d'échouer : **il réussit en silence.** Deux
tentatives de suite ont déjà paru prouver quelque chose sans rien prouver — une
application déjà lancée qu'un double-clic ramène au premier plan, et un
double-clic détourné vers une autre copie du même identifiant.

- [ ] **L'exemplaire testé est NEUF** : jamais lancé, portant sa propre marque de
      quarantaine. Un exemplaire déjà ouvert une fois ne redemandera rien, et une
      copie faite à partir d'un exemplaire déjà ouvert peut hériter de son
      accord — ce n'est pas mesuré, donc c'est un refus, pas une permission.
- [ ] **Avant publication**, quand le ZIP n'existe pas encore : une copie fraîche
      avec une quarantaine posée à la main suffit — le parcours obtenu est le
      même, mesuré.
- [ ] **Après publication**, sur le **vrai téléchargement** : ZIP récupéré **par
      un navigateur** — une récupération en ligne de commande ne pose pas la
      marque de quarantaine et ne teste donc pas ce que vit l'utilisateur — puis
      extrait par double-clic dans le Finder.
- [ ] **Le geste testé est celui des textes publiés** : glisser l'application à
      l'emplacement d'installation, puis double-cliquer.
- [ ] **Application quittée avant le test**, code de sortie montré.
- [ ] **Une capture avant chaque clic.** Les libellés se relèvent à l'écran, pas
      de mémoire : Apple les a déjà changés une fois, et le texte publié citait
      encore l'ancien.
- [ ] **Jamais la touche Entrée** dans ces dialogues : le bouton par défaut n'est
      pas toujours celui qu'on croit, et valider au clavier peut déclencher la
      mise à la corbeille.
- [ ] **Le refus se prouve par le journal du noyau**, la ligne nommant le chemin
      complet de l'exemplaire évalué. Un outil d'évaluation en ligne de commande
      ne sert à rien ici : il rend le même verdict sur une copie approuvée et sur
      une copie bloquée — il ne voit pas les accords donnés par l'utilisateur.
- [ ] **Verdict.** Le dialogue apparaît → conforme. **Une ouverture silencieuse
      n'est JAMAIS un succès** : sur un Mac où cette empreinte a déjà été
      approuvée à cet emplacement, le test est **non concluant** — refaire
      ailleurs.
- [ ] **Les libellés relevés sont reportés sur la page de téléchargement**, et
      **aucun repli « clic droit → Ouvrir » n'est présenté pour macOS 15 ou plus
      récent** : il est invalide depuis macOS 15 pour une application ad-hoc non
      notarisée. L'utilisateur qui l'essaie n'obtient rien et conclut que
      l'application est cassée. Le repli reste valide, et documenté, pour
      macOS 14.

---

## Obligations de licence

- [ ] **Le texte complet de la LGPL-2.1 accompagne le binaire FFmpeg
      redistribué** — dans le bundle, et à la racine du paquet.
- [ ] **La source correspondante de FFmpeg est servie**, dans la version exacte
      du binaire embarqué, **sur les deux canaux** : l'un ou l'autre doit
      toujours la porter, et elle survit à la release qui l'a introduite.
- [ ] **Le script de reconstruction du FFmpeg embarqué est versionné**, ainsi que
      la liste figée des décodeurs dont il dépend. Sans elle, la fabrication n'est
      plus reproductible, et l'obligation §4 n'est plus tenue.
- [ ] **`THIRD_PARTY_NOTICES.md` est à jour** : versions, commits, empreintes des
      binaires redistribués, ligne de configuration exacte de FFmpeg, et la
      procédure de vérification que l'utilisateur peut dérouler lui-même.
- [ ] **Les en-têtes de licence sont présents** sur les sources et les scripts.
- [ ] **Le fichier d'empreintes conserve la ligne de la source FFmpeg** à chaque
      mise à jour : elle reste la source correspondante du binaire embarqué,
      version après version.

---

## Le jour du tag

Quelques textes datent, et ils ne peuvent pas être justes avant ce moment.

- [ ] **La date de l'entrée du `CHANGELOG.md`** se fixe ici. Tant que le tag
      n'est pas posé, l'entrée porte « non publié » : un journal public qui
      affiche une date annonce une version téléchargeable.
- [ ] **Les phrases du `README.md` qui décrivent l'état de la publication** sont
      mises à jour au même moment.
- [ ] **Le ZIP publié est celui du binaire testé, et sa reproduction se prouve.**
      Les textes datés ci-dessus se retirent dans un commit **postérieur** à
      celui qui a produit le binaire testé ; aucun d'eux n'entre dans le bundle.
      Donc :
      - le ZIP est fabriqué **une fois**, depuis le binaire exact que la fiche de
        test a éprouvé, et c'est lui qui est publié ;
      - **au jour du tag**, fabrication propre (`.build` effacé) depuis le commit
        tagué : **son CDHash doit être identique** à celui du binaire testé ;
      - **s'il diffère**, on ne publie pas ce ZIP : on refait le ZIP depuis le
        commit tagué, et les tests avec — fiche comprise.

---

## Distribution

Le dépôt et le site sont deux endroits distincts : **un tag posé ne publie
rien.** Deux canaux, et l'ordre compte — le tag d'abord.

### Release GitHub

- [ ] Release créée **sur le tag de version**, avec en assets : l'archive ZIP
      **réellement validée**, la **source correspondante FFmpeg**, et le fichier
      d'empreintes.
- [ ] Empreintes vérifiées **après téléversement** : re-télécharger, recalculer,
      comparer.
- [ ] Aucune release ayant distribué un binaire n'est supprimée.

### Publication sur nonp.fr

À dérouler **en une seule fois** : un site qui annonce une version et en sert une
autre est pire que pas de mise à jour du tout.

- [ ] Archive copiée dans le dossier d'artefacts **et** dans le dossier servi.
- [ ] Fichier d'empreintes mis à jour, **ligne de la source FFmpeg conservée**.
- [ ] **Alias « dernière version » repointé** vers la nouvelle archive. L'oublier
      laisse l'alias servir silencieusement la version précédente. Redirection
      **302**, jamais 301 — la cible change à chaque version —, et c'est
      l'**empreinte du fichier servi via l'alias** qu'on vérifie, pas seulement le
      code de redirection.
- [ ] Page de téléchargement : version affichée, nom du fichier (lien **et**
      libellé accessible **et** texte du bouton), poids, empreinte, et le bloc de
      données structurées.
- [ ] **Les deux mentions de compatibilité**, aux mêmes endroits que sur l'autre
      page du site : la version minimale de macOS à côté du bouton, et
      l'incompatibilité avec les Mac à processeur Intel sous le poids du fichier.
      Les trois Mach-O sont `arm64` seul — sans cette mention, un utilisateur
      télécharge une application qui ne s'ouvrira jamais et conclut qu'elle est
      cassée.
- [ ] Après déploiement : **re-télécharger depuis le site** et vérifier que
      l'empreinte correspond à celle annoncée sur la page.
- [ ] Archive de la version précédente retirée du dossier servi ; son empreinte
      reste documentée au `CHANGELOG.md`.
- [ ] **Toute vérification de purge se fait avec un paramètre anti-cache.** Sans
      lui, purge réussie et purge ratée sont indiscernables.

### Vérifier ce que le dépôt public sert

Deux moitiés, et les confondre fait conclure à l'envers.

- [ ] **Une PRÉSENCE se vérifie par l'API de contenus, jamais par le CDN de
      fichiers bruts.** Le CDN sert une version périmée pendant un temps qu'on ne
      contrôle pas : un fichier fraîchement poussé y apparaît encore sans sa
      modification, et on conclut à tort à une poussée incomplète.
- [ ] **Une ABSENCE se vérifie sur les DEUX, CDN compris** — et par accès direct
      à l'empreinte de l'objet, en requête **non authentifiée** : une session
      connectée voit un dépôt privé exactement comme un dépôt public. C'est la
      moitié qui compte, celle du jour où l'on retire quelque chose qui ne doit
      plus être lisible.
- [ ] **Une absence se recontrôle après quelques heures.** Le cache expire seul,
      et c'est seulement au second passage qu'on sait.

---

## Test de mise à niveau

À exécuter sur le `.app` de **production**, jamais sur un build `.test`.

1. [ ] **Archiver d'abord la version précédente — ne pas la supprimer.** Une
   archive non exécutable, conservée pour permettre un retour arrière.
2. [ ] **Installer réellement la nouvelle version**, en remplacement effectif.
3. [ ] **Lancer la bonne version** : « À propos » affiche la version attendue,
   identifiant de production, **et aucune redirection de LaunchServices vers une
   copie résiduelle** — voir « L'écueil de l'identifiant partagé ».
4. [ ] **Le modèle déjà téléchargé est reconnu** : aucun re-téléchargement de
   plusieurs gigaoctets n'est déclenché.
5. [ ] **Les réglages mémorisés sont relus** sans perte et sans réinitialisation
   silencieuse.
6. [ ] **Persistance après relance** : modifier un réglage, quitter, relancer →
   le réglage est conservé.

En cas d'anomalie : **restaurer la version précédente depuis l'archive.**

---

## Règle de versionnement

À partir de la V1.1, le **tag Git** et `CFBundleShortVersionString` **doivent
toujours coïncider**. Toute divergence bloque la release jusqu'à correction.

## Note historique — omission de version `v1.0.0`

Fait, sans justification rétroactive :

Le tag `v1.0.0` pointe vers un commit dont le binaire affiche
`CFBundleShortVersionString = 0.1.0` (build `1`). Le nom du tag et la version
interne de l'application **ne coïncident pas**.

Il s'agit d'une **omission au moment du tag**. Elle n'est **pas** corrigée, afin
de ne pas réécrire un tag déjà publié. `v1.0.0` reste un **jalon historique**.
L'alignement entre tag et version affichée commence à partir de la V1.1.

*(Les SHA d'avant la réécriture d'historique du 2026-08-12 n'existent plus ; la
sauvegarde intégrale est conservée hors dépôt.)*
