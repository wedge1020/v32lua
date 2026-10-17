# Utiliser v32lua : d'un fichier .lua à une cartouche

Cette page parcourt la construction d'une cartouche : la ligne de
commande, les indications `--#` qui décrivent la cartouche, le fichier XML
qu'écrit le compilateur et les outils Vircon32 qui terminent le travail.
Le langage et l'API sont décrits dans le [README](../README.fr.md) et dans
[API.fr.md](API.fr.md).

*Aussi en : [English](USAGE.md) | [Español](USAGE.es.md)*

---

## 1. Compiler

```bash
v32lua -o obj/game.asm game.lua
```

Cela écrit trois fichiers, l'un à côté de l'autre (plus les scripts de compilation, [section 6](#6-scripts-de-compilation--makesh-et-makebat)) :

* `obj/game.asm` — le programme, en assembleur Vircon32 ;
* `obj/game.xml` — la définition de cartouche que lit `packrom` ;
* `obj/gameOpt.xml` — la même cartouche pour une compilation avec
  l'[optimiseur](#5-facultatif--loptimiseur) (elle pointe vers `gameOpt.vbin`).

Sans `-o`, la sortie est `game.asm` (et `game.xml`, `gameOpt.xml`) à côté
du source.
Lancez `v32lua --help` pour voir toutes les options ; les plus courantes :

| Option | Effet |
|---|---|
| `-o FICHIER` | Fichier assembleur de sortie. |
| `-g` | Écrit aussi `FICHIER.debug`, qui associe les lignes d'assembleur aux lignes Lua (pour v32sim). |
| `-w` | Aucun avertissement. |
| `-v` | Affiche les étapes du compilateur pendant qu'il travaille. |
| `--api pico8\|tic80\|vircon32` | Choisit l'API ; par défaut, elle est détectée d'après le fichier (`.p8`, `.tic`) ou le source. |
| `--title "TEXTE"` | Titre de la cartouche. |
| `--titleopt "TEXTE"` | Titre de la cartouche optimisée (`gameOpt.xml`) ; par défaut, le titre suivi de ` [optimized]`. |
| `--no-diff-opt-title` | Donne à la cartouche optimisée le même titre qu'à la normale. |
| `--no-build-scripts` | N'écrit pas `Make.sh` / `Make.bat` ([section 6](#6-scripts-de-compilation--makesh-et-makebat)). |
| `--rate 11025\|22050\|44100` | Fréquence d'échantillonnage du son produit à partir d'une cartouche PICO-8 ou TIC-80. |
| `--bezel FICHIER`, `--no-bezel` | Panneaux latéraux PICO-8 : vos propres images, ou aucun. |
| `--fast-circles` | PICO-8/TIC-80 : dessine plus vite les grands cercles pleins (bords légèrement différents). |
| `--allow-float-as-clearcolor` | Un nombre Lua donné à `ioports.gpu.clear` ou au `cls()` TIC-80 garde ses bits float32 comme couleur d'effacement, comme les anciennes versions (effacement translucide = traînée de flou). Désactivé par défaut. |
| `--xml-preserve-paths` | Conserve dans le XML les chemins de `--#texture`/`--#sound` tels qu'écrits et écrit le XML dans le dossier du projet, à côté de la source ou dans son parent quand la source est dans `src/` et la sortie dans un dossier voisin comme `obj/` ([section 3](#3-le-xml-de-la-cartouche)). |
| `--keyboard 0-3` | Port de manette d'un clavier v32kbd (`key()`, `keyp()`, `kbd.*`) ; 2 par défaut. Demande un périphérique v32io (voir plus bas). |
| `--mouse 0-3` | Port de manette d'une souris v32mouse (`mouse()`, `mouse.*`, `stat(32..34)` de PICO-8) ; 3 par défaut. Demande un périphérique v32io (voir plus bas). |
| `--version`, `--help` | Version, utilisation. |

> **Le clavier et la souris demandent un périphérique v32io.** Vircon32
> n'a que des manettes. Un programme qui utilise les fonctions clavier ou
> souris ne reçoit d'entrées que s'il tourne avec l'**adaptateur
> matériel v32io** (un clavier ou une souris USB que l'ordinateur voit
> comme une manette ; n'importe quel émulateur Vircon32) ou avec un
> **émulateur modifié** qui lit le clavier et la souris de l'ordinateur
> (la [branche `v32io`](https://github.com/wedge1020/ComputerSoftware/tree/v32io)
> de wedge1020/ComputerSoftware, ou l'émulateur d'origine avec les
> correctifs v32io). Sinon, il tourne sans aucune entrée clavier ni
> souris. Voir
> [API.fr.md](API.fr.md#clavier-et-souris--ce-quil-faut-v32io).

## 2. Décrire la cartouche avec les indications `--#`

Les lignes qui commencent par `--#` sont des commentaires Lua ordinaires,
que le compilateur lit comme des réglages de cartouche. Placez-les en
haut du fichier.

| Indication | Signification |
|---|---|
| `--#title "Texte"` | Titre de la cartouche. |
| `--#titleopt "Texte"` | Titre de la cartouche optimisée. Sans elle : le titre suivi de ` [optimized]`. |
| `--#no-diff-opt-title` | La cartouche optimisée garde le même titre que la normale (un `--#titleopt` explicite l'emporte toujours). |
| `--#version "1.2"` | Version de la cartouche. |
| `--#texture NOM "chemin/image.png"` | Ajoute une texture. `NOM` devient une globale contenant son numéro de texture (0, 1, 2, … dans l'ordre). |
| `--#sound NOM "chemin/son.wav"` | Ajoute un son. `NOM` contient son numéro de son (0, 1, 2, …). |
| `--#tilemap NOM "chemin/carte.csv"` | Intègre une carte de tuiles au programme (voir [API.fr.md](API.fr.md#tilemap--tilemap)). |
| `--#include "fichier.lua"` | Insère ici un autre fichier source. |
| `--#api "pico8"` / `"tic80"` | Choisit une API de compatibilité. |
| `--#p8 "cart.p8"` | PICO-8 : utilise les sprites, les drapeaux et la carte d'un fichier `.p8`. |
| `--#rate 22050`, `--#bezel off`, `--#fast-circles`, `--#keyboard 2`, `--#mouse 3` | Comme les options de la ligne de commande, qui ont priorité. |
| `--#allow-float-as-clearcolor` | Comme l'option de la ligne de commande. |

```lua
--#title "Space Invaders Vircon32"
--#version "1.2"

--#texture bg_space   "assets/textures/background.png"   -- texture 0
--#texture spr_player "assets/textures/ship.png"         -- texture 1

--#sound sfx_laser  "assets/sounds/laser.wav"             -- son 0
--#sound bgm_stage1 "assets/music/stage1.wav"             -- son 1

function main()
    ioports.gpu.texture = bg_space
    ioports.gpu.clear()
    music.play(bgm_stage1, 0, true)          -- canal 0, en boucle
    while true do
        if btnp(5) then sfx.play(sfx_laser) end   -- bouton A
        system.wait()
    end
end
```

Les noms des ressources sont définis avant l'exécution de `init()` ou de
`main()`.

## 3. Le XML de la cartouche

`packrom` lit tous les chemins du XML **relativement au fichier XML
lui-même**. `v32lua` écrit donc le XML à côté du fichier de `-o` et n'y
place que des noms de fichiers. Pour l'exemple ci-dessus, `obj/game.xml`
est :

```xml
<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<rom-definition version="1.0">
    <rom type="cartridge" title="Space Invaders Vircon32" version="1.2" />
<binary path="game.vbin" />
<textures>
    <texture path="background.vtex" /> <!-- bg_space -->
    <texture path="ship.vtex" /> <!-- spr_player -->
</textures>
<sounds>
    <sound path="laser.vsnd" /> <!-- sfx_laser -->
    <sound path="stage1.vsnd" /> <!-- bgm_stage1 -->
</sounds>
</rom-definition>
```

Le XML nomme les fichiers convertis : `.vtex` pour chaque texture et
`.vsnd` pour chaque son, avec le nom du fichier de l'indication et sans son
dossier. L'ordre des entrées est celui des indications, ce qui fait de
`bg_space` la texture 0, et ainsi de suite. Les fichiers `.vbin`, `.vtex`
et `.vsnd` sont attendus **à côté du XML**, ici dans `obj/` (la section
suivante les y convertit). Tout étant relatif au XML, le projet peut être
construit depuis n'importe quel dossier, sans rien déplacer ni modifier à
la main.

**Mêmes noms dans des dossiers différents.** Si deux ressources se
réduisent au même nom, la première le garde et chaque suivante ne garde que
les dossiers nécessaires pour être unique : `textures/ship.png` suivi de
`textures/extra/ship.png` donne `ship.vtex` et `extra/ship.vtex`, le second
étant attendu dans `obj/extra/`. Seules deux ressources dont les chemins
complets se réduisent au même nom (ne différant que par l'extension, par
exemple) provoquent encore un avertissement.

**Le jumeau de l'optimiseur.** À côté de `obj/game.xml`, le compilateur
écrit aussi `obj/gameOpt.xml`, identique sauf `<binary path="gameOpt.vbin" />`
et le titre, pour la compilation optimisée de la
[section 5](#5-facultatif--loptimiseur). Il est écrit que vous utilisiez
l'optimiseur ou non.

**Le titre de la cartouche optimisée.** Pour distinguer les deux cartouches
sur une carte mémoire ou dans un menu, le titre du jumeau est le titre
normal suivi de ` [optimized]` (`Space Invaders Vircon32 [optimized]`).
Choisissez le vôtre avec `--#titleopt "Texte"` (ou `--titleopt "Texte"`, qui
l'emporte sur l'indication), ou gardez les deux titres identiques avec
`--no-diff-opt-title` (ou l'indication `--#no-diff-opt-title`). Un
`titleopt` explicite l'emporte toujours sur `no-diff-opt-title`.

**`--xml-preserve-paths`** rétablit les chemins tels qu'écrits dans les
indications (`assets/textures/ship.vtex`) et écrit le XML dans le *dossier du
projet* au lieu de le placer à côté de la sortie : le répertoire du fichier
*source* (le point de référence des indications elles-mêmes) — ou son parent,
quand la source est dans un dossier nommé `src` et la sortie dans un dossier
voisin comme `obj/`. Ainsi, `-o obj/game.asm src/game.lua` donne `game.xml` et
`gameOpt.xml` à côté de `src/` et de `obj/`, au même endroit que les
[scripts de compilation](#6-scripts-de-compilation--makesh-et-makebat).
`<binary>` devient le chemin du `.vbin` relatif au XML (`obj/game.vbin`) et,
le XML ayant monté d'un niveau, les chemins des indications sont rebasés sur
lui (`src/assets/textures/ship.vtex`). Les ressources que le compilateur
génère lui-même (cartouches PICO-8 et TIC-80, ci-dessous) restent à côté de la
sortie ; elles sont donc elles aussi nommées par rapport au XML
(`obj/game_pico8.vtex`). Quand la source n'est pas dans `src/` (ou que la
sortie n'est pas dans un dossier voisin), le XML va dans le répertoire de la
source elle-même et les chemins restent exactement tels qu'écrits
(`../obj/game.vbin`). Utilisez-le quand vos ressources vivent déjà à côté du
code source et que vous voulez le XML là.

## 4. Convertir les ressources, assembler et empaqueter

Avec les [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases) :

```bash
png2vircon assets/textures/background.png -o obj/background.vtex
png2vircon assets/textures/ship.png       -o obj/ship.vtex
wav2vircon assets/sounds/laser.wav        -o obj/laser.vsnd
wav2vircon assets/music/stage1.wav        -o obj/stage1.vsnd

assemble -o obj/game.vbin obj/game.asm
packrom obj/game.xml -o bin/game.v32
```

`bin/game.v32` tourne dans l'émulateur Vircon32 ou dans
[v32sim](https://github.com/g7n-org/v32sim). Pour `wav2vircon`, les sons
doivent être des fichiers WAV stéréo 16 bits à 44100 Hz.

Les cartouches PICO-8 et TIC-80 n'ont pas besoin de ressources propres :
le compilateur écrit lui-même leurs textures et leurs sons, à côté de la
sortie (`obj/game_pico8.vtex`, `obj/game_sfx00.vsnd`, ...), et les nomme
dans le XML.

## 5. Facultatif : l'optimiseur

[v32opt](https://github.com/wedge1020/v32opt) réécrit l'assembleur pour
qu'il s'exécute plus vite ; il se place entre la compilation et
l'assemblage :

```bash
v32opt -O3 -o obj/gameOpt.asm obj/game.asm
assemble -o obj/gameOpt.vbin obj/gameOpt.asm
packrom obj/gameOpt.xml -o bin/gameOpt.v32
```

`obj/gameOpt.xml` est le jumeau que le compilateur a déjà écrit (section 3),
donc rien n'est à modifier à la main. Les Makefiles des démos
(`demos/*/Makefile`, `demos/pico8/*/Makefile`, `demos/tic80/*/Makefile`) font tout cela, et construisent aussi la
cartouche optimisée quand `v32opt` est installé ; un échec dans les
étapes optimisées n'empêche pas de construire la cartouche normale.
Copiez-en un comme point de départ pour votre propre projet.

## 6. Scripts de compilation : `Make.sh` et `Make.bat`

Avec le XML, `v32lua` écrit les scripts de compilation traditionnels de
Vircon32, `Make.sh` (Linux/macOS) et `Make.bat` (Windows), afin qu'un projet
se compile en une seule commande même sans Makefile :

```bash
./Make.sh        # ou : Make.bat
```

Ils reprennent toutes les étapes des sections 1 à 5 pour ce projet, à partir
des mêmes informations que le XML : ils créent `obj/` et `bin/` (et tout
dossier nécessaire à une ressource), relancent `v32lua` avec les options
données, convertissent chaque `--#texture` / `--#sound` avec `png2vircon` /
`wav2vircon` à l'endroit où le XML l'attend, puis `assemble` et `packrom`
vers `bin/game.v32`. Chaque commande est suivie de `|| abort_build`
(`|| goto :failed` dans le fichier batch), et le script se termine par
`BUILD FAILED` ou `BUILD SUCCESSFUL`.

* **Ils vérifient les outils.** Si `v32lua` n'est pas dans le `PATH`, le
  script indique qu'il est nécessaire pour compiler le projet et s'arrête.
  La compilation optimisée (`v32opt`, `assemble`, `packrom` de `gameOpt.xml`
  vers `bin/gameOpt.v32`) ne s'exécute que si `v32opt` est trouvé ; sinon
  elle est ignorée et le script réussit quand même. Un échec dans les
  étapes optimisées n'est qu'un avertissement.
* **Où ils vont.** À côté du fichier source, ou dans son parent quand la
  source est dans un dossier nommé `src` et la sortie dans un dossier voisin
  (`src/game.lua` avec `-o obj/game.asm` les place dans le dossier du
  projet, pas dans `src/`). Tous les chemins sont relatifs au dossier du
  script, dans lequel il se place d'abord, il peut donc être lancé de
  n'importe où.
* **Vos propres scripts sont à l'abri.** Les premières lignes disent
  `Generated by v32lua`. Un `Make.sh` ou `Make.bat` sans cette marque n'est
  jamais écrasé (un avertissement le signale). Les scripts générés sont
  réécrits à chaque compilation : copiez-en un et retirez la marque pour
  garder vos modifications. La commande `v32lua` qu'ils contiennent passe
  `--no-build-scripts`, donc compiler depuis le script ne le réécrit pas.
* **Les options sont reprises.** `--api`, `--title`, `--titleopt`,
  `--no-diff-opt-title`, `--rate`, `--bezel`, `--no-bezel`, `--fast-circles`,
  `--allow-float-as-clearcolor`, `--keyboard`, `--mouse`,
  `--xml-preserve-paths` et `-w` sont répétées dans la ligne `v32lua` du
  script, et `-g` ajoute aussi `assemble -g program`.
* **Les cartes Tiled** (`tiled2vircon`) ne sont pas couvertes ; utilisez
  `--#tilemap` ou ajoutez ces lignes à votre copie.

`--no-build-scripts` désactive tout cela (la valeur par défaut peut aussi
être changée dans `inc/config.h`, `V32LUA_DEFAULT_BUILD_SCRIPTS`). Les
Makefiles des démos et les suites de tests l'utilisent, car ils compilent à
leur manière.
