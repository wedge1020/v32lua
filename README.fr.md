# v32lua : Compilateur Lua pour Vircon32

[Version anglaise / in English](README.md) | [Version espagnole / en español](README.es.md)

**Architecture Cible :** Console de fantaisie Vircon32 (32-bit)

**Langage d'Implémentation :** C (Flex/Bison + Émetteur Sémantique Personnalisé)

**Dépôt :** [github.com/wedge1020/v32lua](https://github.com/wedge1020/v32lua)

**Référence de l'API :** [doc/API.fr.md](doc/API.fr.md) — l'API native complète
de Vircon32 (son, graphismes, entrées, tuiles/tilemaps, carte mémoire, et
ports d'E/S bruts). Commencez par sa [Référence rapide](doc/API.fr.md#quick-reference) :
chaque intrinsèque et chaque port `ioports.*` réunis en un seul endroit.

**Construire une cartouche :** [doc/USAGE.fr.md](doc/USAGE.fr.md) — la ligne de
commande, les indices `--#`, le XML généré, et les outils Vircon32 qui
terminent le travail.

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
fantaisie rétro, `v32lua` propose des intrinsèques « matériels » de bas
niveau à coût nul, un [NaN-boxing](doc/NaN_boxing.md) personnalisé, et —
au-delà de l'API native de Vircon32 — deux couches de compatibilité d'API
afin que les cartouches écrites pour **TIC-80** et **PICO-8** puissent être
compilées et exécutées dans l'environnement Vircon32 avec peu ou pas de
modification du code source.

```
+------------------+     +-------------------+     +------------------+
| Source (.lua)    | --> | Lexer & Parseur   | --> | Construction AST |
+------------------+     | (Flex / Bison)    |     +------------------+
                         +-------------------+              |
                                                            v
+------------------+     +-------------------+     +------------------+
| Config Cartouche | <-- | Émetteur Vircon32 | <-- | Émetteur         |
| (.xml)           |     | assembleur (.asm) |     | Sémantique       |
+------------------+     +-------------------+     +------------------+
```

---

## Table des Matières

- [Pour Commencer](#pour-commencer)
- [Couches de Compatibilité d'API](#couches-de-compatibilité-dapi)
  - [Clavier et souris (v32io)](#clavier-et-souris-v32io)
- [Indices de Ressources de Cartouche (`--#...`)](#indices-de-ressources-de-cartouche)
- [Pipeline de Compilation](#pipeline-de-compilation)
- [Fonctionnalités Clés du Langage et du Compilateur](#fonctionnalités-clés-du-langage-et-du-compilateur)
- [Fonctionnalités Lua Prises en Charge](#fonctionnalités-lua-prises-en-charge)
- [E/S Matérielle et Intrinsèques du Compilateur](#es-matérielle-et-intrinsèques-du-compilateur)
- [Assembleur en Ligne (`__asm__` et `__rawasm__`)](#assembleur-en-ligne-__asm__-et-__rawasm__)
- [Référence de la Carte Mémoire](#référence-de-la-carte-mémoire)
- [Particularités, Hypothèses et Limitations Connues du Compilateur](#particularités-et-hypothèses-du-compilateur)
- [Optimisation du Compilateur](#optimisation-du-compilateur)
- [Feuille de Route / Pas Encore Implémenté](#feuille-de-route--pas-encore-implémenté)
- [Utilisation de l'IA](#utilisation-de-lia)

---

## Pour Commencer

**Prérequis**

* Une chaîne d'outils C (`gcc`/`clang` + `make`), ou CMake 3.13+ comme
  compilation alternative (voir [Compiler avec CMake](#compiler-avec-cmake))
* Si le lexer/parseur est modifié, les outils `flex` et `bison` sont
  nécessaires pour régénérer les routines C du lexer/parseur. Les routines
  C déjà générées par `flex` et `bison` sont incluses dans le dépôt pour
  simplifier la compilation, ce qui évite dans la plupart des cas d'avoir
  réellement besoin de `flex`/`bison`
* La chaîne d'outils [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases) (assembleur et `packrom`) si vous comptez
  aller jusqu'au bout, du `.lua` à une cartouche `.v32` exécutable, plus
  [v32sim](https://github.com/g7n-org/v32sim) si vous souhaitez exécuter ou
  déboguer le résultat (également utilisé pour les tests unitaires).

**Compiler le Compilateur**

Le dépôt inclut un Makefile à la racine qui gère la compilation du binaire
du compilateur, l'exécution de la suite de tests, et l'entretien général du
projet. Pour compiler le binaire principal du compilateur depuis les
sources, exécutez la cible par défaut depuis la racine du dépôt :

```bash
make
```

Ceci compile les différents fichiers sources et produit le binaire
`v32lua` (sous `bin/`), qui transforme un fichier source `.lua` en un
fichier `.asm` Vircon32 accompagné d'un `.xml` de cartouche. À partir de
là, l'assemblage et l'empaquetage suivent les mêmes étapes que n'importe
quel autre projet Vircon32 (assembler → `packrom` → exécuter sous
[v32sim](https://github.com/g7n-org/v32sim) ou sur l'émulateur officiel).

*Tableau de Référence des Cibles du Makefile*

| Cible | Description |
| --- | --- |
| **`all`** | **Cible par défaut.** Compile le compilateur (`bin/v32lua`) dans `src/`. |
| **`clean`** | Supprime les artefacts de compilation de `src/` et les fichiers générés dans `testing/` et `demos/`. |
| **`install`** | Copie `bin/v32lua` dans `~/bin/bin.$(ARCH)/` si ce répertoire existe, sinon dans `~/bin/`. |
| **`sysinstall`** | Installation système : `bin/v32lua` dans `/usr/local/bin/`, la page de manuel dans `/usr/local/share/man/man1/` et la bibliothèque de `--#include` (`lib/*.lua`) dans `/usr/local/Vircon32/v32tools/include/v32lua/` (nécessite généralement `sudo` ; voir [Installation](#installation)). |
| **`sysuninstall`** | Supprime ce que `sysinstall` a installé. |
| **`tests`** | Exécute les tests unitaires de `testing/` : chaque programme est compilé, assemblé, empaqueté et exécuté sur [v32sim](https://github.com/g7n-org/v32sim), et ses résultats sont comparés au bloc `EXPECTED OUTPUT` du fichier (nécessite les DevTools, v32sim et `v32lua` dans votre `PATH`). |
| **`asmcheck`** | Compile les tests et assemble chaque résultat (`.vbin`), ce qui vérifie l'assembleur généré. |
| **`v32check`** | Comme `asmcheck`, et empaquette en plus chaque test dans une cartouche `.v32`. |
| **`demos`** | Compile toutes les démos sous `demos/` (voir [Compiler les démos](#building-the-demos)). |
| **`version`** | Affiche la version tirée de `inc/v32lua.h` et l'inscrit dans `man/v32lua.1` et `doc/DEBUGGING.md` (à lancer avant une publication). |
| **`monofiles`**, **`context`**, **`put`** | Rassemblent les sources dans `put/` sous forme de fichiers texte uniques, à coller dans une conversation. |
| **`archive`** | Nettoie, puis compresse le projet dans `v32lua-project.zip`. |

La chaîne de version se trouve à un seul endroit, `#define VERSION` dans
`inc/v32lua.h` ; `v32lua --version` l'affiche et `make version` la copie
dans la page de manuel et le guide de débogage.

<a id="compiler-avec-cmake"></a>
**Compiler avec CMake**

Pour ceux qui le préfèrent, `CMakeLists.txt` compile le même compilateur
à partir des mêmes sources (le Makefile reste la compilation principale,
et `make tests` reste l'exécution complète des tests sur v32sim) :

```sh
cmake -S . -B build              # Release par défaut
cmake --build build              # build/v32lua
ctest --test-dir build           # compile chaque programme de test
sudo cmake --install build       # voir « Installation » plus bas
```

`ctest` vérifie que chaque programme des catégories de `testing/`
qu'exécute `make tests` se compile, et que ceux de `testing/fail/` sont
refusés ; les exécuter reste le rôle de `make tests`. flex et bison sont
utilisés s'ils sont trouvés (`-DV32LUA_REGENERATE_PARSER=OFF` les
ignore) ; sinon `src/parser.c`, `inc/parser.h` et `src/lexer.c`, déjà
générés, sont compilés tels quels, si bien qu'une compilation ordinaire
ne demande qu'un compilateur C et CMake 3.13+. Sous **Windows**,
compilez avec MinGW-w64 64 bits (par exemple depuis un terminal MINGW64
de MSYS2, `cmake -S . -B build -G "MSYS Makefiles"`) ; MSVC n'est pas
pris en charge. `cpack --config build/CPackConfig.cmake` produit un
`.tar.gz` (plus `.deb` / `.rpm` là où `dpkg-deb` / `rpmbuild` sont
disponibles), ou un `.zip` sous Windows.

<a id="installation"></a>
**Installation**

Une installation système met tout là où une installation de Vircon32
l'attend. Le binaire et la page de manuel vont là où vont les commandes
et les pages de manuel ; la bibliothèque de `--#include` et les documents
vont dans `v32tools/`, le dossier que partagent les outils de la
communauté (avec [v32opt](https://github.com/wedge1020/v32opt) et
v32c++), à côté des `DevTools/` officiels :

| | Linux / macOS | Windows (CMake) |
| --- | --- | --- |
| compilateur | `/usr/local/bin/v32lua` | `C:\Program Files\Vircon32\v32tools\v32lua.exe` |
| page de manuel | `/usr/local/share/man/man1/v32lua.1` | `...\v32tools\docs\v32lua\v32lua.1` |
| bibliothèque de `--#include` (`lib/*.lua`) | `/usr/local/Vircon32/v32tools/include/v32lua` | `...\v32tools\include\v32lua` |
| documentation | `/usr/local/Vircon32/v32tools/docs/v32lua` (CMake) | `...\v32tools\docs\v32lua` |

L'une ou l'autre compilation s'en charge :

```sh
sudo make sysinstall                          # Linux / macOS
sudo make sysuninstall

sudo cmake --install build                    # tout système (préfixe : /usr/local,
sudo cmake --build build --target uninstall   #   ou C:/Program Files/Vircon32)
```

Le répertoire de la bibliothèque est intégré au compilateur : une fois
l'installation faite, `--#include "string.lua"` fonctionne depuis
n'importe quel répertoire. Avec CMake, choisissez un autre emplacement à
la configuration (`cmake -S . -B build
-DCMAKE_INSTALL_PREFIX=/opt/vircon32`) et le compilateur y cherchera ;
`-DV32LUA_INSTALL_INCLUDEDIR=...` (et `BINDIR`, `MANDIR`, `DOCDIR`)
déplacent une seule partie. La désinstallation ne supprime que les
fichiers de v32lua, puis `v32tools/` (et sous Linux / macOS `Vircon32/`)
seulement s'il n'y reste rien d'autre. Sous Windows, ajoutez
`C:\Program Files\Vircon32\v32tools` à votre `PATH`, comme pour les
DevTools.

`make install`, lui, ne copie que le binaire dans `~/bin`. Les valeurs
par défaut de la compilation par le Makefile (le répertoire de la
bibliothèque, les fréquences d'échantillonnage et les ports de manette
par défaut, ...) se trouvent dans [`inc/config.h`](inc/config.h) ;
modifiez-en une puis recompilez, ou remplacez-la à la compilation :

```sh
make CFLAGS="-Wall -Wextra -g -I ../inc -DYYDEBUG=1 -DV32LUA_INCLUDE_PATH='\"/opt/v32tools/include/v32lua\"'"
```

<a id="building-the-demos"></a>
**Compiler les démos**

Chaque démo sous `demos/pico8/` et `demos/tic80/` possède un Makefile qui
compile, assemble et empaquette la cartouche dans `bin/<demo>.v32`. Si
l'optimiseur d'assembleur [v32opt](https://github.com/wedge1020/v32opt) est
dans votre `PATH`, la même exécution produit aussi une cartouche optimisée,
`bin/<demo>Opt.v32` (à partir de `obj/<demo>Opt.asm` et `<demo>Opt.xml`).
Les étapes optimisées ont le droit d'échouer : si `v32opt` ou l'assembleur
rejette le code optimisé, `make` affiche l'erreur et continue, et la
cartouche normale est tout de même produite. Sans `v32opt`, la compilation
optimisée est sautée avec un message ; désactivez-la de force avec
`make HAVE_OPTIMIZER=`, ou changez les options avec
`make OPTIMIZER="v32opt -O2"`.

**Votre Première Cartouche**

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
    ioports.gpu.clear()             -- efface l'écran avec bgcolor

    -- Met à jour l'état en utilisant des calculs en virgule flottante purs
    if ioports.inp.left > 0 then    -- > 0 : maintenu (en images) ; < 0 : relâché
        x_pos = x_pos - speed
    elseif ioports.inp.right > 0 then
        x_pos = x_pos + speed
    end

    -- Dessin matériel direct
    ioports.gpu.x = x_pos
    ioports.gpu.y = y_pos
    ioports.gpu.draw()

    -- Concaténation de chaînes intégrée ; print() prend d'abord x, y
    local frame = system.frames
    if frame > 1000 then
        print(10, 10, "Demo Running: Frame " .. frame)
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

**Utilisation en Ligne de Commande**

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

Options de cartouche — chacune remplace l'indice `--#` correspondant dans
le source, de sorte qu'une cartouche PICO-8 ou TIC-80 se compile sans
modification (`--opt=valeur` fonctionne aussi) :

* `--api pico8|tic80|vircon32` : Sélectionne la couche d'API. Sans elle,
  l'API est détectée : un `.p8` est PICO-8, un `.tic` est TIC-80, et un
  `.lua` utilise son propre indice `--#api`/`--#p8` — ou, à défaut, ses
  points d'entrée (`TIC()` → tic80 ; `_draw()`/`_update()`/`_update60()`
  → pico8 ; sinon natif).
* `--title "texte"` : Titre de la cartouche, utilisé tel quel. Sans elle :
  l'indice `--#title`, sinon le titre propre à la cartouche (la métadonnée
  `-- title:` de TIC-80, la première ligne de commentaire de PICO-8) ou le
  nom du fichier — préfixé par `[PICO8] ` ou `[TIC80] ` dans ces modes
  d'API.
* `--rate 11025|22050|44100` : Fréquence d'échantillonnage du son
  synthétisé à partir d'une cartouche PICO-8 ou TIC-80 (22050 par défaut ;
  voir [doc/PICO8.md](doc/PICO8.md#sound) et
  [doc/TIC80.md](doc/TIC80.md#sound)). `--p8rate` est l'ancien nom.
* `--bezel art.png` : panneaux latéraux PICO-8 tirés de vos propres images
  au lieu de ceux intégrés (voir [doc/PICO8.md](doc/PICO8.md#side-panels)) ;
  `--no-bezel` : marges noires.
* `--fast-circles` : les cercles pleins TIC-80/PICO-8 de rayon supérieur à
  31 sont dessinés comme un disque mis à l'échelle.

Les valeurs par défaut de ces options (fréquences d'échantillonnage par
API, panneaux latéraux activés ou non et fichier d'image de panneau par
défaut, cercles rapides, avertissements) sont définies dans
`inc/config.h` : modifiez-les là et recompilez, ou passez-les à la
compilation (`make CFLAGS="... -DV32LUA_DEFAULT_PICO8_RATE=11025"`).
Priorité : l'option de ligne de commande, puis l'indice `--#` dans le
source, puis `config.h`.

```bash
$ v32lua celeste.p8 --title "celeste" --rate 11025     # API détectée depuis .p8
$ v32lua game.tic                                        # cartouche binaire TIC-80
```

Fichiers d'entrée : `.lua`, `.p8` (cartouche PICO-8), `.tic` (cartouche
TIC-80, cartouches Lua uniquement ; le code ainsi que les tuiles, sprites,
carte, drapeaux, palette, formes d'onde et SFX de la banque 0 sont lus —
les mêmes données que contient un export `.lua` de TIC-80).

---

## Couches de Compatibilité d'API

`v32lua` prend en charge trois surfaces d'API distinctes, sélectionnées
avec l'indice de cartouche `--#api` (l'API native de Vircon32 est celle
par défaut lorsqu'aucun indice `--#api` n'est présent) :

```lua
--#api "tic80"   -- opte pour la surface d'API compatible TIC-80
--#api "pico8"   -- opte pour la surface d'API compatible PICO-8
```

* **API native Vircon32** (par défaut) — accès direct et à coût nul aux
  IOPorts propres de la console : `ioports.gpu.*`, `ioports.spu.*`,
  `ioports.inp.*`, `music.*`/`sfx.*`, `system.*`, `rect()`/`rectfill()`,
  l'API native `tilemap.*`, un clavier complet à travers un
  périphérique v32kbd (`key()`/`keyp()`, texte tapé avec `kbd.read()`) et
  une souris à travers un périphérique v32mouse (`mouse()`, `mouse.*`).
  Entièrement documentée dans [doc/API.fr.md](doc/API.fr.md).
* **Couche de compatibilité TIC-80** (`--#api "tic80"`) — les appels au
  format TIC-80 (`spr()`, `btn()`/`btnp()`, `map()`/`mset()`/`mget()`, les
  fonctions son/musique, et les sections de ressources façon console de
  fantaisie) compilés en instructions natives Vircon32, y compris la mise
  à l'échelle des coordonnées nécessaire pour faire correspondre l'écran
  logique 240×136 de TIC-80 à la résolution physique de Vircon32.
  `sfx()`/`music()` jouent les `WAVES`/`SFX`/`PATTERNS`/`TRACKS` de la
  cartouche elle-même, synthétisés à la compilation par un portage du
  moteur sonore de TIC-80 (voir [doc/TIC80.md](doc/TIC80.md)) ; `spr()`
  gère la rotation ; Start met le jeu en pause (comme sur la couche
  PICO-8). `print()` respecte sa couleur et renvoie la largeur du texte.
  `key()`/`keyp()` lisent un vrai clavier à travers un périphérique v32kbd
  (codes de touche TIC-80, répétition comprise), et `mouse()` une vraie
  souris à travers un périphérique v32mouse.
  `map()` accepte tous les arguments optionnels de TIC-80, y compris
  `scale` (mais pas la fonction de remappage) ; `fget()` renvoie un booléen
  et `fset()` en prend un. `peek`/`peek1`/`peek2`/`peek4`,
  `poke`/`poke1`/`poke2`/`poke4`, `memcpy` et `memset` agissent sur une RAM
  TIC-80 émulée de 96 Ko, créée à la première utilisation avec la palette,
  les tuiles, les sprites et la carte de la cartouche ; les zones de la
  carte (0x08000), de la manette (0x0FF80) et des drapeaux de sprites
  (0x14404) sont des vues directes de `mget`/`mset`, des boutons et de
  `fget`/`fset`. Les autres écritures sont stockées mais ne modifient ni
  l'écran ni le son. `pmem` dispose des 256 emplacements 32 bits de TIC-80
  sur la carte mémoire. Sur les deux couches de console de fantaisie, les
  cercles jusqu'au rayon 31 coûtent un seul dessin GPU chacun (pré-rendus à
  la compilation, identiques au pixel près à ceux des consoles). Une
  fonction que le programme définit lui-même (`function pal(...)`)
  remplace la fonction intégrée du même nom, comme en Lua.
* **Couche de compatibilité PICO-8** (`--#api "pico8"`) — l'équivalent au
  format PICO-8 : `spr`/`map`/`mget`/`mset`/`fget`/`fset`, `cls`,
  `rectfill`/`rect`/`circfill`/`circ`/`line`/`pset`/`print` (avec
  couleur), `camera`/`color`, `btn`/`btnp` (répétition automatique
  PICO-8), `add`/`del`/`count`/`foreach`/`for v in all(t)` (sûrs en cas de
  suppression), les maths PICO-8 (`flr`, `rnd`, `mid`, `sin`/`cos` en
  tours, ...), `sspr`, `split`, `tostr`/`tonum`, `_ENV[nom]`, les
  raccourcis de syntaxe PICO-8 (`?`, `\`, `f"chaîne"`, glyphes des
  boutons, ...), `sfx`/`music` qui jouent le `__sfx__`/`__music__` de la
  cartouche elle-même (synthétisé à la compilation), `time`/`t`,
  `peek`/`poke` (8/16/32 bits, et les opérateurs `@ % $`), `memcpy`/
  `memset`/`reload`/`sget`/`sset` sur une RAM émulée de 64 Ko organisée
  comme celle de PICO-8 (carte, drapeaux, stylo, caméra et boutons en
  direct ; écritures à l'écran dessinées), `cartdata`/`dget`/`dset`
  sauvegardés sur la carte mémoire, la souris du devkit (`stat(32..34)`,
  plus le `mouse()` de TIC-80) à travers un périphérique v32mouse, et
  `_init`/`_update` (30 i/s)/`_update60`/`_draw`. L'écran 128×128 est mis à
  l'échelle 2,75× et centré ; ce qui est dessiné en dehors est masqué.
  **Une cartouche `.p8` se compile directement** (`v32lua jeu.p8`) : sa
  section `__lua__` est le programme et ses sections `__gfx__`/`__gff__`/
  `__map__` deviennent la planche de sprites, les drapeaux de sprites et la
  carte. Un simple `.lua` peut prendre ces ressources dans une cartouche
  avec `--#p8 "jeu.p8"`. Voir [doc/PICO8.md](doc/PICO8.md).

Une seule surface d'API est active par cartouche ; sélectionner `tic80` ou
`pico8` remplace la surface d'appel native au lieu de s'y ajouter.


### Clavier et souris (v32io)

> **⚠ Le clavier et la souris demandent du matériel en plus ou un
> émulateur modifié.** La console Vircon32 n'a ni clavier ni souris :
> seulement quatre manettes. Les fonctions clavier et souris de v32lua
> (`key()`/`keyp()`/`kbd.*` et `mouse()`/`mouse.*` natives,
> `key()`/`keyp()`/`mouse()` de TIC-80, `stat(32..34)` de PICO-8) lisent un
> clavier ou une souris **déguisés en manette**, et ne fonctionnent
> **qu'avec** l'une de ces solutions :
>
> * l'**adaptateur matériel v32io** — une carte Waveshare RP2350-USB-A
>   (résistance R13 retirée) avec le firmware v32io : un clavier ou une
>   souris USB branchés dessus apparaissent sur l'ordinateur comme une
>   manette (`v32io:kbd` / `v32io:mouse`), donc il fonctionne avec
>   **n'importe quel** émulateur Vircon32, y compris celui d'origine, une
>   fois son profil de joystick configuré ;
> * un **émulateur Vircon32 modifié**, qui lit le clavier et la souris de
>   l'ordinateur comme des périphériques v32io (sans matériel) : le fork
>   [wedge1020/ComputerSoftware](https://github.com/wedge1020/ComputerSoftware),
>   [branche `v32io`](https://github.com/wedge1020/ComputerSoftware/tree/v32io)
>   (avec `v32kbd` et `v32mouse`), ou les sources du DesktopEmulator
>   d'origine auxquelles on applique les correctifs `emulator/v32kbd.patch`
>   et `emulator/v32mouse.patch` du projet v32io.
>
> **Sans l'une d'elles, l'accès au clavier et à la souris est impossible :**
> les programmes se compilent et s'exécutent, mais aucune touche n'est
> jamais enfoncée et la souris ne bouge pas. Les programmes qui en ont
> besoin devraient le dire et, si possible, proposer aussi des commandes à
> la manette.

Le clavier est lu par défaut sur le port de manette 2 (le troisième) et
la souris sur le port 3 (le quatrième), ce qui laisse les ports 0 et 1
aux manettes ordinaires (`--keyboard N`, `--mouse N`, `--#keyboard N`,
`--#mouse N`, ou `kbd.port(n)` / `mouse.port(n)` à l'exécution). Les
ports sont numérotés à partir de 0 ; les menus de l'émulateur appellent
le port 2 « Gamepad 3 » et le port 3 « Gamepad 4 ». Les protocoles, la lecture
à chaque image ajoutée par le compilateur et la configuration sont décrits
dans [doc/API.fr.md](doc/API.fr.md#clavier-et-souris--ce-quil-faut-v32io).

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
| `--#p8 "cart.p8"` | PICO-8 : prend la planche de sprites, les drapeaux de sprites et la carte d'une cartouche `.p8` (implique `--#api pico8`). |
| `--#rate 11025` \| `22050` \| `44100` | Fréquence d'échantillonnage du son synthétisé à partir d'une cartouche PICO-8 ou TIC-80 (22050 par défaut ; `--#p8rate` est l'ancien nom ; voir [doc/PICO8.md](doc/PICO8.md#sound)). |
| `--#bezel off` \| `on` \| `"art.png"` | PICO-8 : les panneaux latéraux à côté de l'écran 128×128 — aucun, les images intégrées, ou les vôtres (voir [doc/PICO8.md](doc/PICO8.md#side-panels)). |
| `--#fast-circles` | TIC-80/PICO-8 : les cercles pleins de rayon supérieur à 31 sont dessinés comme un seul disque mis à l'échelle (plus rapide, bords légèrement différents). |
| `--#keyboard 0`–`3` | Port de manette d'un clavier v32kbd (adaptateur v32io ou émulateur modifié nécessaire, voir [Clavier et souris](#clavier-et-souris-v32io)), pour `key()`/`keyp()`/`kbd.*` (2 par défaut ; voir [doc/API.fr.md](doc/API.fr.md#clavier--key--keyp--kbd)). |
| `--#mouse 0`–`3` | Port de manette d'une souris v32mouse (adaptateur v32io ou émulateur modifié nécessaire, voir [Clavier et souris](#clavier-et-souris-v32io)), pour `mouse()`/`mouse.*` et `stat(32..34)` de PICO-8 (3 par défaut ; voir [doc/API.fr.md](doc/API.fr.md#souris--mouse--mouse)). |
| `--#texture NOM "chemin/image.png"` | Enregistre une ressource de texture et la lie à une constante `NOM` à la compilation. Le XML nomme le fichier `.vtex` (`image.vtex`) que `png2vircon` produit à partir du PNG. |
| `--#sound NOM "chemin/son.wav"` | Enregistre une ressource sonore et la lie à une constante `NOM` à la compilation. Le XML nomme le fichier `.vsnd` que produit `wav2vircon`. |
| `--#tilemap NOM "chemin/carte.csv"` | Enregistre une tilemap depuis un fichier CSV, intégrée directement dans l'image ROM (voir [doc/API.fr.md](doc/API.fr.md#tilemap--tilemap)). |
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

**Projets Multi-Fichiers (`--#include`)**

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
* Les cibles d'inclusion sont recherchées, dans l'ordre : dans le
  répertoire du fichier qui inclut ; dans le répertoire de travail courant
  du compilateur ; dans chaque entrée de la variable d'environnement
  `V32LUA_INCLUDE` si elle est définie (une liste séparée par des
  deux-points ; par des points-virgules sous Windows) ; et enfin dans le
  chemin d'inclusion par défaut intégré,
  `/usr/local/Vircon32/v32tools/include/v32lua` (fixé à la compilation :
  voir `inc/config.h`, ou [Installation](#installation) pour la
  compilation avec CMake). C'est là que `make sysinstall` et
  `cmake --install` placent les portages de la bibliothèque standard de
  `lib/`, de sorte que n'importe quel projet peut faire
  `--#include "string.lua"` sans avoir à copier la bibliothèque. Les
  chemins absolus sont utilisés tels quels.
* Les inclusions cycliques sont détectées, et chaque fichier résolu n'est
  inclus qu'une seule fois sur l'ensemble de l'expansion.
* Les indices de ressources de cartouche (`--#texture`, `--#sound`,
  `--#tilemap`) déclarés dans un fichier inclus reçoivent des identifiants
  de ressources corrects et un ordre correct dans le XML.
* Les messages d'erreur à l'intérieur d'un fichier inclus rapportent le
  fichier source et le numéro de ligne corrects, via une table interne de
  remappage de lignes.
* Deux fichiers inclus qui déclarent chacun une `local` de niveau
  supérieur portant le même nom partagent une seule variable globale —
  identique à ce que ferait le code monolithique équivalent.

---

## Pipeline de Compilation

**Flux de Compilation**

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

**Étapes de Compilation (`-v`)**

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

**Modèles d'Exécution Flexibles : `main()` vs. `game_loop()`**

Pour s'adapter à différents styles d'architecture de jeu, le compilateur
prend en charge deux points d'entrée de fonction distincts :

* **La Fonction à Attente Automatique (`game_loop`)** : Si votre programme
  déclare une fonction `game_loop()`, le compilateur génère automatiquement
  un harnais d'exécution continu. Le CPU appelle `game_loop()`, suspend
  l'exécution pour l'image en cours à l'aide de l'instruction `WAIT` du
  CPU, et boucle indéfiniment. Ceci est idéal pour les jeux d'arcade et
  démos standards, et imite le comportement de diverses autres consoles de
  fantaisie.

* **Contrôle Manuel (`main`)** : Si votre programme déclare une fonction
  `main()`, le CPU s'arrête à la fin de la fonction `main()`, un
  comportement semblable à celui de la fonction `main()` du C. Si vous
  souhaitez que l'exécution continue, vous devez mettre en place une
  forme de boucle de jeu, et exécuter les instructions `WAIT` nécessaires
  pour assurer un traitement continu et un affichage fluide des éléments à
  l'écran. Le compilateur vérifie si une instruction `WAIT` est émise à
  l'intérieur de `main()` ; si elle est absente, `v32lua` émet un
  avertissement sémantique à la compilation.

De plus, en préalable à l'un ou l'autre des modèles ci-dessus :

* **Point d'Initialisation** : Dans les deux modèles, si une fonction
  `init()` est présente, il est garanti qu'elle s'exécute exactement une
  fois, après les allocations de RAM globales de niveau supérieur et avant
  le début de la boucle principale.

Un programme doit déclarer au moins l'une des deux fonctions `main()` ou
`game_loop()` — il s'agit du point d'entrée désigné, et son absence est une
erreur de compilation.

**NaN-Boxing : Éléments RAM vs. ROM**

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
| **Chaîne RAM** | `0xFFC00000` | Chaînes construites à l'exécution, sur le tas (charge utile 4 et plus). |
| **Fonction** | `0x7F800000` | Adresse de code en ROM, ou (avec le bit 21 à 1) un enregistrement de fermeture en RAM. |
| **Table** | `0xFF800000` | Adresses mémoire de tas encapsulées (bit 31=1, bit 22=0). |
| **Nombre** | Flottant IEEE 754 | Valeurs en virgule flottante natives de Vircon32, non encapsulées, pour les calculs directs. |

**Intrinsèques Matériels et Mappage E/S**

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
  dynamiques. Consultez [doc/API.fr.md](doc/API.fr.md) pour la surface complète,
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

Consultez [doc/API.fr.md](doc/API.fr.md) pour la référence complète et
faisant autorité — ce README met en avant les idées, le document d'API
couvre chaque appel.

**Expérience de Développement et Outillage de Débogage**

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

**Variables et Portée**

* **Variables Globales :** Enregistrées automatiquement en RAM et
  accessibles via des symboles (`[var_nom]`, `[func_nom]`). L'adresse `0`
  est réservée au pointeur de tas (heap) et les adresses `1`/`2` sont des
  mots de travail (scratch) réservés utilisés par la routine de
  conversion flottant-vers-chaîne ; les variables globales ordinaires
  commencent à l'adresse `3`.

* **Variables Locales :** Déclarées avec le mot-clé `local`. À portée
  lexicale limitée au bloc englobant (corps de fonction, boucles, ou
  conditionnelles) et associées à des décalages de pile
  (`[BP - offset]`). Une `local` déclarée au propre niveau supérieur
  d'un chunk — en dehors de toute fonction — est promue en variable
  globale à la place, car son stockage résiderait sinon dans un cadre de
  pile qui retourne avant que tout code de jeu ne s'exécute ; ceci
  s'applique également aux `local`s introduites via `--#include`.

Dans le jargon Lua, les fonctions sont des « citoyennes de première
classe », et sont effectivement des variables. Cela se vérifie dans
`v32lua`, puisque les deux transitent au sein du schéma de NaN-boxing.

**Affectation Multiple**

Le compilateur prend nativement en charge l'affectation multiple et
l'échange de variables sans nécessiter de variables temporaires
explicites de la part de l'utilisateur :

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Synthétise des chaînes de registres temporaires pour échanger les valeurs en toute sécurité
```

**Opérateurs bit à bit**

Les opérateurs `&`, `|`, `~` (ou exclusif), `<<`, `>>` et `~` unaire
(non) de Lua 5.3/5.4. Chaque nombre est un float32, donc chaque opération
prend ses opérandes comme des mots de 32 bits et reconvertit le résultat :

* **Natif / TIC-80 :** des entiers. Les opérandes sont arrondis à l'entier
  inférieur et pris modulo 2^32, donc `0xFFFFFFFF` et `-1` sont le même
  mot. Le signe de la valeur complète est conservé, de sorte que `&`, `|`,
  `~` correspondent au Lua 64 bits pour des opérandes dans
  [-2^31, 2^32) : `-1 & 0xFF` vaut 255, `~0` vaut -1, `0xFF << 24` vaut
  4278190080. `>>` est logique ; un décalage de 32 ou plus donne 0.
* **PICO-8 :** virgule fixe 16.16, exactement comme le fait PICO-8 — les
  fractions participent (`0.5 | 1` vaut 1.5, `~0` vaut -1/65536), `>>` est
  arithmétique, et le `^^` (ou exclusif), le `>>>` (décalage logique à
  droite), les `<<>` / `>><` (rotation) de PICO-8, les formes composées
  (`&= |= ^^= <<= >>= >>>= <<>= >><=`), les fonctions `band`/`bor`/
  `bxor`/`bnot`/`shl`/`shr`/`lshr`/`rotl`/`rotr` et les littéraux binaires
  `0b1010` sont tous acceptés. Les littéraux hexadécimaux
  `0x8000`–`0xffff` sont négatifs, comme dans PICO-8 (`0xffff == -1`).

Limite : un float32 contient 24 bits significatifs, donc un résultat comme
`0xDEADBEEF` revient arrondi ; les masques et les champs regroupés ayant
moins de bits significatifs (`0xFF000000`, `0xF0F0`) sont exacts. Les
expressions de littéraux (`1 << 4`) sont calculées à la compilation.

**Programmation Orientée Objet et Tables**

`v32lua` fournit un sucre syntaxique transparent pour les modèles de POO
basés sur des tables :

* **Désucrage de la Définition de Méthode :** Définir une fonction sur
  une table génère automatiquement une étiquette au nom modifié et lie la
  propriété du pointeur de fonction :

```lua
function Player.move(dx, dy) --[[ corps ]] end
-- Se désucre en : Player["move"] = __function_Player_move
```

* **Désucrage de l'Appel de Méthode (opérateur `:`) :** Utiliser
  l'opérateur deux-points évalue automatiquement l'expression de table et
  l'injecte comme paramètre implicite `self` :

```lua
Player:move(5, -2)
-- Se désucre en : Player.move(Player, 5, -2)
```

**Flux de Contrôle**

* **Boucles :** `while ... do ... end`, `repeat ... until ...`, le `for`
  numérique `for i = a, b [, step]` et le `for` générique
  `for k, v in pairs(t)` / `ipairs(t)` (ou votre propre fonction
  d'itération), chacune avec sa propre portée de bloc.

* **Contrôle de Boucle :** Les instructions `break` sautent immédiatement
  vers l'étiquette de fin de la boucle la plus interne actuelle (suivie
  via une pile interne de compilation des boucles).

* **`goto` / `::étiquette::` :** étiquettes façon Lua 5.2, à portée de
  bloc, avec références en avant — l'idiome habituel `goto continue` /
  `::continue::` fonctionne, y compris avec le même nom d'étiquette dans
  plusieurs boucles d'une même fonction.

* **Conditionnelles :** Structures `if <cond> then ... elseif <cond> then
  ... else ... end` avec branchement en court-circuit.

**Opérateurs et Expressions**

* **Arithmétiques :** `+`, `-`, `*`, `/` (associés aux instructions
  matérielles en virgule flottante de Vircon32 `FADD`, `FSUB`, `FMUL`,
  `FDIV`), `%`, `^`, `//` (division entière) et le moins unaire. Une
  chaîne contenant un nombre est convertie dans les calculs, comme en Lua
  (`"5" + 1` vaut 6). Il n'y a pas d'erreur pour les autres opérandes
  (`"abc" + 1`, `nil + 1`) : le résultat n'a pas de sens.

* **Relationnels :** `==`, `~=` (via `__builtin_eq` avec désencapsulation
  de NaN), `<`, `>`, `<=`, `>=` (via le matériel `FLT`, `FLE`, `FGT`,
  `FGE`).

* **Logiques :** `and`, `or`, `not` (avec évaluation en court-circuit).

* **Concaténation de Chaînes :** l'opérateur `..` empile automatiquement
  les opérandes et invoque la sous-routine d'exécution
  `__builtin_strcat`.

* **Littéraux et méthodes de chaînes :** chaînes `"doubles"`, `'simples'`
  et longues `[[entre crochets]]` (sans échappements ; un saut de ligne
  juste après `[[` est ignoré). Les littéraux numériques acceptent les
  exposants (`1e-3`, `2.5E4`). Les fonctions de la bibliothèque de chaînes
  s'utilisent comme méthodes sur les valeurs de chaîne — `s:sub(2, #s)`,
  `("abc"):upper()`, `s:len()`, `rep`, `byte`, `find`, `lower`, `reverse`,
  `gsub` — et les chaînes utilisées comme clés de table sont comparées par
  contenu, donc `t["a" .. "b"]` trouve `t.ab`.

* **Nombres → chaînes :** les nombres entiers s'affichent sans point
  décimal (`"5"`), les autres avec jusqu'à 6 chiffres fractionnaires
  significatifs et sans zéros finaux (`"0.5"`, `"2.25"`) — précision
  float32.

* **Opérateur de Longueur :** l'opérateur `#` invoque `__builtin_len` pour
  résoudre les longueurs de chaînes ou de tables.

**Fonctions et Retours de Valeurs Multiples**

Les arguments sont passés sur la pile. Les fonctions peuvent retourner
plusieurs valeurs : les trois premières reviennent dans les registres
`R0`, `R2` et `R3`, et les suivantes passent par un tampon réservé en RAM.
Comme en Lua, un appel ou `...` en fin de liste se développe en toutes ses
valeurs — dans les arguments (`f(a, g())`), les constructeurs de table
(`{g()}`), `return x, ...` et `local a, b = ...` — jusqu'à 32 valeurs.
Les fonctions variadiques (`function f(...)`), les fermetures avec
upvalues (des locales capturées, partagées entre les fermetures qui les
capturent) et la récursivité fonctionnent toutes.

**Regroupement des Littéraux de Chaîne**

Tous les littéraux de chaîne déclarés dans le code source (par exemple,
`"GAME OVER"`) sont collectés lors de la compilation, dédupliqués, et
émis dans une section de données dédiée à la fin de la ROM
(`__string_0: string "GAME OVER"`), évitant une consommation redondante
de la ROM.

**Évaluation Truthy / Falsy en Court-Circuit**

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

**Métatables**

`setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawlen` et
`rawequal`. Ces événements sont pris en charge :

* `__index` : une table, qui peut avoir sa propre métatable (les chaînes
  de classes fonctionnent), ou une fonction `(t, k)`.
* `__newindex` : une table ou une fonction `(t, k, v)`, uniquement pour
  les clés absentes de la table, comme en Lua.
* `__call` : appeler la table, qui est passée en premier argument.
* `__tostring`, `__len`, `__metatable`.

```lua
Point = {}
Point.__index = Point
function Point.new(x, y) return setmetatable({x = x, y = y}, Point) end
function Point:len2() return self.x * self.x + self.y * self.y end
```

La métatable n'est consultée que lorsqu'une lecture ne trouve rien ou
qu'une écriture ajoute une nouvelle clé. Les tables sans métatable
exécutent le même code qu'avant. Les événements arithmétiques, de
comparaison et de concaténation (`__add`, `__eq`, `__lt`, `__concat`, …)
ne sont **pas** pris en charge : les opérateurs sont compilés en
instructions flottantes directes, et vérifier à chacune s'il s'agit d'une
table ralentirait toute l'arithmétique.

## E/S Matérielle et Intrinsèques du Compilateur

L'une des fonctionnalités les plus puissantes de `v32lua` est son
**moteur d'interception statique des intrinsèques**. Lorsque le
compilateur rencontre des accès à des tables ou des appels de fonctions
correspondant à des chemins système spécifiques (par exemple,
`ioports.gpu.clear()`), il **contourne entièrement les recherches
dynamiques dans les tables** et émet des instructions d'E/S matérielle
Vircon32 directes (`IN`, `OUT`).

**Conversion Automatique de Types aux Frontières d'E/S**

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

**Tableau de Référence Complet des Intrinsèques**

La référence complète et faisant autorité pour chaque intrinsèque —
`ioports.gpu.*`, `ioports.inp.*`, `ioports.spu.*`, `ioports.tim.*`,
`ioports.rng.*`, `ioports.car.*`, `ioports.mem.*`, `music.*`/`sfx.*`,
`tilemap.*`, `memcard.*`, et `system.*` — se trouve dans
[doc/API.fr.md](doc/API.fr.md), avec les mises en garde sur l'ordre des ports,
les signatures d'appel, et des exemples détaillés. Sa
[Référence rapide](doc/API.fr.md#quick-reference) liste chaque intrinsèque
et chaque port `ioports.*` (tous les `ioports.gpu.*` compris) sur une
seule page. Voici un bref échantillon des entrées les plus couramment
utilisées :

*Contrôle et Dessin GPU (`ioports.gpu.*`)*

| Chemin Lua / Intrinsèque | Port/Commande Vircon32 | Accès | Description et Comportement |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lecture / Écriture | Définit ou lit l'identifiant de texture actif utilisé pour les opérations de dessin. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lecture / Écriture | Sélectionne la sous-région de texture (image de sprite) à afficher. |
| **`ioports.gpu.x`** / **`ioports.gpu.y`** | `GPU_DrawingPointX/Y` | Lecture / Écriture | Coordonnées écran pour le placement du dessin. |
| **`ioports.gpu.minX/minY/maxX/maxY`** | `GPU_RegionMin/MaxX/Y` | Lecture / Écriture | Définit les limites en pixels de la région de texture active. |
| **`ioports.gpu.hotX/hotY`** | `GPU_RegionHotSpotX/Y` | Lecture / Écriture | Définit l'origine de dessin (hotspot) relative à la région du sprite. |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Appel de Fonction | Exécute une commande de dessin matérielle : `"zoom"`, `"rotate"`, `"rotozoom"`, ou la valeur par défaut. |
| **`ioports.gpu.clear([couleur])`**<br>**`ioports.gpu.clear(r, g, b [, a])`** | `GPU_ClearColor` + `GPU_Command` | Appel de Fonction | Définit la couleur d'effacement et efface l'écran. Prend en charge des chaînes de couleurs prédéfinies (`"black"`, `"white"`, `"blue"`, `"red"`, `"green"`), une valeur compressée `0xAABBGGRR` (un littéral, ou `rgba()`/`hex()` pour une valeur calculée à l'exécution), ou des composantes séparées : `clear(r, g, b [, a])`, chacune de `0` à `255`, alpha opaque par défaut. |
| **`rgba(r, g, b [, a])`** | — | Intrinsèque | Le mot compressé `0xAABBGGRR` (brut, pas un nombre Lua) pour le `color_mult` de `spr()`, `ioports.gpu.clear(couleur)`, `ioports.gpu.multiply` / `bgcolor`. Composantes limitées à `0`–`255` et tronquées, alpha à 255 par défaut ; calculé à la compilation quand toutes sont des littéraux. Gardez les couleurs sous forme de composantes et appelez `rgba()` là où elles sont dessinées — voir [doc/API.fr.md](doc/API.fr.md#colors-rgba) pour savoir pourquoi. |
| **`color(n)`** | — | Intrinsèque | Un nombre contenant une couleur compressée (calculée, ou lue dans une table), sous forme de mot brut. Arrondi à l'entier inférieur et ramené sur 32 bits ; les littéraux sont exacts, les valeurs d'exécution gardent les 24 bits significatifs du float32 ([détails](doc/API.fr.md#colors-color)). |
| **`rect(x1, y1, x2, y2 [, color])`**<br>**`rectfill(x1, y1, x2, y2 [, color])`** | `GPU_Command` (dessin agrandi) | Intrinsèque | Contour / rectangle plein entre deux coins inclus, dans n'importe quel ordre ; `color` est un mot empaqueté comme pour `spr()` (blanc par défaut). Un dessin GPU pour `rectfill`, jusqu'à quatre pour `rect` ; l'état du GPU est rétabli ensuite ([détails](doc/API.fr.md#graphismes--rect--rectfill)). |

*Manette et Entrées (`ioports.inp.*`)*

| Chemin Lua / Intrinsèque | Port/Commande Vircon32 | Accès | Description et Comportement |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lecture / Écriture | Sélectionne l'index de la manette active (`0`-`3`) pour le sondage des entrées. Sa lecture renvoie le dernier index affecté (les émulateurs ne savent pas relire le port). |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Lecture Seule | Retourne un booléen Lua : la manette sélectionnée est-elle connectée. |
| **`ioports.inp.left/right/up/down`** | `INP_Gamepad*` | Lecture Seule | État directionnel de la croix directionnelle (`> 0` pressé, `< 0` relâché). |
| **`ioports.inp.A/B/X/Y/L/R/START`** | `INP_GamepadButton*` | Lecture Seule | État des boutons d'action/gâchettes (`> 0` pressé, `< 0` relâché). |
| **`ioports.inp.inputs`** | *Sous-routine d'Action Personnalisée* | Lecture Seule | **Intrinsèque de regroupement :** sonde tous les boutons/axes de la manette en une seule passe, les regroupe en un unique masque de bits sur 32 bits, et le convertit en flottant Lua. |
| **`key([k])`**, **`keyp([k [, hold, period]])`** | périphérique v32kbd sur un port de manette | Intrinsèque | **Uniquement avec un adaptateur v32io ou l'émulateur modifié** ([pourquoi](#clavier-et-souris-v32io)). Un clavier complet à travers un périphérique v32kbd (port de manette 2 par défaut, `--#keyboard N`) : touche enfoncée / enfoncée à cette image, façon TIC-80, avec des codes de touche ou des noms littéraux (`"a"`, `"enter"`, `"shift"`) ([détails](doc/API.fr.md#clavier--key--keyp--kbd)). |
| **`kbd.read()`**, **`kbd.event()`**, **`kbd.port([n])`**, **`kbd.capslock()`**, **`kbd.connected()`**, **`kbd.clear()`** | périphérique v32kbd | Intrinsèque | Texte tapé (Maj et Verr Maj appliqués), événements d'appui/relâchement, le port du clavier, Verr Maj, périphérique présent, oubli des événements non lus. |
| **`mouse()`** | périphérique v32mouse sur un port de manette | Intrinsèque | **Uniquement avec un adaptateur v32io ou l'émulateur modifié** ([pourquoi](#clavier-et-souris-v32io)). Une souris à travers un périphérique v32mouse (port de manette 3 par défaut, `--#mouse N`) : `x, y, left, middle, right, scrollx, scrolly`, comme celui de TIC-80 (défilement toujours 0) ([détails](doc/API.fr.md#souris--mouse--mouse)). |
| **`mouse.pressed/released([b])`**, **`mouse.buttons()`**, **`mouse.delta()`**, **`mouse.position([x, y])`**, **`mouse.bounds(...)`**, **`mouse.scale([n])`**, **`mouse.port([n])`**, **`mouse.connected()`** | périphérique v32mouse | Intrinsèque | Changements de boutons à cette image, boutons enfoncés, mouvement à cette image, le pointeur, ses limites et sa vitesse, le port de la souris, périphérique présent. |

*Utilitaires Système et d'Exécution*

| Chemin Lua / Intrinsèque | Instruction Vircon32 | Accès | Description et Comportement |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Appel de Fonction | Émet l'instruction matérielle `HLT`, terminant immédiatement l'exécution du CPU ou figeant l'image jusqu'au prochain cycle d'interruption/image. |
| **`system.wait()`** | `WAIT` | Appel de Fonction | Émet l'instruction matérielle `WAIT`, mettant en pause l'exécution jusqu'au prochain cycle d'interruption/image. |
| **`system.frames()`** / **`system.cycles()`** | `TIM_FrameCounter` / `TIM_CycleCounter` | Lecture Seule | Images écoulées depuis la mise sous tension / cycles CPU utilisés jusqu'ici dans l'image en cours (les `()` sont facultatives). |
| **`print(x, y, valeur)`** | `__builtin_tostring` + `__builtin_print` | Appel de Fonction | Convertit `valeur` en chaîne et la dessine à l'écran avec la police du BIOS, à la position en pixels `x`, `y`. |

---

## Assembleur en Ligne (`__asm__` et `__rawasm__`)

Pour les boucles internes critiques en performance ou la manipulation
matérielle avancée de Vircon32, `v32lua` fournit une injection directe
d'assembleur en ligne.

**Assembleur en Ligne Standard (`__asm__`)**

La directive `__asm__` permet d'intégrer des chaînes d'assembleur brut de
Vircon32 directement à l'intérieur de fonctions Lua. Fait crucial, elle
prend en charge l'**interpolation de variables**, permettant un pont
transparent entre les symboles de portée Lua et les registres
d'assembleur :

```lua
local speed = 5.0
__asm__("MOV R0, {speed}\nFADD R0, 1.5\nMOV {speed}, R0")
```

* **Comment ça fonctionne :** Tout identifiant entouré d'accolades (par
  exemple, `{speed}`) est remplacé à la compilation par l'opérande mémoire
  de la variable : `[BP - n]` pour une locale, `[BP + n]` pour un
  paramètre, `[var_speed]` pour une globale. Le code doit être un seul
  littéral de chaîne (écrivez les sauts de ligne sous la forme `\n`). Une
  locale capturée par une fermeture contient un pointeur vers sa boîte
  plutôt que la valeur.

* Chaque ligne d'assembleur interpolé passe par le moteur de formatage du
  compilateur, garantissant une indentation et un alignement des
  commentaires cohérents dans le fichier `.asm` de sortie.

* Cet assembleur en ligne standard applique quelques garde-fous et
  protections légers, sous la forme d'une sauvegarde des registres
  actuellement utilisés ainsi que de la pile. Bien que cela ne prévienne
  pas tous les problèmes, cela peut aider à atténuer ceux causés par
  accident. Tout changement de registre effectué ici est perdu en dehors
  de la « bulle » en ligne.

**Assembleur Brut (`__rawasm__`)**

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
| `0` | `HEAP_POINTER` | Stocke l'adresse de départ dynamique pour les allocations de tables/chaînes à l'exécution. |
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
[v32opt](https://github.com/wedge1020/v32opt). Celui-ci est conçu comme
un optimiseur d'assembleur Vircon32 à usage général, destiné à être
utilisé avec le compilateur C et le compilateur Lua (ainsi qu'avec de
l'assembleur écrit à la main). Les premiers tests ont montré de légères
améliorations de performance, et des économies d'espace potentielles en
éliminant les instructions redondantes.

Au moment d'écrire ces lignes, cet outil est encore très en cours de
développement, mais il montre des promesses et fonctionnera probablement
pour des scénarios standards sous les niveaux d'optimisation `-O1`,
`-O2`, et même `-O3`. Il est conçu pour être inséré dans la chaîne de
compilation après la compilation et avant l'assemblage. Les Makefiles des
démos l'utilisent lorsqu'il est installé, en produisant une cartouche
optimisée `bin/<demo>Opt.v32` à côté de la cartouche normale (voir
[Compiler les démos](#building-the-demos) et
[doc/USAGE.fr.md](doc/USAGE.fr.md#5-facultatif--loptimiseur)).

## Feuille de Route / Pas Encore Implémenté

Ce qui suit sont des lacunes connues et délibérées plutôt que des bugs —
soit reportées pour maintenir l'élan du développement initial, soit en
attente d'une décision de conception :

* `pcall`/`error`/`assert`
* `string.match`/`gmatch` ; les événements de métatable `__add`/`__sub`/…, `__eq`/`__lt`/`__le`,
  `__concat`, `__unm` (voir [Métatables](#fonctionnalités-lua-prises-en-charge))
* `select()`, et `next()` comme fonction appelable (`pairs()` fonctionne)
* Les listes de valeurs multiples sont limitées à 32 valeurs : au-delà,
  les valeurs de retour d'un appel, un `...` développé ou `unpack(t)` sont
  perdus (`f(...)`, `{g()}`, `return x, ...`, `local a, b = ...` se
  développent tous, jusqu'à 32).
* Les opérateurs bit à bit agissent sur des mots de 32 bits (les nombres
  sont des float32) : `x << 32` et les résultats plus larges, ainsi que
  `>>` d'un nombre négatif, diffèrent des entiers 64 bits de Lua, et un
  résultat de plus de 24 bits significatifs (`0xDEADBEEF`) est arrondi.
  Voir **Opérateurs bit à bit** ci-dessus.
* `string.format` comme méthode (`("%d"):format(x)`) — utilisez
  `string.format(...)`.
* Le ramasse-miettes : le tas est un allocateur linéaire, donc chaque
  table, fermeture et chaîne créée à l'exécution vit jusqu'à la
  réinitialisation. Les jeux qui tournent longtemps devraient réutiliser
  leurs tables plutôt que d'en créer à chaque image. Les chaînes occupent
  un mot par caractère, donc construire une longue chaîne morceau par
  morceau (`s = s .. c` dans une boucle) consomme de la mémoire de façon
  quadratique : nanoman décode ses niveaux ainsi et remplit les 4M mots de
  RAM après environ 100 s de jeu.
* Un audio PICO-8 encore plus léger : le son d'une cartouche se limite
  désormais à ses 64 SFX à 22050 Hz (Celeste : 18 Mo, contre 66 Mo).
  Séquencer des notes isolées plutôt que des SFX entiers le réduirait
  encore de moitié environ (près de la moitié des notes de Celeste se
  répètent), au prix d'un séquenceur par note.
* PICO-8 : `pal`/`palt` (compilés en no-op avec un avertissement),
  `clip`, les vraies valeurs de `stat` (hors souris), les largeurs fractionnaires de
  `spr`, `pget`, le chargement multi-
  cartouche (`reload` depuis un autre fichier, `cstore`) ; écrire dans la
  mémoire des sprites ou du son est sans effet et lire la mémoire écran ne
  rend que ce qui y a été écrit (pas de relecture GPU) ; les filtres de
  l'éditeur de SFX dans le son synthétisé
* TIC-80 : `tri`/`trib`, `elli`/`ellib`, `clip`, `font`, la
  fonction de remappage de `map()` ; l'argument de vitesse de `sfx()` et
  les arguments tempo/vitesse/sustain de `music()` (voir
  [doc/TIC80.md](doc/TIC80.md#sound)). `peek`/`poke` agissent sur une RAM
  émulée, mais écrire dans l'écran, la palette, les tuiles ou les
  registres sonores n'a aucun effet visible ni audible. `trace` ne fait
  rien.
* Les `circ`/`circb`/`rectb` de TIC-80 dessinent un quad GPU par pixel :
  une cartouche qui dessine beaucoup de grands contours à chaque image
  (l'écran titre de witchem_up) tourne en dessous de la pleine vitesse
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
