# v32lua : Compilateur Lua pour Vircon32

[Version anglaise / in English](README.md) | [Version espagnole / en español](README.es.md)

**Architecture Cible :** Console de fantaisie Vircon32 (32-bit)

**Langage d'Implémentation :** C (Flex/Bison + Émetteur Sémantique Personnalisé)

**Dépôt :** [github.com/wedge1020/v32lua](https://github.com/wedge1020/v32lua)

**Référence de l'API :** [doc/API.md](doc/API.md) — l'API native complète
de Vircon32 (son, graphismes, entrées, tuiles/tilemaps, carte mémoire, et
ports d'E/S bruts).

`v32lua` est un compilateur Lua écrit en C qui cible la console de
fantaisie **Vircon32**. Plutôt que d'embarquer un interpréteur de bytecode
lourd, `v32lua` analyse le code source Lua et le compile directement en
assembleur natif Vircon32, tout en produisant également la définition XML
de cartouche dont la chaîne d'outils de la console a besoin pour empaqueter
une ROM.

Bien qu'il ne soit pas encore complet, l'un des objectifs du développement
est de faire de `v32lua` un substitut (en aucun cas un remplacement) du
Compilateur C de Vircon32 au sein de la chaîne de développement Vircon32.
En somme, choisissez votre langage — C ou Lua — et une fois compilé en
assembleur, vous poursuivez la construction indépendamment du langage
d'implémentation. Des efforts ont donc été faits pour imiter divers
comportements du Compilateur C de Vircon32 afin de rendre la substitution
de compilateur plus transparente.

Conçu dès le départ en tenant compte des contraintes d'une console de
fantaisie rétro, `v32lua` propose des intrinsèques matériels à coût nul,
un [NaN-boxing](doc/NaN_boxing.md) personnalisé, et — au-delà de l'API
native de Vircon32 — deux couches de compatibilité d'API afin que les
cartouches écrites pour **TIC-80** et **PICO-8** puissent être compilées et
exécutées sur le matériel Vircon32 avec peu ou pas de modification du code
source.

```
+------------------+     +-------------------+     +------------------+
| Source (.lua)    | --> | Lexer & Parseur   | --> | Construction de   |
+------------------+     | (Flex / Bison)    |     | l'AST             |
                         +-------------------+     +------------------+
                                                            |
                                                            v
+------------------+     +-------------------+     +------------------+
| Configuration     | <-- | Assembleur         | <-- | Émetteur          |
| de Cartouche      |     | Vircon32 (.asm)    |     | Sémantique        |
| (.xml)            |     |                    |     |                   |
+------------------+     +-------------------+     +------------------+
```

---

## Table des Matières

- [Pour Commencer](#pour-commencer)
  - [Prérequis](#prérequis)
  - [Compiler le Compilateur](#compiler-le-compilateur)
  - [Cibles du Makefile](#tableau-de-référence-des-cibles-du-makefile)
  - [Votre Première Cartouche](#votre-première-cartouche)
  - [Utilisation en Ligne de Commande](#utilisation-en-ligne-de-commande)
- [Couches de Compatibilité d'API](#couches-de-compatibilité-dapi)
- [Indices de Ressources de Cartouche (`--#...`)](#indices-de-ressources-de-cartouche)
  - [Projets Multi-Fichiers (`--#include`)](#projets-multi-fichiers---include)
- [Pipeline de Compilation](#pipeline-de-compilation)
- [Fonctionnalités Clés du Langage et du Compilateur](#fonctionnalités-clés-du-langage-et-du-compilateur)
  - [Modèles d'Exécution : `main()` vs `game_loop()`](#modèles-dexécution-flexibles-main-vs-game_loop)
  - [NaN-Boxing : Éléments RAM vs ROM](#nan-boxing--éléments-ram-vs-rom)
  - [Intrinsèques Matériels et Mappage E/S](#intrinsèques-matériels-et-mappage-es)
  - [Outillage pour Développeurs](#expérience-de-développement-et-outillage-de-débogage)
- [Fonctionnalités Lua Prises en Charge](#fonctionnalités-lua-prises-en-charge)
  - [Variables et Portée](#variables-et-portée)
  - [Affectation Multiple](#affectation-multiple)
  - [Programmation Orientée Objet et Tables](#programmation-orientée-objet-et-tables)
  - [Flux de Contrôle](#flux-de-contrôle)
  - [Opérateurs et Expressions](#opérateurs-et-expressions)
  - [Fonctions et Retours de Valeurs Multiples](#fonctions-et-retours-de-valeurs-multiples)
  - [Regroupement des Littéraux de Chaîne](#regroupement-des-littéraux-de-chaîne)
  - [Évaluation Truthy / Falsy en Court-Circuit](#évaluation-truthy--falsy-en-court-circuit)
- [E/S Matérielle et Intrinsèques du Compilateur](#es-matérielle-et-intrinsèques-du-compilateur)
  - [Conversion Automatique de Types aux Frontières d'E/S](#conversion-automatique-de-types-aux-frontières-des)
  - [Tableau de Référence Complet des Intrinsèques](#tableau-de-référence-complet-des-intrinsèques)
- [Assembleur en Ligne (`__asm__` et `__rawasm__`)](#assembleur-en-ligne-__asm__--__rawasm__)
- [Référence de la Carte Mémoire](#référence-de-la-carte-mémoire)
- [Particularités, Hypothèses et Limitations Connues du Compilateur](#particularités-et-hypothèses-du-compilateur)
- [Optimisation du Compilateur](#optimisation-du-compilateur)
- [Feuille de Route / Pas Encore Implémenté](#feuille-de-route--pas-encore-implémenté)
- [Utilisation de l'IA](#utilisation-de-lia)

---

## Pour Commencer

### Prérequis

* Une chaîne d'outils C (`gcc`/`clang` + `make`) capable de compiler des
  sources générées par `flex`/`bison`.
* `flex` et `bison` eux-mêmes, pour régénérer le lexer/parseur si vous
  compilez depuis l'arborescence de sources séparées plutôt que depuis une
  version pré-générée.
* La chaîne d'outils Vircon32 (assembleur et `packrom`) si vous comptez
  aller jusqu'au bout, du `.lua` à une cartouche `.v32` exécutable, plus
  [v32sim](https://github.com/g7n-org/v32sim) si vous souhaitez exécuter ou
  déboguer le résultat.

### Compiler le Compilateur

Le dépôt inclut un Makefile à la racine qui gère la compilation du binaire
du compilateur, l'exécution de la suite de tests, et l'entretien général du
projet. Pour compiler le binaire principal du compilateur depuis les
sources, exécutez la cible par défaut depuis la racine du dépôt :

```bash
make
```

Ceci produit le binaire `v32lua` (sous `bin/`), qui transforme un fichier
source `.lua` en un fichier `.asm` Vircon32 accompagné d'un `.xml` de
cartouche. À partir de là, l'assemblage et l'empaquetage suivent les mêmes
étapes que n'importe quel autre projet Vircon32 (assembler → `packrom` →
exécuter sous [v32sim](https://github.com/g7n-org/v32sim) ou sur du matériel réel).

#### Tableau de Référence des Cibles du Makefile

| Cible | Description | Actions Principales & Dépendances |
| --- | --- | --- |
| **`all`** | **Cible par défaut.** Compile l'exécutable principal du compilateur. | Invoque le processus de compilation nativement dans le sous-répertoire `src/`. |
| **`clean`** | Utilitaire standard de nettoyage de l'espace de travail. | Efface récursivement les artefacts de compilation intermédiaires de `src/` et supprime les fichiers générés dans `testing/` et `demos/`. |
| **`install`** | Installe le binaire du compilateur sur le système hôte. | Transmet la cible aux scripts d'installation localisés du répertoire `src/`. |
| **`tests`** | Exécute la suite de tests de compilation automatisée. | Dépend de la compilation préalable du binaire du compilateur (`bin/v32lua`), puis déclenche les routines de test dans `testing/`. |
| **`demos`** | Compile la collection de démos disponibles. | Dépend de la compilation préalable du binaire du compilateur (`bin/v32lua`), puis compile chaque démo sous `demos/`. |
| **`asmcheck`** | Valide la correction de l'assembleur. | Nécessite que `bin/v32lua` soit présent, puis traite les validations d'assembleur via la suite `testing/`. |
| **`monofiles`** | Génère des variantes de fichier monolithique simplifiées (utilisées pour coller l'ensemble du projet dans une conversation à fichier unique). | Exécute le flux de création `monofile` séquentiellement dans `src/` et `testing/`. |

### Votre Première Cartouche

```lua
--#title "v32lua Tech Demo"
--#version "1.0"
--#texture tex_logo "logo.png"

x_pos = 160.0
y_pos = 120.0
speed = 2.5

function init()
    -- Définit la couleur de fond via les mappages de ports GPU à coût nul
    ioports.gpu.bgcolor = 0xFF003366
    ioports.gpu.texture = tex_logo -- définit la texture
    ioports.gpu.region  = 0 -- définit la région

    -- définit la région
    ioports.gpu.minX    = 0
    ioports.gpu.minY    = 0
    ioports.gpu.maxX    = 100
    ioports.gpu.maxY    = 50
    ioports.gpu.hotX    = 0
    ioports.gpu.hotY    = 0
end

function game_loop()

    -- Met à jour l'état en utilisant des calculs en virgule flottante purs
    if ioports.inp.left > 1 then
        x_pos = x_pos - speed
    else if ioports.inp.right > 1 then
        x_pos = x_pos + speed
    end

    -- Dessin matériel direct
    ioports.gpu.x = x_pos
    ioports.gpu.y = y_pos
    ioports.gpu.draw()

    -- Accès aux tables et concaténation de chaînes intégrée
    local frame = system.frames
    if frame > 1000 then
        local msg = "Demo Running: Frame " .. frame
        print(msg)
    end
end
```

Compilez-le avec :

```bash
$ v32lua -o program.asm program.lua
```

`v32lua` produit `program.asm` et `program.xml` à ses côtés ; transmettez-
les à l'assembleur Vircon32 puis à `packrom` pour obtenir une cartouche
exécutable.

### Utilisation en Ligne de Commande

```bash
$ v32lua [options] fichier
```

Options disponibles :

* `-o <fichier>` : Spécifie le nom du fichier de sortie de l'assembleur.
  Par défaut, il s'agit du nom du fichier d'entrée avec son extension
  remplacée par `.asm`.
* `-g` : Génère un fichier `.debug` compagnon qui associe les décalages de
  lignes de l'assembleur aux lignes du code source Lua d'origine et aux
  points d'entrée des fonctions.
* `-v`, `--verbose` : Rapporte la progression à travers les étapes internes
  du pipeline du compilateur pendant son exécution.
* `-d`, `--debug` : Affiche des informations de débogage internes/
  opérationnelles supplémentaires.
* `-w` : Supprime tous les avertissements du compilateur.
* `--version` : Affiche la version du compilateur et les informations sur
  l'auteur.
* `--help`, `-h` : Affiche les instructions d'utilisation de la ligne de
  commande.

---

## Couches de Compatibilité d'API

`v32lua` prend en charge trois surfaces d'API distinctes, sélectionnées
avec l'indice de cartouche `--#api` (l'API native de Vircon32 est celle
par défaut lorsqu'aucun indice `--#api` n'est présent) :

```lua
--#api "tic80"   -- opte pour la surface d'API compatible TIC-80
--#api "pico8"   -- opte pour la surface d'API compatible PICO-8
```

* **API native Vircon32** (par défaut) — accès direct et à coût nul au
  matériel propre de la console : `ioports.gpu.*`, `ioports.spu.*`,
  `ioports.inp.*`, `music.*`/`sfx.*`, `system.*`, et l'API native
  `tilemap.*`. Entièrement documentée dans [doc/API.fr.md](doc/API.fr.md).
* **Couche de compatibilité TIC-80** (`--#api "tic80"`) — les appels au
  format TIC-80 (`spr()`, `btn()`/`btnp()`, `map()`/`mset()`/`mget()`, les
  fonctions son/musique, et les sections de ressources façon console de
  fantaisie) compilés en instructions natives Vircon32, y compris la mise
  à l'échelle des coordonnées nécessaire pour faire correspondre l'écran
  logique 240×136 de TIC-80 à la résolution physique de Vircon32.
* **Couche de compatibilité PICO-8** (`--#api "pico8"`) — l'équivalent au
  format PICO-8, à un stade d'avancement antérieur à celui de la couche
  TIC-80.

Une seule surface d'API est active par cartouche ; sélectionner `tic80` ou
`pico8` remplace la surface d'appel native au lieu de s'y ajouter.

---

## Indices de Ressources de Cartouche

`v32lua` vous permet d'intégrer des métadonnées de cartouche Vircon32
directement dans votre code source Lua à l'aide de commentaires de ligne
spéciaux `--#`. Le compilateur analyse ces indices pour générer
automatiquement la définition ROM `.xml` du projet et attribuer des
identifiants de ressources matérielles séquentiels.

Indices pris en charge :

| Indice | Objectif |
| --- | --- |
| `--#version "X.Y"` | Définit le champ de version de la cartouche dans le XML. |
| `--#title "TITRE"` | Définit le titre de la cartouche. |
| `--#api "tic80"` / `--#api "pico8"` | Sélectionne une couche de compatibilité d'API (voir ci-dessus). |
| `--#texture NOM "chemin/image.png"` | Enregistre une ressource de texture et la lie à une constante `NOM` à la compilation. |
| `--#sound NOM "chemin/son.vsnd"` | Enregistre une ressource sonore et la lie à une constante `NOM` à la compilation. |
| `--#tilemap NOM "chemin/carte.csv"` | Enregistre une tilemap depuis un fichier CSV, intégrée directement dans l'image ROM (voir [doc/API.md](doc/API.md#tilemap-tilemap)). |
| `--#include "fichier.lua"` | Insère textuellement un autre fichier Lua à cet endroit, avant le début de l'analyse (voir ci-dessous). |

```lua
--#version "1.1"
--#title "Space Grinder: Tech Demo"

-- Enregistre des textures (lie automatiquement 'bg_space' à l'ID 0, 'spr_ship' à l'ID 1)
--#texture bg_space "assets/background.png"
--#texture spr_ship "assets/player.png"

function init()
    -- Les variables déclarées dans les indices sont disponibles globalement en Lua à l'exécution !
    ioports.gpu.texture = bg_space
end
```

Une fois compilé, `v32lua` produit à la fois l'assembleur `.asm` compilé et
un fichier complet de définition de cartouche XML Vircon32 reliant les
ressources `.vtex` et `.vsnd`. Avec cela, et le traitement approprié de
toute donnée PNG et WAV, vous pouvez procéder à l'étape `packrom`. Les
identifiants de ressources sont attribués dans l'ordre du code source et
sont garantis de correspondre à leur position dans le XML généré.

### Projets Multi-Fichiers (`--#include`)

Comme les cartouches Vircon32 sont une ROM fixe entièrement assemblée au
moment de la compilation — il n'existe aucun système de fichiers à
l'exécution — `v32lua` ne prend pas en charge le `require`/`dofile`
dynamique du vrai Lua. Au lieu de cela, `--#include "fichier.lua"` est un
collage textuel effectué à la compilation, résolu par une passe de
prétraitement avant même que le lexer ne voie le fichier, exactement comme
le `#include` du C :

```lua
--#include "src/physics.lua"
--#include "src/entities.lua"
```

* Les fichiers inclus sont insérés au véritable niveau supérieur du
  chunk — sans être enveloppés dans un `do...end` ni dans un corps de
  fonction — de sorte qu'une `local` de niveau supérieur dans un fichier
  inclus se comporte exactement comme une `local` déclarée dans le fichier
  d'entrée.
* Les chemins sont résolus par rapport au fichier qui inclut ; les
  inclusions cycliques sont détectées, et chaque chemin absolu n'est
  inclus qu'une seule fois sur l'ensemble de l'expansion.
* Les indices de ressources de cartouche (`--#texture`, `--#sound`,
  `--#tilemap`) déclarés dans un fichier inclus reçoivent des identifiants
  de ressources corrects et un ordre correct dans le XML.
* Les messages d'erreur à l'intérieur d'un fichier inclus rapportent le
  fichier source et le numéro de ligne corrects, via une table interne de
  reremappage de lignes.
* Deux fichiers inclus qui déclarent chacun une `local` de niveau
  supérieur portant le même nom partagent une seule variable globale —
  identique à ce que ferait le code monolithique équivalent.

---

## Pipeline de Compilation

### Flux de Compilation

1. **Analyse Lexicale et Syntaxique** : Flex/Bison analyse le code source
   Lua en un Arbre de Syntaxe Abstraite (AST) typé.
2. **Résolution des Symboles et des Portées** : Résout les variables à
   travers les portées lexicales, associant les globales à des adresses
   RAM séquentielles et les locales à des positions de pile
   `[BP - offset]`.
3. **Génération de Code** : Émet des instructions assembleur Vircon32, en
   appliquant les substitutions d'intrinsèques matériels au fil du
   parcours de l'AST.
4. **Assemblage de la Cartouche** : Émet le fichier `.asm` final, intègre
   les routines de support à l'exécution, génère la section de données de
   chaînes en lecture seule, et produit la définition `.xml` de la
   cartouche.

### Étapes de Compilation (`-v`)

Lorsque `-v` est activé, `v32lua` rapporte sa progression à travers ses
étapes de pipeline :

1. **Étape 1 : Lexer** — Décompose le code source Lua en tokens, retire
   les commentaires standards et traite les séquences d'échappement de
   chaînes (`\n`, `\t`, `\r`, `\\`, `\"`).
2. **Étape 2 : Préprocesseur** — Développe les directives `--#include` et
   évalue les indices de cartouche (`--#...`) et les syntaxes de
   commentaires personnalisées.
3. **Étape 3 : Parseur** — Construit un Arbre de Syntaxe Abstraite (AST)
   complet à l'aide d'une grammaire Bison LALR(1) avec une précédence
   d'opérateurs stricte (noyau PEMDAS + logique).
4. **Étape 4 : Analyseur Sémantique** — Exécute une pré-passe pour
   enregistrer les symboles globaux de fonctions et de variables et
   initialiser la portée globale.
5. **Étape 5 : Émetteur** — Parcourt l'AST pour générer l'assembleur
   Vircon32, en appliquant l'allocation de registres et les décalages de
   portée, et produit enfin le fichier de configuration XML de la
   cartouche.

---

## Fonctionnalités Clés du Langage et du Compilateur

### Modèles d'Exécution Flexibles : `main()` vs. `game_loop()`

Pour s'adapter à différents styles d'architecture de jeu, le compilateur
prend en charge deux paradigmes distincts de point d'entrée :

* **Le Harnais à Tic Automatique (`game_loop`)** : Si votre programme
  déclare une fonction `game_loop()`, le compilateur génère automatiquement
  un harnais d'exécution continu. Le CPU appelle `game_loop()`, suspend
  l'exécution pour l'image en cours à l'aide de l'instruction matérielle
  `WAIT`, et boucle indéfiniment. Ceci est idéal pour les jeux d'arcade et
  démos standards, et imite le comportement de diverses autres consoles de
  fantaisie.

* **Contrôle Manuel (`main`)** : Si votre programme déclare une fonction
  `main()`, le contrôle est remis directement à `__function_main`. Vous
  prenez alors l'entière responsabilité du cycle d'image et devez exécuter
  manuellement de l'assembleur en ligne ou des attentes matérielles. Le
  compilateur vérifie si une instruction `WAIT` est émise à l'intérieur de
  `main()` ; si elle est absente, `v32lua` émet un avertissement sémantique
  à la compilation.

* **Point d'Initialisation** : Dans les deux modèles, si une fonction
  `init()` est présente, il est garanti qu'elle s'exécute exactement une
  fois, après les allocations de RAM globales de niveau supérieur et avant
  le début de la boucle principale.

Un programme doit déclarer au moins l'une des deux fonctions `main()` ou
`game_loop()` — il s'agit du point d'entrée désigné, et son absence est une
erreur de compilation.

### NaN-Boxing : Éléments RAM vs. ROM

`v32lua` utilise une architecture d'étiquetage sur 32 bits qui compresse
les métadonnées de type et les pointeurs de charge utile dans des valeurs
unifiées, séparant les **éléments ROM** immuables (littéraux de chaîne,
pointeurs de fonction) des **objets de tas (heap) RAM** dynamiques
(tables) :

| Type de Donnée | Masque/Étiquette Hex | Description de l'Architecture |
| --- | --- | --- |
| **Nil** | `0xFFC00000` | Représentation canonique des valeurs indéfinies/manquantes. |
| **Booléen Faux** | `0xFFC00001` | Valeur fausse de court-circuit. |
| **Booléen Vrai** | `0xFFC00002` | Valeur vraie de court-circuit. |
| **Chaîne ROM** | `0x7FC00000` | Pointeurs vers des sections de données de chaînes en lecture seule (`__string_%d`) en ROM. |
| **Table / Objet Encapsulé** | `0xFF800000` | Adresses mémoire de tas encapsulées (bit 31=1, bit 22=0). |
| **Nombre** | Flottant IEEE 754 | Valeurs en virgule flottante natives de Vircon32, non encapsulées, pour les calculs directs. |

### Intrinsèques Matériels et Mappage E/S

Les jeux Vircon32 à haute performance ne peuvent pas se permettre des
recherches dans des tables de hachage pour la manipulation matérielle.
`v32lua` intercepte des expressions spécifiques d'accès aux membres de
table et des appels de fonctions, et les compile directement en
instructions d'E/S matérielle natives :

* **Accès Matériel à Coût Nul** : Accéder à des espaces de noms comme
  `ioports.gpu.*`, `ioports.spu.*`, `ioports.tim.*`, `ioports.rng.*`,
  `ioports.car.*`, `ioports.mem.*`, ou `system.*` contourne entièrement les
  routines de recherche dans les tables. Ils sont compilés directement en
  opérations sur les ports matériels (comme `GPU_DrawingPointX` ou
  `TIM_FrameCounter`).

* **`music.*` / `sfx.*`** : L'API son native compile des appels comme
  `music.play(SOUND, channel, loop)` en une séquence linéaire de `OUT`
  lorsque tous les arguments sont connus à la compilation, et se replie
  sur une petite routine d'exécution seulement lorsque les arguments sont
  dynamiques. Consultez [doc/API.md](doc/API.md) pour la surface complète,
  y compris pourquoi l'ordre d'écriture des ports SPU (arrêt → assignation
  → volume → lecture → boucle/position) est déterminant.

* **`tilemap.*`** : Une API native de tilemap (`tilemap.get()`,
  `tilemap.set()`, `tilemap.render()`) adossée à un indice de cartouche
  `--#tilemap`. Les données de tilemap sont livrées en lecture seule dans
  la ROM et sont promues paresseusement vers une copie privée en RAM la
  première fois qu'une tilemap donnée est écrite.

* **Sondage Consolidé de la Manette** : Le sondage des entrées du
  contrôleur est optimisé en un seul intrinsèque de variable
  (`ioports.inp.inputs`). Le compilateur sonde tous les axes/boutons de la
  manette, combine les états de boutons actifs en un masque entier de 32
  bits décalé, et le convertit en un flottant Lua en un seul registre. Les
  entrées de manette individuelles sont également disponibles
  (`ioports.inp.left`, `ioports.inp.A`, etc.) en tant qu'intrinsèques de
  variable.

* **Chemins Rapides Intégrés** : Les opérations Lua standards telles que
  la concaténation de chaînes (`..`), la longueur (`#`), et le moins
  unaire (`-`) sont mappées directement vers des sous-routines
  d'exécution optimisées (`__builtin_strcat`, `__builtin_len`,
  `__builtin_unm`).

Consultez [doc/API.md](doc/API.md) pour la référence complète et
faisant autorité — ce README met en avant les idées, le document d'API
couvre chaque appel.

### Expérience de Développement et Outillage de Débogage

* **Rapport d'Erreurs Visuel en ASCII** : Les erreurs lexicales,
  syntaxiques, sémantiques et internes du compilateur affichent des
  extraits de code ASCII en surbrillance, sur plusieurs lignes, pointant
  directement vers la ligne fautive dans le fichier source.

* **Mappage Source-vers-Assembleur (`-g`)** : Passer le drapeau de
  débogage `-g` génère un fichier `.debug` compagnon aux côtés de
  l'assembleur de sortie. Ce fichier associe les décalages de lignes
  relatifs de l'assembleur Vircon32 aux lignes du code source Lua
  d'origine et aux points d'entrée des fonctions, permettant un débogage
  pas à pas sous [v32sim](https://github.com/g7n-org/v32sim).

* **Bulles d'Assembleur en Ligne et Brut** : Vous pouvez écrire de
  l'assembleur natif directement dans Lua en utilisant
  `__asm__("votre ASM")` (qui sauvegarde et restaure les registres et le
  pointeur de pile) ou `__rawasm__("votre ASM")` pour une exécution non
  protégée. Les deux modes prennent en charge l'interpolation de chaînes
  des variables Lua avec la syntaxe `{nom_var}`.

---

## Fonctionnalités Lua Prises en Charge

`v32lua` implémente un sous-ensemble de Lua, spécifiquement adapté au
développement de jeux sur matériel embarqué.

### Variables et Portée

* **Variables Globales :** Enregistrées automatiquement en RAM et
  accessibles via des symboles (`[var_nom]`, `[func_nom]`). L'adresse `0`
  est réservée au pointeur de tas (heap) et les adresses `1`/`2` sont des
  mots de travail (scratch) réservés utilisés par la routine de
  conversion flottant-vers-chaîne ; les variables globales ordinaires
  commencent à l'adresse `3`.

* **Variables Locales :** Déclarées avec le mot-clé `local`. À portée
  lexicale limitée au bloc englobant (corps de fonction, boucles, ou
  conditionnelles) et associées à des décalages de pile
  (`[BP - offset]`). Une `local` déclarée au véritable niveau supérieur
  d'un chunk — en dehors de toute fonction — est promue en variable
  globale à la place, car son stockage résiderait sinon dans un cadre de
  pile qui retourne avant que tout code de jeu ne s'exécute ; ceci
  s'applique également aux `local`s introduites via `--#include`.

Dans le jargon Lua, les fonctions sont des « citoyennes de première
classe », et sont effectivement des variables. Cela se vérifie dans
`v32lua`, puisque les deux transitent au sein du schéma de NaN-boxing.

### Affectation Multiple

Le compilateur prend nativement en charge l'affectation multiple et
l'échange de variables sans nécessiter de variables temporaires
explicites de la part de l'utilisateur :

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Synthétise des chaînes de registres temporaires pour échanger les valeurs en toute sécurité
```

### Programmation Orientée Objet et Tables

`v32lua` fournit un sucre syntaxique transparent pour les modèles de POO
basés sur des tables :

* **Désucrage de la Définition de Méthode :** Définir une fonction sur
  une table génère automatiquement une étiquette au nom modifié et lie la
  propriété du pointeur de fonction :

```lua
function Player.move(dx, dy) ... end
-- Se désucre en : Player["move"] = __function_Player_move
```

* **Désucrage de l'Appel de Méthode (opérateur `:`) :** Utiliser
  l'opérateur deux-points évalue automatiquement l'expression de table et
  l'injecte comme paramètre implicite `self` :

```lua
Player:move(5, -2)
-- Se désucre en : Player.move(Player, 5, -2)
```

### Flux de Contrôle

* **Boucles :** Les instructions `while <cond> do ... end` sont prises en
  charge avec une portée de bloc complète.

* **Contrôle de Boucle :** Les instructions `break` sautent immédiatement
  vers l'étiquette de fin de la boucle la plus interne actuelle (suivie
  via une pile interne de compilation des boucles).

* **Conditionnelles :** Structures `if <cond> then ... elseif <cond> then
  ... else ... end` avec branchement en court-circuit.

### Opérateurs et Expressions

* **Arithmétiques :** `+`, `-`, `*`, `/` (associés aux instructions
  matérielles en virgule flottante de Vircon32 `FADD`, `FSUB`, `FMUL`,
  `FDIV`), et le moins unaire (`-` via `__builtin_unm`).

* **Relationnels :** `==`, `~=` (via `__builtin_eq` avec désencapsulation
  de NaN), `<`, `>`, `<=`, `>=` (via le matériel `FLT`, `FLE`, `FGT`,
  `FGE`).

* **Logiques :** `and`, `or`, `not` (avec évaluation en court-circuit).

* **Concaténation de Chaînes :** l'opérateur `..` empile automatiquement
  les opérandes et invoque la sous-routine d'exécution
  `__builtin_strcat`.

* **Opérateur de Longueur :** l'opérateur `#` invoque `__builtin_len` pour
  résoudre les longueurs de chaînes ou de tables.

### Fonctions et Retours de Valeurs Multiples

Les fonctions peuvent retourner plusieurs valeurs simultanément. La
convention d'appel optimise les trois premières expressions retournées en
les plaçant directement dans les registres `R0`, `R2`, et `R3`. Toute
valeur de retour supplémentaire (4ème et suivantes) est déversée
directement sur le cadre de pile de l'appelant.

### Regroupement des Littéraux de Chaîne

Tous les littéraux de chaîne déclarés dans le code source (par exemple,
`"GAME OVER"`) sont collectés lors de la compilation, dédupliqués, et
émis dans une section de données dédiée à la fin de la ROM
(`__string_0: string "GAME OVER"`), évitant une consommation redondante
de la ROM.

### Évaluation Truthy / Falsy en Court-Circuit

En Lua, seuls `nil` et `false` s'évaluent comme faux dans les expressions
conditionnelles ; toute autre valeur (y compris `0` et les chaînes vides)
est **vraie (truthy)**. `v32lua` implémente cela via deux primitives
d'émission d'assembleur à haute vitesse :

* **`emit_falsy_jump(reg, label)`** : Teste si `reg` correspond à
  `0xFFC00000` (Nil) ou `0xFFC00001` (Faux). Si l'un des deux correspond,
  l'exécution saute vers l'étiquette cible.

* **`emit_truthy_jump(reg, label)`** : Teste par rapport à Nil et Faux ;
  si aucun ne correspond, l'exécution court-circuite vers l'étiquette
  cible.

Lorsque les opérateurs logiques (`and`, `or`) sont évalués, le résultat
évalué est laissé intact dans le registre de destination, préservant
l'idiome Lua consistant à retourner la valeur réelle de l'opérande
plutôt qu'un booléen strict.

---

## E/S Matérielle et Intrinsèques du Compilateur

L'une des fonctionnalités les plus puissantes de `v32lua` est son
**moteur d'interception statique des intrinsèques**. Lorsque le
compilateur rencontre des accès à des tables ou des appels de fonctions
correspondant à des chemins système spécifiques (par exemple,
`ioports.gpu.clear()`), il **contourne entièrement les recherches
dynamiques dans les tables** et émet des instructions d'E/S matérielle
Vircon32 directes (`IN`, `OUT`).

### Conversion Automatique de Types aux Frontières d'E/S

Étant donné que les variables Lua sont stockées sous forme de flottants
IEEE 754 encapsulés en NaN, alors que les ports matériels de Vircon32
attendent des entiers 32 bits ou des booléens, `v32lua` injecte
automatiquement des instructions de conversion matérielle lors des
lectures et écritures de ports :

* **`CFI` (Conversion Flottant vers Entier) :** Émise automatiquement
  lors de l'écriture de valeurs numériques dans des ports GPU/Entrée de
  type entier.

* **`CFB` (Conversion Flottant vers Booléen) :** Émise lors de l'écriture
  de drapeaux booléens dans des registres matériels, en décodant la
  véracité (truthiness) Lua (seuls `nil`/`false` sont faux) plutôt qu'un
  simple test de non-zéro brut.

* **`CIF` (Conversion Entier vers Flottant) :** Émise immédiatement après
  l'exécution d'une instruction `IN` depuis des ports matériels de type
  entier, garantissant que la valeur soit immédiatement utilisable comme
  un nombre Lua.

* **Lectures de ports booléens :** décodées vers la représentation
  encapsulée `true`/`false` plutôt qu'un flottant brut `0.0`/`1.0`,
  puisque `0.0` est vrai (truthy) en Lua et ferait sinon lire une manette
  déconnectée ou une carte mémoire comme étant « connectée ».

### Tableau de Référence Complet des Intrinsèques

La référence complète et faisant autorité pour chaque intrinsèque —
`ioports.gpu.*`, `ioports.inp.*`, `ioports.spu.*`, `ioports.tim.*`,
`ioports.rng.*`, `ioports.car.*`, `ioports.mem.*`, `music.*`/`sfx.*`,
`tilemap.*`, `memcard.*`, et `system.*` — se trouve dans
[doc/API.md](doc/API.md), avec les mises en garde sur l'ordre des ports,
les signatures d'appel, et des exemples détaillés. Voici un bref
échantillon des entrées les plus couramment utilisées :

#### Contrôle et Dessin GPU (`ioports.gpu.*`)

| Chemin Lua / Intrinsèque | Port/Commande Vircon32 | Accès | Description et Comportement |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lecture / Écriture | Définit ou lit l'identifiant de texture actif utilisé pour les opérations de dessin. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lecture / Écriture | Sélectionne la sous-région de texture (image de sprite) à afficher. |
| **`ioports.gpu.x`** / **`ioports.gpu.y`** | `GPU_DrawingPointX/Y` | Lecture / Écriture | Coordonnées écran pour le placement du dessin. |
| **`ioports.gpu.minX/minY/maxX/maxY`** | `GPU_RegionMin/MaxX/Y` | Lecture / Écriture | Définit les limites en pixels de la région de texture active. |
| **`ioports.gpu.hotX/hotY`** | `GPU_RegionHotSpotX/Y` | Lecture / Écriture | Définit l'origine de dessin (hotspot) relative à la région du sprite. |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Appel de Fonction | Exécute une commande de dessin matérielle : `"zoom"`, `"rotate"`, `"rotozoom"`, ou la valeur par défaut. |
| **`ioports.gpu.clear([couleur])`** | `GPU_ClearColor` + `GPU_Command` | Appel de Fonction | Définit la couleur d'effacement et efface l'écran. Prend en charge des chaînes de couleurs prédéfinies (`"black"`, `"white"`, `"blue"`, `"red"`, `"green"`) ou des valeurs hexadécimales numériques. |

#### Manette et Entrées (`ioports.inp.*`)

| Chemin Lua / Intrinsèque | Port/Commande Vircon32 | Accès | Description et Comportement |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lecture / Écriture | Sélectionne l'index de la manette active (`0`-`3`) pour le sondage des entrées. |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Lecture Seule | Retourne un booléen Lua : la manette sélectionnée est-elle connectée. |
| **`ioports.inp.left/right/up/down`** | `INP_Gamepad*` | Lecture Seule | État directionnel de la croix directionnelle (`> 0` pressé, `< 0` relâché). |
| **`ioports.inp.A/B/X/Y/L/R/start`** | `INP_GamepadButton*` | Lecture Seule | État des boutons d'action/gâchettes (`> 0` pressé, `< 0` relâché). |
| **`ioports.inp.inputs`** | *Sous-routine d'Action Personnalisée* | Lecture Seule | **Intrinsèque de regroupement :** sonde tous les boutons/axes de la manette en une seule passe, les regroupe en un unique masque de bits sur 32 bits, et le convertit en flottant Lua. |

#### Utilitaires Système et d'Exécution

| Chemin Lua / Intrinsèque | Instruction Vircon32 | Accès | Description et Comportement |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Appel de Fonction | Émet l'instruction matérielle `HLT`, terminant immédiatement l'exécution du CPU ou figeant l'image jusqu'au prochain cycle d'interruption/image. |
| **`system.wait()`** | `WAIT` | Appel de Fonction | Émet l'instruction matérielle `WAIT`, mettant en pause l'exécution jusqu'au prochain cycle d'interruption/image. |
| **`system.frames`** / **`system.cycles`** | `TIM_FrameCounter` / `TIM_CycleCounter` | Lecture Seule | Compteurs continus d'images/cycles. |
| **`print(x, y, ...)`** | `__builtin_tostring` + `__builtin_print` | Appel de Fonction | Convertit les arguments en leur représentation sous forme de chaîne et les envoie au terminal de débogage de la console. Les deux premiers paramètres sont la position X, Y à l'écran, en pixels. |

---

## Assembleur en Ligne (`__asm__` et `__rawasm__`)

Pour les boucles internes critiques en performance ou la manipulation
matérielle avancée de Vircon32, `v32lua` fournit une injection directe
d'assembleur en ligne.

### Assembleur en Ligne Standard (`__asm__`)

La directive `__asm__` permet d'intégrer des chaînes d'assembleur brut de
Vircon32 directement à l'intérieur de fonctions Lua. Fait crucial, elle
prend en charge l'**interpolation de variables**, permettant un pont
transparent entre les symboles de portée Lua et les registres
d'assembleur :

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )
```

* **Comment ça fonctionne :** Tout identifiant entouré d'accolades (par
  exemple, `{speed}`) est résolu dynamiquement par
  `emit_interpolated_asm` à la compilation. Si `speed` est une variable
  locale au décalage de pile 1, `{speed}` est automatiquement remplacé
  par `[BP - 1]`. S'il s'agit d'une globale, il est résolu en
  `[var_speed]`.

* Chaque ligne d'assembleur interpolé passe par le moteur de formatage du
  compilateur, garantissant une indentation et un alignement des
  commentaires cohérents dans le fichier `.asm` de sortie.

* Cet assembleur en ligne standard applique quelques garde-fous et
  protections légers, sous la forme d'une sauvegarde des registres
  actuellement utilisés ainsi que de la pile. Bien que cela ne prévienne
  pas tous les problèmes, cela peut aider à atténuer ceux causés par
  accident. Tout changement de registre effectué ici est perdu en dehors
  de la « bulle » en ligne.

### Assembleur Brut (`__rawasm__`)

La directive `__rawasm__` produit la chaîne littérale directement dans le
flux d'assembleur sans aucune sécurité appliquée. Cela peut être assez
dangereux, et ne devrait être utilisé que par les utilisateurs
d'assembleur les plus avertis et expérimentés. C'est également la base du
propre harnais de tests unitaires du compilateur : un fichier de test est
typiquement un enveloppement `function main() ... end` autour d'une
séquence de blocs `__rawasm__` avec des étiquettes `__debugN:` pour poser
des points d'arrêt sous [v32sim](https://github.com/g7n-org/v32sim).

---

## Référence de la Carte Mémoire

| Adresse RAM | Désignation | Utilisation |
| --- | --- | --- |
| `0` | `HEAP_POINTER` | Stocke l'adresse de départ dynamique pour les allocations de tables à l'exécution. |
| `1`, `2` | `FTOA_SCRATCH_PTR_A`/`B` | Mots de travail (scratch) réservés utilisés par la routine de conversion flottant-vers-chaîne. |
| `3` à `HEAP_START - 1` | RAM Globale | Emplacements alloués séquentiellement pour les variables globales Lua, les identifiants de ressources, et les `local`s de niveau supérieur promues. |
| `HEAP_START` et au-delà | Tas (Heap) Dynamique | Mémoire d'exécution gérée par l'allocateur de tables et les routines de chaînes. |
| Sommet de Pile (`SP`) | Pile d'Appels | Enregistrements d'activation des fonctions, variables locales, et états de registres sauvegardés. |

`HEAP_START` est calculé après la fin de toute la génération de code, de
sorte que la génération de code des instructions de niveau supérieur qui
enregistre des globales tardives ne puisse jamais entrer en collision
avec le tas.

---

## Particularités et hypothèses du compilateur

Bien que `v32lua` tente d'être un compilateur Lua fonctionnel, il n'est en
aucun cas une implémentation complète et conforme à la spécification du
langage. Pour commencer, il n'y a ni machine virtuelle à bytecode, ni
interpréteur — Lua est compilé directement en assembleur natif.

De plus, il existe quelques déviations explicites par rapport à une
implémentation standard du langage afin de mieux s'adapter à
l'environnement autonome (freestanding) de Vircon32 :

* `print()` requiert, comme ses deux premiers paramètres, la position `x`
  et `y` à l'écran.

* Les instructions `return` isolées ne fonctionnent pas (elles génèrent
  une erreur de syntaxe). Donnez-leur quelque chose (`nil`, `0`, etc.)
  pour qu'elles fonctionnent.

* L'exécution du programme DOIT résider à l'intérieur d'une fonction.
  Bien que vous puissiez déclarer des fonctions, vous devez utiliser
  l'un des points de départ désignés pour amorcer la chaîne d'exécution
  (`init()`, `game_loop()`, ou `main()`). Ne pas avoir de fonction
  `main()` ou `game_loop()` entraîne une erreur de compilation.
  `game_loop()` émet automatiquement un `WAIT` avant de s'appeler à
  nouveau, ce qui en fait votre emplacement naturel de boucle de jeu —
  similaire à d'autres consoles de fantaisie (comme la fonction `TIC()`
  dans TIC-80, qui est requise de manière similaire).

* `v32lua` est une implémentation **uniquement en virgule flottante** :
  il n'existe pas le type numérique double entier/flottant de Lua 5.3+.
  Tous les nombres sont des flottants IEEE-754 32 bits, de sorte que les
  entiers au-delà de 2^24 ne peuvent pas être représentés exactement —
  un point à garder à l'esprit pour le code fortement axé sur la
  manipulation de bits.

* Une `local` déclarée dans un bloc lexicalement en dehors de toute
  fonction (un `do...end` nu, ou un corps `if`/`while`/`for` au niveau du
  chunk) n'a actuellement aucun garde-fou au niveau du compilateur si une
  fonction la lit ultérieurement — voir le point de la feuille de route
  ci-dessous.

Clairement, cet effort est concentré sur la création d'un outil pour le
développement sur Vircon32, et non sur une implémentation Lua totalement
conforme. Des efforts seront faits pour s'en approcher autant que
possible et faisable, sans sacrifier une performance significative ni
s'éloigner de l'outil qu'il est censé être.

## Optimisation du Compilateur

Au tout début du développement du compilateur, tout le code
d'optimisation a été retiré et transféré dans un outil séparé,
[`v32opt`](https://github.com/wedge1020/v32opt). Celui-ci est conçu comme
un optimiseur d'assembleur Vircon32 à usage général, destiné à être
utilisé avec le compilateur C et le compilateur Lua (ainsi qu'avec de
l'assembleur écrit à la main). Les premiers tests ont montré de légères
améliorations de performance, et des économies d'espace potentielles en
éliminant les instructions redondantes.

Au moment d'écrire ces lignes, cet outil est encore très en cours de
développement, mais il montre des promesses et fonctionnera probablement
pour des scénarios standards sous les niveaux d'optimisation `-O1`,
`-O2`, et même `-O3`. Il est conçu pour être inséré dans la chaîne de
compilation après la compilation et avant l'assemblage.

## Feuille de Route / Pas Encore Implémenté

Ce qui suit sont des lacunes connues et délibérées plutôt que des bugs —
soit reportées pour maintenir l'élan du développement initial, soit en
attente d'une décision de conception :

* `pcall`/`error`/`assert`
* `string.match`/`gmatch`, `setmetatable`
* travail supplémentaire sur les couches d'API PICO-8 et TIC-80
* `tonumber(s, base)` — la forme à deux arguments, avec base explicite
* Un diagnostic (avertissement/erreur) pour la lecture, depuis
  l'intérieur d'une fonction, d'une `local` déclarée dans un bloc
  lexicalement en dehors de toute fonction au niveau du chunk (voir
  ci-dessus)

---

## Utilisation de l'IA

REMARQUE : Il y a eu une utilisation et une interaction étendues avec
l'IA tout au long de cet effort. Une distinction doit être faite par
rapport au « vibe coding », mais il existe indéniablement un flou entre
l'humain et l'IA. En fin de compte, les deux en bénéficient et pourraient
compenser les lacunes de l'autre.

Cette entreprise ne visait en réalité pas principalement à développer un
compilateur ; elle a commencé comme une tentative honnête de se faire une
idée de l'IA et de son impact : son rôle et son détriment pour la pensée
et l'éducation humaines. Le fait qu'elle ait eu un thème de compilateur
servait simplement à accentuer un point d'intérêt. Cela a certainement
été une expérience d'apprentissage. Si les concepts de compilation et les
connaissances de fond nécessaires n'avaient pas été suffisamment connus
avant de commencer cela, l'effort se serait terminé de façon bien moins
réussie.
