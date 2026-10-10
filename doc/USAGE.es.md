# Usar v32lua: de un archivo .lua a un cartucho

Esta página recorre la construcción de un cartucho: la línea de órdenes,
las pistas `--#` que describen el cartucho, el archivo XML que escribe el
compilador y las herramientas de Vircon32 que terminan el trabajo. El
lenguaje y la API están en el [README](../README.es.md) y en
[API.es.md](API.es.md).

*También en: [English](USAGE.md) | [Français](USAGE.fr.md)*

---

## 1. Compilar

```bash
v32lua -o obj/game.asm game.lua
```

Esto escribe dos archivos, uno junto al otro:

* `obj/game.asm` — el programa, en ensamblador de Vircon32;
* `obj/game.xml` — la definición del cartucho que lee `packrom`.

Sin `-o`, la salida es `game.asm` (y `game.xml`) junto al código fuente.
Ejecuta `v32lua --help` para ver todas las opciones; las más comunes:

| Opción | Efecto |
|---|---|
| `-o ARCHIVO` | Archivo de ensamblador de salida. |
| `-g` | Escribe además `ARCHIVO.debug`, que relaciona las líneas de ensamblador con las de Lua (para v32sim). |
| `-w` | Sin advertencias. |
| `-v` | Muestra las etapas del compilador mientras trabaja. |
| `--api pico8\|tic80\|vircon32` | Elige la API; por defecto se detecta a partir del archivo (`.p8`, `.tic`) o del código. |
| `--title "TEXTO"` | Título del cartucho. |
| `--rate 11025\|22050\|44100` | Frecuencia de muestreo del sonido generado a partir de un cartucho de PICO-8 o TIC-80. |
| `--bezel ARCHIVO`, `--no-bezel` | Paneles laterales de PICO-8: tu propio arte, o ninguno. |
| `--fast-circles` | PICO-8/TIC-80: dibuja más rápido los círculos rellenos grandes (bordes ligeramente distintos). |
| `--keyboard 0-3` | Puerto de mando de un teclado v32kbd (`key()`, `keyp()`, `kbd.*`); 2 por defecto. Necesita un dispositivo v32io (ver abajo). |
| `--mouse 0-3` | Puerto de mando de un ratón v32mouse (`mouse()`, `mouse.*`, `stat(32..34)` de PICO-8); 3 por defecto. Necesita un dispositivo v32io (ver abajo). |
| `--version`, `--help` | Versión, uso. |

