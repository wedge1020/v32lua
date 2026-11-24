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

Esto escribe tres archivos, uno junto al otro (más los scripts de compilación, [sección 6](#6-scripts-de-compilación-makesh-y-makebat)):

* `obj/game.asm` — el programa, en ensamblador de Vircon32;
* `obj/game.xml` — la definición del cartucho que lee `packrom`;
* `obj/gameOpt.xml` — el mismo cartucho para una compilación con el
  [optimizador](#5-opcional-el-optimizador) (apunta a `gameOpt.vbin`).

Sin `-o`, la salida es `game.asm` (y `game.xml`, `gameOpt.xml`) junto al
código fuente.
Ejecuta `v32lua --help` para ver todas las opciones; las más comunes:

| Opción | Efecto |
|---|---|
| `-o ARCHIVO` | Archivo de ensamblador de salida. |
| `-b` | Construye una **BIOS** de Vircon32 en lugar de un cartucho: necesita `function error_handler()` (la consola la ejecuta ante un error de hardware de la CPU), exactamente una `--#texture` y como máximo un `--#sound`; el XML recibe `<rom type="bios">` y los scripts de compilación usan `v32lua -b` / `assemble -b`. Solo con la API nativa de vircon32. |
| `-g` | Escribe además `ARCHIVO.debug`, que relaciona las líneas de ensamblador con las de Lua (para v32sim). |
| `-w` | Sin advertencias. |
| `-v` | Muestra las etapas del compilador mientras trabaja. |
| `--api pico8\|tic80\|vircon32` | Elige la API; por defecto se detecta a partir del archivo (`.p8`, `.tic`) o del código. |
| `--title "TEXTO"` | Título del cartucho. |
| `--titleopt "TEXTO"` | Título del cartucho optimizado (`gameOpt.xml`); por defecto, el título seguido de ` [optimized]`. |
| `--no-diff-opt-title` | Da al cartucho optimizado el mismo título que al normal. |
| `--no-build-scripts` | No escribe `Make.sh` / `Make.bat` ([sección 6](#6-scripts-de-compilación-makesh-y-makebat)). |
| `--rate 11025\|22050\|44100` | Frecuencia de muestreo del sonido generado a partir de un cartucho de PICO-8 o TIC-80. |
| `--bezel ARCHIVO`, `--no-bezel` | Paneles laterales de PICO-8: tu propio arte, o ninguno. |
| `--fast-circles` | PICO-8/TIC-80: dibuja más rápido los círculos rellenos grandes (bordes ligeramente distintos). |
| `--gc none\|arena` | Gestión del montón ([sección 7](#7-gestión-del-montón---gc)): `none` (por defecto) no tiene recolector (solo reutiliza los bloques que las tablas dejan al crecer); `arena` añade `arena.mark()` / `arena.release(m)`, que liberan de una vez todo lo reservado entre ambos. |
| `--gc-check` | Con `--gc arena`: se detiene cuando un valor creado en una arena abierta se guarda en algo que sobrevive a la arena. Para compilaciones de desarrollo. |
| `--allow-float-as-clearcolor` | Un número Lua dado a `ioports.gpu.clear` o al `cls()` de TIC-80 conserva sus bits float32 como color de borrado, como las versiones antiguas (borrado translúcido = estela de desenfoque). Desactivado por defecto. |
| `--xml-preserve-paths` | Conserva en el XML las rutas de `--#texture`/`--#sound` tal como se escribieron y escribe el XML en la carpeta del proyecto, junto al fuente o en su directorio padre cuando el fuente está en `src/` y la salida en una hermana como `obj/` ([sección 3](#3-el-xml-del-cartucho)). |
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
| `--#titleopt "Texto"` | Título del cartucho optimizado. Sin ella: el título seguido de ` [optimized]`. |
| `--#no-diff-opt-title` | El cartucho optimizado conserva el mismo título que el normal (un `--#titleopt` explícito sigue prevaleciendo). |
| `--#version "1.2"` | Versión del cartucho. |
| `--#texture NOMBRE "ruta/imagen.png"` | Añade una textura. `NOMBRE` pasa a ser una global con su número de textura (0, 1, 2, … en orden). |
| `--#sound NOMBRE "ruta/sonido.wav"` | Añade un sonido. `NOMBRE` contiene su número de sonido (0, 1, 2, …). |
| `--#tilemap NOMBRE "ruta/mapa.csv"` | Incrusta un mapa de mosaicos en el programa (ver [API.es.md](API.es.md#mapa-de-mosaicos-tilemap)). |
| `--#include "archivo.lua"` | Inserta aquí otro archivo fuente. |
| `--#api "pico8"` / `"tic80"` | Elige una API de compatibilidad. |
| `--#p8 "cart.p8"` | PICO-8: usa los sprites, los flags y el mapa de un archivo `.p8`. |
| `--#rate 22050`, `--#bezel off`, `--#fast-circles`, `--#keyboard 2`, `--#mouse 3`, `--#gc arena`, `--#gc-check` | Igual que las opciones de la línea de órdenes, que tienen prioridad. |
| `--#allow-float-as-clearcolor` | Igual que la opción de la línea de órdenes. |

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

`packrom` lee todas las rutas del XML **relativas al propio archivo XML**.
Por eso `v32lua` escribe el XML junto al archivo de `-o` y coloca en él solo
nombres de archivo. Para el ejemplo anterior, `obj/game.xml` es:

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

El XML nombra los archivos convertidos: `.vtex` para cada textura y
`.vsnd` para cada sonido, con el nombre del archivo de la pista y sin su
carpeta. El orden de las entradas es el orden de las pistas, que es lo que
hace de `bg_space` la textura 0, y así sucesivamente. Los archivos `.vbin`,
`.vtex` y `.vsnd` se esperan **junto al XML**, aquí en `obj/` (la sección
siguiente los convierte allí). Como todo es relativo al XML, el proyecto
puede construirse desde cualquier carpeta y no hay que mover ni editar nada
a mano.

**Mismos nombres en carpetas distintas.** Si dos recursos se reducen al
mismo nombre, el primero lo conserva y cada posterior conserva solo las
carpetas necesarias para ser único: `textures/ship.png` seguido de
`textures/extra/ship.png` da `ship.vtex` y `extra/ship.vtex`, el segundo
esperado en `obj/extra/`. Solo dos recursos cuyas rutas completas se reducen
a un mismo nombre (que difieren solo en la extensión, por ejemplo) siguen
provocando un aviso.

**El gemelo del optimizador.** Junto a `obj/game.xml` el compilador escribe
también `obj/gameOpt.xml`, idéntico salvo por
`<binary path="gameOpt.vbin" />` y el título, para la compilación
optimizada de la [sección 5](#5-opcional-el-optimizador). Se escribe se use
o no el optimizador.

**El título del cartucho optimizado.** Para distinguir ambos cartuchos en
una tarjeta de memoria o en un menú, el título del gemelo es el título
normal con ` [optimized]` añadido (`Space Invaders Vircon32 [optimized]`).
Elige el tuyo con `--#titleopt "Texto"` (o `--titleopt "Texto"`, que
prevalece sobre la pista), o mantén ambos títulos idénticos con
`--no-diff-opt-title` (o la pista `--#no-diff-opt-title`). Un `titleopt`
explícito siempre prevalece sobre `no-diff-opt-title`.

**`--xml-preserve-paths`** restaura las rutas tal como se escribieron en las
pistas (`assets/textures/ship.vtex`) y escribe el XML en la *carpeta del
proyecto* en lugar de junto a la salida: el directorio del archivo *fuente*
(el punto de referencia de las propias pistas) o su directorio padre, cuando
el fuente está en una carpeta llamada `src` y la salida en una hermana como
`obj/`. Así, `-o obj/game.asm src/game.lua` da `game.xml` y `gameOpt.xml`
junto a `src/` y `obj/`, el mismo lugar que los
[scripts de compilación](#6-scripts-de-compilación-makesh-y-makebat).
`<binary>` pasa a ser la ruta del `.vbin` relativa al XML (`obj/game.vbin`) y,
como el XML subió un nivel, las rutas de las pistas se rebasan sobre él
(`src/assets/textures/ship.vtex`). Los recursos que genera el propio
compilador (cartuchos PICO-8 y TIC-80, más abajo) quedan junto a la salida,
así que también se nombran relativos al XML (`obj/game_pico8.vtex`). Cuando
el fuente no está en `src/` (o la salida no está en una hermana suya), el XML
va al directorio del propio fuente y las rutas quedan tal como se escribieron
(`../obj/game.vbin`). Úsalo cuando tus recursos ya viven junto al código
fuente y quieres el XML allí.

Con `-b` (una compilación de BIOS) el elemento `<rom>` dice `type="bios"` en
lugar de `type="cartridge"`; el resto del XML es igual. Una BIOS necesita
exactamente una `--#texture` y como máximo un `--#sound`.

## 4. Convertir los recursos, ensamblar y empaquetar

Con las [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases):

```bash
png2vircon assets/textures/background.png -o obj/background.vtex
png2vircon assets/textures/ship.png       -o obj/ship.vtex
wav2vircon assets/sounds/laser.wav        -o obj/laser.vsnd
wav2vircon assets/music/stage1.wav        -o obj/stage1.vsnd

assemble -o obj/game.vbin obj/game.asm
packrom obj/game.xml -o bin/game.v32
```

`bin/game.v32` se ejecuta en el emulador de Vircon32 o en
[v32sim](https://github.com/g7n-org/v32sim). Para `wav2vircon`, los
sonidos deben ser archivos WAV estéreo de 16 bits a 44100 Hz.

Los cartuchos de PICO-8 y TIC-80 no necesitan recursos propios: el
compilador escribe él mismo sus texturas y sonidos, junto a la salida
(`obj/game_pico8.vtex`, `obj/game_sfx00.vsnd`, ...), y los nombra en el XML.

## 5. Opcional: el optimizador

[v32opt](https://github.com/wedge1020/v32opt) reescribe el ensamblador
para que se ejecute más rápido; va entre la compilación y el ensamblado:

```bash
v32opt -L lua -O3 -o obj/gameOpt.asm obj/game.asm
assemble -o obj/gameOpt.vbin obj/gameOpt.asm
packrom obj/gameOpt.xml -o bin/gameOpt.v32
```

`obj/gameOpt.xml` es el gemelo que el compilador ya escribió (sección 3),
así que no hay que editar nada a mano. Los Makefiles de las demos
(`demos/*/Makefile`, `demos/pico8/*/Makefile`, `demos/tic80/*/Makefile`) hacen todo lo anterior, y además construyen el
cartucho optimizado cuando `v32opt` está instalado; un fallo en los pasos
optimizados no impide construir el cartucho normal. Copia uno como punto
de partida para tu propio proyecto.

## 6. Scripts de compilación: `Make.sh` y `Make.bat`

Junto con el XML, `v32lua` escribe los scripts de compilación tradicionales
de Vircon32, `Make.sh` (Linux/macOS) y `Make.bat` (Windows), de modo que un
proyecto se compile con un solo comando aunque no uses un Makefile:

```bash
./Make.sh        # o: Make.bat
```

Repiten todos los pasos de las secciones 1 a 5 para este proyecto, a partir
de la misma información con la que se hace el XML: crean `obj/` y `bin/` (y
cualquier carpeta que necesite un recurso), vuelven a ejecutar `v32lua` con
las opciones que diste, convierten cada `--#texture` / `--#sound` con
`png2vircon` / `wav2vircon` al lugar donde lo espera el XML, `assemble` y
`packrom` hacia `bin/game.v32`. Cada comando va seguido de `|| abort_build`
(`|| goto :failed` en el archivo batch), y el script termina con
`BUILD FAILED` o `BUILD SUCCESSFUL`.

* **Comprueban las herramientas.** Si `v32lua` no está en el `PATH`, el
  script dice que hace falta para compilar el proyecto y se detiene. La
  compilación optimizada (`v32opt`, `assemble`, `packrom` de `gameOpt.xml` a
  `bin/gameOpt.v32`) solo se ejecuta si se encuentra `v32opt`; si no, se
  omite y el script termina con éxito. Un fallo en los pasos optimizados es
  solo un aviso.
* **Dónde van.** Junto al archivo fuente, o en su directorio padre cuando el
  fuente está en una carpeta llamada `src` y la salida en una carpeta
  hermana (`src/game.lua` con `-o obj/game.asm` los pone en la carpeta del
  proyecto, no en `src/`). Todas las rutas son relativas a la carpeta del
  script, que primero se sitúa en ella, así que se puede ejecutar desde
  cualquier lugar.
* **Tus propios scripts están a salvo.** Las primeras líneas dicen
  `Generated by v32lua`. Un `Make.sh` o `Make.bat` sin esa marca nunca se
  sobrescribe (un aviso lo indica). Los generados se reescriben en cada
  compilación, así que copia uno y quita la marca para conservar tus
  cambios. El comando `v32lua` de su interior lleva `--no-build-scripts`,
  de modo que compilar desde el script no lo reescribe.
* **Las opciones se conservan.** `--api`, `--title`, `--titleopt`,
  `--no-diff-opt-title`, `--rate`, `--bezel`, `--no-bezel`, `--fast-circles`,
  `--gc`, `--gc-check`, `--allow-float-as-clearcolor`, `--keyboard`, `--mouse`,
  `--xml-preserve-paths` y `-w` se repiten en la línea de `v32lua` del
  script; `-g` añade además `assemble -g program`, y `-b` (compilación de BIOS)
  también se repite y añade `assemble -b` (con ambos: `assemble -b -g program`).
* **Los mapas de Tiled** (`tiled2vircon`) no se incluyen; usa `--#tilemap`
  o añade esas líneas a tu copia.

`--no-build-scripts` lo desactiva todo (el valor por defecto también puede
cambiarse en `inc/config.h`, `V32LUA_DEFAULT_BUILD_SCRIPTS`). Los Makefiles
de las demos y las suites de pruebas lo pasan, porque compilan a su manera.

## 7. Gestión del montón (`--gc`)

Por defecto (`--gc none`) el montón es un asignador incremental sin
recolector: cada cadena, tabla y closure que creas permanece hasta reiniciar
la consola, así que un juego que crea otras nuevas en cada fotograma acabará
sin memoria (una pantalla roja de «out of memory»). El remedio habitual es
reutilizar tablas. Lo único que el runtime sí libera, en todos los modos de
`--gc`, es la basura que conoce: cuando una tabla supera su parte de array o
de hash, el bloque antiguo pasa a una lista libre (`__mfree`) y las
reservas posteriores de cualquier tipo (cadenas, tablas, closures) lo
reutilizan, primer ajuste por clase de tamaño; `tostring(número)` también
devuelve la cola sin usar de su búfer de texto, así que conserva unas 5
palabras en lugar de 48. Una tabla que crece elemento a elemento hasta 64
cuesta unas 75 palabras del montón en lugar de unas 128. El coste es de 23
palabras de RAM y 2 instrucciones por reserva mientras no se haya liberado
nada. Las tablas, cadenas y closures muertas siguen sin liberarse, y `stat(0)`
en modo PICO-8 sigue informando del tope del montón, de modo que las palabras
reutilizables cuentan como usadas. La alternativa opcional es **`--gc arena`**: marcas un
punto, reservas libremente y liberas de una vez todo lo reservado desde la
marca.

```lua
local m = arena.mark()   -- abre una arena: devuelve el tope actual del montón
-- ... reserva libremente: cadenas, tablas, closures ...
arena.release(m)         -- libera todo lo creado desde la marca m (y cierra
                         -- todas las arenas abiertas después)
arena.used()             -- palabras del montón en uso ahora mismo
```

`arena.*` funciona en todos los modos de API (nativo, PICO-8, TIC-80) y
necesita `--gc arena` (o `--#gc arena`); sin él, usar `arena.*` es un error
de compilación. Las marcas se anidan, hasta 16 abiertas a la vez; liberar una
marca externa cierra también las internas. Liberar algo que no es una marca
abierta (nunca abierta, o ya liberada) o abrir una marca 17 detiene el
programa con una pantalla roja `ARENA ERROR`. Mark, release y used cuestan
unas pocas instrucciones cada una, y el tiempo de un release no depende de
cuánto se reservó. Con `--gc arena`, la reutilización de bloques se
detiene mientras hay una arena abierta (los objetos creados en una arena deben
quedar por encima de su marca) y un bloque liberado dentro de una arena abierta
no se conserva, porque el release lo libera de todos modos; los bloques
liberados fuera de las arenas, o por debajo de la marca abierta más externa,
se reutilizan cuando ya no queda ninguna arena abierta. Sin `--gc arena` no
hay arenas y el montón solo reutiliza los bloques que se quedan pequeños.

```lua
--#gc arena

function _draw()
  local m = arena.mark()
  cls()
  print("score: " .. score .. "  " .. tostring(time()), 4, 4, 7)  -- cadenas temporales
  arena.release(m)            -- todas liberadas de una vez
end
```

En un programa nativo de Vircon32, envuelve igual el cuerpo del bucle de
`main`, alrededor del trabajo hecho antes de `system.wait()`.

Con `--tic80-commit`, las llamadas de dibujo que hace `TIC()` se encolan y
se reproducen cuando termina, y un `print()` encolado sigue apuntando a su
cadena. Si se libera un arena dentro de `TIC()`, esas cadenas se liberan
antes de dibujarse. Libere en su lugar el arena del fotograma *anterior* al
principio del siguiente `TIC()`, cuando la cola ya se ha dibujado:

```lua
--#gc arena
local frame_mark
function TIC()
  if frame_mark then arena.release(frame_mark) end
  frame_mark = arena.mark()    -- un número: se puede guardar en un upvalue
  cls(0)
  print("t=" .. time(), 4, 4)
end
```

**Qué es seguro automáticamente.** Una tabla creada *antes* de la arena que
crece *dentro* de ella (`bullets[#bullets+1] = b` sobre una lista duradera,
una clave nueva en una tabla antigua) tiene su nuevo almacenamiento
*fijado* (pinned): el release conserva el montón hasta ese bloque, de modo
que la tabla antigua nunca apunta a memoria liberada. El precio es que el
resto de la basura de la arena por debajo del bloque fijado sigue reservado
(como mucho el equivalente a una arena por cada fijado, y las tablas crecen
duplicándose, así que los fijados son raros). Los búferes duraderos del
propio runtime (RAM emulada de PICO-8 y TIC-80, búferes `pmem` y de bancos de
TIC-80, un tilemap promovido) se fijan siempre.

**La regla.** Un valor creado dentro de la arena no debe ser referenciado,
tras el release, desde nada que sobreviva a la arena: una global, una tabla
creada antes de la marca, un upvalue (variable local capturada) declarado
antes de la marca, o una local de una función exterior. Esa referencia
apuntaría a memoria liberada (valores basura, cuelgues). Crea las cosas
duraderas antes de la marca o fuera de la arena, copia lo que deba
sobrevivir (por ejemplo un número en lugar de una cadena), o no pongas ese
código en una arena.

**`--gc-check`** (o `--#gc-check`; solo con `--gc arena`, si no se ignora con
un aviso) detecta las infracciones de la regla durante el desarrollo: se
detiene en el propio almacenamiento con `ARENA ERROR: A VALUE MADE IN THE
OPEN ARENA / WAS STORED IN SOMETHING OLDER (--gc-check)`, con la dirección
del valor, la del contenedor (0 = una global) y dónde empieza la arena.
Comprueba los almacenamientos en globales, las escrituras en upvalues, todo
almacenamiento en tablas (`t[k]=v`, `t.k=v`, constructores, `rawset`,
`table.insert`, `add()` de PICO-8, ...; tanto el valor como la clave) y
`setmetatable`. No comprueba las locales de funciones exteriores, y los
números, booleanos, nil, literales de cadena y funciones simples (que no son
closures) siempre pasan. Añade una llamada a cada uno de esos
almacenamientos (alrededor de un 9 % más de ciclos en un cartucho de PICO-8
con muchas tablas), por lo que está pensado para compilaciones de desarrollo.

`--gc marksweep` es un nombre reservado y se rechaza («not implemented
yet»). La línea de órdenes tiene prioridad sobre la pista, y un modo
desconocido es un error. El modo por defecto puede cambiarse al compilar
(`-DV32LUA_DEFAULT_GC=1`, y `V32LUA_DEFAULT_GC_CHECK`, en `inc/config.h`).

**Medir el montón.** v32sim 20261124-dev y posteriores pueden vigilar el
montón mientras corre un cartucho: `v32sim --heap=PROG.asm PROG.v32`, o sin
pantalla `v32orun --heap -a PROG.asm PROG.vbin` (sin `-q`, que oculta las líneas por fotograma). Al final de cada fotograma
se imprime `HEAP F<fotograma> ptr= used= peak=` (`used` es
`HEAP_POINTER - HEAP_START`), con `--gc arena` también
`floor= pin= depth= stack=`, y al salir `HEAP PEAK` y `HEAP END`. Un `used`
que sube fotograma tras fotograma es una fuga: en modo arena, busque un
`pin=` que no deja de subir (una tabla anterior que crece dentro del arena)
o un `depth=` mayor que 0 al final de un fotograma (un arena que nunca se
liberó). El pico indica cuánto montón necesita un nivel o un menú.
