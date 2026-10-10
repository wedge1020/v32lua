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

Cela écrit deux fichiers, l'un à côté de l'autre :

* `obj/game.asm` — le programme, en assembleur Vircon32 ;
* `obj/game.xml` — la définition de cartouche que lit `packrom`.

Sans `-o`, la sortie est `game.asm` (et `game.xml`) à côté du source.
Lancez `v32lua --help` pour voir toutes les options ; les plus courantes :

| Option | Effet |
|---|---|
| `-o FICHIER` | Fichier assembleur de sortie. |
| `-g` | Écrit aussi `FICHIER.debug`, qui associe les lignes d'assembleur aux lignes Lua (pour v32sim). |
| `-w` | Aucun avertissement. |
| `-v` | Affiche les étapes du compilateur pendant qu'il travaille. |
| `--api pico8\|tic80\|vircon32` | Choisit l'API ; par défaut, elle est détectée d'après le fichier (`.p8`, `.tic`) ou le source. |
| `--title "TEXTE"` | Titre de la cartouche. |
| `--rate 11025\|22050\|44100` | Fréquence d'échantillonnage du son produit à partir d'une cartouche PICO-8 ou TIC-80. |
| `--bezel FICHIER`, `--no-bezel` | Panneaux latéraux PICO-8 : vos propres images, ou aucun. |
| `--fast-circles` | PICO-8/TIC-80 : dessine plus vite les grands cercles pleins (bords légèrement différents). |
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
| `--#version "1.2"` | Version de la cartouche. |
| `--#texture NOM "chemin/image.png"` | Ajoute une texture. `NOM` devient une globale contenant son numéro de texture (0, 1, 2, … dans l'ordre). |
| `--#sound NOM "chemin/son.wav"` | Ajoute un son. `NOM` contient son numéro de son (0, 1, 2, …). |
| `--#tilemap NOM "chemin/carte.csv"` | Intègre une carte de tuiles au programme (voir [API.fr.md](API.fr.md#tilemap--tilemap)). |
| `--#include "fichier.lua"` | Insère ici un autre fichier source. |
| `--#api "pico8"` / `"tic80"` | Choisit une API de compatibilité. |
| `--#p8 "cart.p8"` | PICO-8 : utilise les sprites, les drapeaux et la carte d'un fichier `.p8`. |
| `--#rate 22050`, `--#bezel off`, `--#fast-circles`, `--#keyboard 2`, `--#mouse 3` | Comme les options de la ligne de commande, qui ont priorité. |

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

Pour l'exemple ci-dessus, `obj/game.xml` est :

```xml
<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<rom-definition version="1.0">
    <rom type="cartridge" title="Space Invaders Vircon32" version="1.2" />
<binary path="obj/game.vbin" />
<textures>
    <texture path="assets/textures/background.vtex" /> <!-- bg_space -->
    <texture path="assets/textures/ship.vtex" /> <!-- spr_player -->
</textures>
<sounds>
    <sound path="assets/sounds/laser.vsnd" /> <!-- sfx_laser -->
    <sound path="assets/music/stage1.vsnd" /> <!-- bgm_stage1 -->
</sounds>
</rom-definition>
```

Le XML nomme les fichiers convertis : `.vtex` pour chaque texture et
`.vsnd` pour chaque son, dans le même dossier et sous le même nom que le
fichier de l'indication. L'ordre des entrées est celui des indications,
ce qui fait de `bg_space` la texture 0, et ainsi de suite. Les chemins
sont utilisés tels qu'ils sont écrits : écrivez-les donc par rapport au
dossier depuis lequel vous lancez `packrom`.

## 4. Convertir les ressources, assembler et empaqueter

Avec les [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases) :

```bash
png2vircon assets/textures/background.png -o assets/textures/background.vtex
png2vircon assets/textures/ship.png       -o assets/textures/ship.vtex
wav2vircon assets/sounds/laser.wav        -o assets/sounds/laser.vsnd
wav2vircon assets/music/stage1.wav        -o assets/music/stage1.vsnd

assemble -o obj/game.vbin obj/game.asm
packrom obj/game.xml -o bin/game.v32
```

`bin/game.v32` tourne dans l'émulateur Vircon32 ou dans
[v32sim](https://github.com/g7n-org/v32sim). Pour `wav2vircon`, les sons
doivent être des fichiers WAV stéréo 16 bits à 44100 Hz.

Les cartouches PICO-8 et TIC-80 n'ont pas besoin de ressources propres :
le compilateur écrit lui-même leurs textures et leurs sons et les nomme
dans le XML.

## 5. Facultatif : l'optimiseur

[v32opt](https://github.com/wedge1020/v32opt) réécrit l'assembleur pour
qu'il s'exécute plus vite ; il se place entre la compilation et
l'assemblage :

```bash
v32opt -O3 -o obj/gameOpt.asm obj/game.asm
assemble -o obj/gameOpt.vbin obj/gameOpt.asm
sed 's/\.vbin/Opt.vbin/g' obj/game.xml > obj/gameOpt.xml
packrom obj/gameOpt.xml -o bin/gameOpt.v32
```

Les Makefiles des démos (`demos/pico8/*/Makefile`,
`demos/tic80/*/Makefile`) font tout cela, et construisent aussi la
cartouche optimisée quand `v32opt` est installé ; un échec dans les
étapes optimisées n'empêche pas de construire la cartouche normale.
Copiez-en un comme point de départ pour votre propre projet.