> **El teclado y el ratón necesitan un dispositivo v32io.** Vircon32 solo
> tiene mandos. Un programa que usa las funciones de teclado o ratón solo
> recibe entrada cuando se ejecuta con el **adaptador de hardware v32io**
> (un teclado o ratón USB que el ordenador ve como un mando; cualquier
> emulador de Vircon32) o con un **emulador modificado** que lee el
> teclado y el ratón del propio ordenador (la
> [rama `v32io`](https://github.com/wedge1020/ComputerSoftware/tree/v32io)
> de wedge1020/ComputerSoftware, o el emulador original con los parches
> de v32io). Si no, se ejecuta sin ninguna entrada de teclado ni de ratón.
> Ver [API.es.md](API.es.md#teclado-y-ratón-qué-se-necesita-v32io).

## 2. Describir el cartucho con pistas `--#`

Las líneas que empiezan por `--#` son comentarios normales de Lua, que el
compilador lee como ajustes del cartucho. Ponlas al principio del
archivo.

| Pista | Significado |
|---|---|
| `--#title "Texto"` | Título del cartucho. |
| `--#version "1.2"` | Versión del cartucho. |
| `--#texture NOMBRE "ruta/imagen.png"` | Añade una textura. `NOMBRE` pasa a ser una global con su número de textura (0, 1, 2, … en orden). |
| `--#sound NOMBRE "ruta/sonido.wav"` | Añade un sonido. `NOMBRE` contiene su número de sonido (0, 1, 2, …). |
| `--#tilemap NOMBRE "ruta/mapa.csv"` | Incrusta un mapa de mosaicos en el programa (ver [API.es.md](API.es.md#mapa-de-mosaicos-tilemap)). |
| `--#include "archivo.lua"` | Inserta aquí otro archivo fuente. |
| `--#api "pico8"` / `"tic80"` | Elige una API de compatibilidad. |
| `--#p8 "cart.p8"` | PICO-8: usa los sprites, los flags y el mapa de un archivo `.p8`. |
| `--#rate 22050`, `--#bezel off`, `--#fast-circles`, `--#keyboard 2`, `--#mouse 3` | Igual que las opciones de la línea de órdenes, que tienen prioridad. |

```lua
--#title "Space Invaders Vircon32"
--#version "1.2"

--#texture bg_space   "assets/textures/background.png"   -- textura 0
--#texture spr_player "assets/textures/ship.png"         -- textura 1

--#sound sfx_laser  "assets/sounds/laser.wav"             -- sonido 0
--#sound bgm_stage1 "assets/music/stage1.wav"             -- sonido 1

function main()
    ioports.gpu.texture = bg_space
    ioports.gpu.clear()
    music.play(bgm_stage1, 0, true)          -- canal 0, en bucle
    while true do
        if btnp(5) then sfx.play(sfx_laser) end   -- botón A
        system.wait()
    end
end
```

Los nombres de los recursos se asignan antes de que se ejecute `init()` o
`main()`.

## 3. El XML del cartucho

Para el ejemplo anterior, `obj/game.xml` es:

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

El XML nombra los archivos convertidos: `.vtex` para cada textura y
`.vsnd` para cada sonido, en la misma carpeta y con el mismo nombre que el
archivo de la pista. El orden de las entradas es el orden de las pistas,
que es lo que hace de `bg_space` la textura 0, y así sucesivamente. Las
rutas se usan tal como están escritas, así que escríbelas relativas a la
carpeta desde la que ejecutas `packrom`.

## 4. Convertir los recursos, ensamblar y empaquetar

Con las [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases):

```bash
png2vircon assets/textures/background.png -o assets/textures/background.vtex
png2vircon assets/textures/ship.png       -o assets/textures/ship.vtex
wav2vircon assets/sounds/laser.wav        -o assets/sounds/laser.vsnd
wav2vircon assets/music/stage1.wav        -o assets/music/stage1.vsnd

assemble -o obj/game.vbin obj/game.asm
packrom obj/game.xml -o bin/game.v32
```

`bin/game.v32` se ejecuta en el emulador de Vircon32 o en
[v32sim](https://github.com/g7n-org/v32sim). Para `wav2vircon`, los
sonidos deben ser archivos WAV estéreo de 16 bits a 44100 Hz.

Los cartuchos de PICO-8 y TIC-80 no necesitan recursos propios: el
compilador escribe él mismo sus texturas y sonidos y los nombra en el XML.

## 5. Opcional: el optimizador

[v32opt](https://github.com/wedge1020/v32opt) reescribe el ensamblador
para que se ejecute más rápido; va entre la compilación y el ensamblado:

```bash
v32opt -O3 -o obj/gameOpt.asm obj/game.asm
assemble -o obj/gameOpt.vbin obj/gameOpt.asm
sed 's/\.vbin/Opt.vbin/g' obj/game.xml > obj/gameOpt.xml
packrom obj/gameOpt.xml -o bin/gameOpt.v32
```

Los Makefiles de las demos (`demos/pico8/*/Makefile`,
`demos/tic80/*/Makefile`) hacen todo lo anterior, y además construyen el
cartucho optimizado cuando `v32opt` está instalado; un fallo en los pasos
optimizados no impide construir el cartucho normal. Copia uno como punto
de partida para tu propio proyecto.
