# v32lua: Compilador de Lua para Vircon32

[Versión en inglés / in English](README.md) | [Versión en francés / en français](README.fr.md)

**Arquitectura Objetivo:** Consola de Fantasía Vircon32 (32-bit)

**Lenguaje de Implementación:** C (Flex/Bison + Emisor Semántico Personalizado)

**Repositorio:** [github.com/wedge1020/v32lua](https://github.com/wedge1020/v32lua)

**Referencia de la API:** [doc/API.es.md](doc/API.es.md) — la API nativa completa
de Vircon32 (sonido, gráficos, entrada, mapas de mosaicos, tarjeta de
memoria y puertos de E/S en bruto). Empieza por su
[Referencia rápida](doc/API.es.md#quick-reference): cada intrínseco y cada
puerto `ioports.*` en un solo lugar.

**Construir un cartucho:** [doc/USAGE.es.md](doc/USAGE.es.md) — la línea de
comandos, las pistas `--#`, el XML generado y las herramientas de Vircon32
que completan el trabajo.

`v32lua` es un compilador de Lua escrito en C que tiene como objetivo la
consola de fantasía **Vircon32**. En lugar de incorporar un intérprete de
bytecode pesado, `v32lua` analiza el código fuente de Lua y lo compila
directamente a ensamblador nativo de Vircon32, además de producir la
definición XML del cartucho que necesita la cadena de herramientas de la
consola para empaquetar una ROM.

Aunque todavía no está completo, uno de los objetivos del desarrollo es
convertir a `v32lua` en un sustituto (de ninguna manera un reemplazo) del
Compilador de C de Vircon32 dentro de su cadena de desarrollo. Básicamente,
elige tu lenguaje preferido — C o Lua — y, una vez compilado a ensamblador,
continúas con la construcción sin importar el lenguaje de implementación.
Como resultado, se ha hecho un esfuerzo por imitar varios comportamientos
del Compilador de C de Vircon32 para que la sustitución del compilador sea
más transparente.

Diseñado desde cero teniendo en cuenta las restricciones de una consola de
fantasía retro, `v32lua` cuenta con intrínsecos de "hardware" de bajo nivel
y costo cero, [NaN-boxing](doc/NaN_boxing.md) personalizado y — más allá de
la API nativa de Vircon32 — dos capas de compatibilidad de API para que los
cartuchos escritos para **TIC-80** y **PICO-8** puedan compilarse y
ejecutarse en el entorno de Vircon32 con poca o ninguna modificación del
código fuente.

```
+------------------+     +-------------------+     +------------------+
| Fuente (.lua)    | --> | Lexer y Parser    | --> | Construcción AST |
+------------------+     | (Flex / Bison)    |     +------------------+
                         +-------------------+              |
                                                            v
+------------------+     +-------------------+     +------------------+
| Config. Cartucho | <-- | Emisor ensamblador| <-- | Emisor Semántico |
| (.xml)           |     | Vircon32 (.asm)   |     |                  |
+------------------+     +-------------------+     +------------------+
```

---

## Tabla de Contenidos

- [Primeros Pasos](#primeros-pasos)
- [Capas de Compatibilidad de API](#capas-de-compatibilidad-de-api)
  - [Teclado y ratón (v32io)](#teclado-y-ratón-v32io)
- [Pistas de Recursos del Cartucho (`--#...`)](#pistas-de-recursos-del-cartucho)
- [Proceso de Compilación](#proceso-de-compilación)
- [Características Clave del Lenguaje y del Compilador](#características-clave-del-lenguaje-y-del-compilador)
- [Características de Lua Soportadas](#características-de-lua-soportadas)
- [E/S de Hardware e Intrínsecos del Compilador](#es-de-hardware-e-intrínsecos-del-compilador)
- [Ensamblador en Línea (`__asm__` y `__rawasm__`)](#ensamblador-en-línea-__asm__-y-__rawasm__)
- [Mapa de Memoria de Referencia](#mapa-de-memoria-de-referencia)
- [Peculiaridades, Supuestos y Limitaciones Conocidas del Compilador](#peculiaridades-y-supuestos-del-compilador)
- [Optimización del Compilador](#optimización-del-compilador)
- [Hoja de Ruta / Aún No Implementado](#hoja-de-ruta--aún-no-implementado)
- [Uso de IA](#uso-de-ia)

---

## Primeros Pasos

**Requisitos**

* Una cadena de herramientas de C (`gcc`/`clang` + `make`), o CMake 3.13+
  como compilación alternativa (ver [Compilar con CMake](#compilar-con-cmake))
* Si se modifica el lexer/parser, se necesitan las herramientas `flex` y
  `bison` para regenerar las rutinas C del lexer/parser. Las rutinas C ya
  generadas por `flex` y `bison` están incluidas en el repositorio para
  simplificar la compilación, de modo que en la mayoría de los casos no hace
  falta tener `flex`/`bison`
* La cadena de herramientas [Vircon32 DevTools](https://github.com/vircon32/ComputerSoftware/releases) (ensamblador y `packrom`) si
  pretendes llegar completamente desde `.lua` hasta un cartucho `.v32`
  ejecutable, más [v32sim](https://github.com/g7n-org/v32sim) si quieres
  ejecutar o depurar el resultado (también se usa para las pruebas
  unitarias).

**Compilando el Compilador**

El repositorio incluye un Makefile en la raíz que gestiona la compilación
del binario del compilador, la ejecución de la suite de pruebas y el
mantenimiento general del proyecto. Para compilar el binario principal del
compilador desde el código fuente, ejecuta el objetivo por defecto desde la
raíz del repositorio:

```bash
make
```

Esto compila los distintos archivos fuente y produce el binario `v32lua`
(bajo `bin/`), que convierte un archivo fuente `.lua` en un archivo `.asm`
de Vircon32 más un `.xml` de cartucho que lo acompaña. A partir de ahí,
ensamblar y empaquetar sigue los mismos pasos que cualquier otro proyecto
de Vircon32 (ensamblar → `packrom` → ejecutar bajo
[v32sim](https://github.com/g7n-org/v32sim) o en el emulador oficial).

*Tabla de Referencia de Objetivos del Makefile*

| Objetivo | Descripción |
| --- | --- |
| **`all`** | **Objetivo por defecto.** Compila el compilador (`bin/v32lua`) dentro de `src/`. |
| **`clean`** | Elimina los artefactos de compilación de `src/` y los archivos generados en `testing/` y `demos/`. |
| **`install`** | Copia `bin/v32lua` a `~/bin/bin.$(ARCH)/` si existe, si no a `~/bin/`. |
| **`sysinstall`** | Instalación en el sistema: `bin/v32lua` en `/usr/local/bin/`, la página de manual en `/usr/local/share/man/man1/` y la biblioteca de `--#include` (`lib/*.lua`) en `/usr/local/Vircon32/v32tools/include/v32lua/` (normalmente requiere `sudo`; ver [Instalación](#instalacion)). |
| **`sysuninstall`** | Elimina lo que instaló `sysinstall`. |
| **`tests`** | Ejecuta las pruebas unitarias de `testing/`: cada programa se compila, se ensambla, se empaqueta y se ejecuta en [v32sim](https://github.com/g7n-org/v32sim), y sus resultados se comparan con el bloque `EXPECTED OUTPUT` del archivo (requiere las DevTools, v32sim y `v32lua` en tu `PATH`). |
| **`asmcheck`** | Compila las pruebas y ensambla cada resultado (`.vbin`), comprobando el ensamblador generado. |
| **`v32check`** | Como `asmcheck`, y además empaqueta cada prueba en un cartucho `.v32`. |
| **`demos`** | Compila todas las demos bajo `demos/` (ver [Compilar las demos](#building-the-demos)). |
| **`version`** | Muestra la versión de `inc/v32lua.h` y la estampa en `man/v32lua.1` y `doc/DEBUGGING.md` (ejecútalo antes de una publicación). |
| **`monofiles`**, **`context`**, **`put`** | Reúnen las fuentes en `put/` como archivos de texto únicos, para pegarlos en una conversación. |
| **`archive`** | Limpia y luego comprime el proyecto en `v32lua-project.zip`. |

La cadena de versión está en un solo lugar, `#define VERSION` en
`inc/v32lua.h`; `v32lua --version` la muestra y `make version` la copia en
la página de manual y en la guía de depuración.

<a id="compilar-con-cmake"></a>
**Compilar con CMake**

Para quien lo prefiera, `CMakeLists.txt` compila el mismo compilador a
partir de las mismas fuentes (el Makefile sigue siendo la compilación
principal, y `make tests` sigue siendo la ejecución completa de las
pruebas en v32sim):

```sh
cmake -S . -B build              # Release por defecto
cmake --build build              # build/v32lua
ctest --test-dir build           # compila cada programa de prueba
sudo cmake --install build       # ver "Instalación" más abajo
```

`ctest` comprueba que cada programa de las categorías de `testing/` que
ejecuta `make tests` compila, y que los de `testing/fail/` se rechazan;
ejecutarlos es tarea de `make tests`. Se usan flex y bison si se
encuentran (`-DV32LUA_REGENERATE_PARSER=OFF` los omite); si no, se
compilan tal cual `src/parser.c`, `inc/parser.h` y `src/lexer.c`, ya
generados, así que una compilación normal solo necesita un compilador de
C y CMake 3.13+. En **Windows**, compila con MinGW-w64 de 64 bits (por
ejemplo desde una terminal MINGW64 de MSYS2, `cmake -S . -B build -G
"MSYS Makefiles"`); MSVC no está soportado. `cpack --config
build/CPackConfig.cmake` genera un `.tar.gz` (más `.deb` / `.rpm` donde
haya `dpkg-deb` / `rpmbuild`), o un `.zip` en Windows.

<a id="instalacion"></a>
**Instalación**

Una instalación en el sistema coloca todo donde una instalación de
Vircon32 lo espera. El binario y la página de manual van donde van los
comandos y las páginas de manual; la biblioteca de `--#include` y los
documentos van en `v32tools/`, la carpeta que comparten las herramientas
de la comunidad (con [v32opt](https://github.com/wedge1020/v32opt) y
v32c++), junto a las `DevTools/` oficiales:

| | Linux / macOS | Windows (CMake) |
| --- | --- | --- |
| compilador | `/usr/local/bin/v32lua` | `C:\Program Files\Vircon32\v32tools\v32lua.exe` |
| página de manual | `/usr/local/share/man/man1/v32lua.1` | `...\v32tools\docs\v32lua\v32lua.1` |
| biblioteca de `--#include` (`lib/*.lua`) | `/usr/local/Vircon32/v32tools/include/v32lua` | `...\v32tools\include\v32lua` |
| documentación | `/usr/local/Vircon32/v32tools/docs/v32lua` (CMake) | `...\v32tools\docs\v32lua` |

Cualquiera de las dos compilaciones lo hace:

```sh
sudo make sysinstall                          # Linux / macOS
sudo make sysuninstall

sudo cmake --install build                    # cualquier sistema (prefijo: /usr/local,
sudo cmake --build build --target uninstall   #   o C:/Program Files/Vircon32)
```

El directorio de la biblioteca queda integrado en el compilador, así que
tras instalar, `--#include "string.lua"` funciona desde cualquier
directorio. Con CMake, elige otra ubicación al configurar (`cmake -S . -B
build -DCMAKE_INSTALL_PREFIX=/opt/vircon32`) y el compilador buscará
allí; `-DV32LUA_INSTALL_INCLUDEDIR=...` (y `BINDIR`, `MANDIR`, `DOCDIR`)
mueven una sola parte. La desinstalación elimina solo los archivos de
v32lua, y después `v32tools/` (y en Linux / macOS `Vircon32/`) solo si no
queda nada más dentro. En Windows, añade `C:\Program
Files\Vircon32\v32tools` a tu `PATH`, como para las DevTools.

`make install`, en cambio, copia solo el binario a `~/bin`. Los valores
por defecto de la compilación con el Makefile (el directorio de la
biblioteca, las frecuencias de muestreo y los puertos de mando por
defecto, ...) están en [`inc/config.h`](inc/config.h); cambia uno ahí y
recompila, o sobrescríbelo al compilar:

```sh
make CFLAGS="-Wall -Wextra -g -I ../inc -DYYDEBUG=1 -DV32LUA_INCLUDE_PATH='\"/opt/v32tools/include/v32lua\"'"
```

<a id="building-the-demos"></a>
**Compilar las demos**

Cada demo bajo `demos/pico8/` y `demos/tic80/` tiene un Makefile que
compila, ensambla y empaqueta el cartucho en `bin/<demo>.v32`. Si el
optimizador de ensamblador [v32opt](https://github.com/wedge1020/v32opt)
está en tu `PATH`, la misma ejecución también produce un cartucho
optimizado, `bin/<demo>Opt.v32` (a partir de `obj/<demo>Opt.asm` y
`<demo>Opt.xml`). Los pasos optimizados pueden fallar: si `v32opt` o el
ensamblador rechazan el código optimizado, `make` muestra el error y
continúa, y el cartucho normal se genera de todos modos. Sin `v32opt`, la
compilación optimizada se omite con un aviso; desactívala a la fuerza con
`make HAVE_OPTIMIZER=`, o cambia las opciones con
`make OPTIMIZER="v32opt -O2"`.

**Tu Primer Cartucho**

```lua
--#title "v32lua Tech Demo"
--#version "1.0"
--#texture tex_logo "logo.png"

x_pos = 160.0
y_pos = 120.0
speed = 2.5

function init()
    -- Establece el color de fondo usando mapeos de puertos GPU de costo cero
    ioports.gpu.bgcolor = 0xFF003366
    ioports.gpu.texture = tex_logo -- establece la textura
    ioports.gpu.region  = 0 -- establece la región

    -- define la región
    ioports.gpu.minX    = 0
    ioports.gpu.minY    = 0
    ioports.gpu.maxX    = 100
    ioports.gpu.maxY    = 50
    ioports.gpu.hotX    = 0
    ioports.gpu.hotY    = 0
end

function game_loop()
    ioports.gpu.clear()             -- borra la pantalla con bgcolor

    -- Actualiza el estado usando matemática de punto flotante pura
    if ioports.inp.left > 0 then    -- > 0: cuadros que lleva pulsado; < 0: liberado
        x_pos = x_pos - speed
    elseif ioports.inp.right > 0 then
        x_pos = x_pos + speed
    end

    -- Dibujo directo por hardware
    ioports.gpu.x = x_pos
    ioports.gpu.y = y_pos
    ioports.gpu.draw()

    -- Concatenación de cadenas integrada; print() recibe x, y primero
    local frame = system.frames
    if frame > 1000 then
        print(10, 10, "Demo Running: Frame " .. frame)
    end
end
```

Compílalo con:

```bash
$ v32lua -o program.asm program.lua
```

`v32lua` emite `program.asm` y `program.xml` a su lado; entrega ambos al
ensamblador de Vircon32 y a `packrom` para producir un cartucho ejecutable.

**Uso desde la Línea de Comandos**

```bash
$ v32lua [options] file
```

Opciones disponibles:

* `-o <archivo>`: Especifica el nombre del archivo de salida del
  ensamblador. Por defecto usa el nombre del archivo de entrada con su
  extensión reemplazada por `.asm`.
* `-g`: Genera un archivo `.debug` complementario que mapea los desplazamientos
  de línea del ensamblador de vuelta a las líneas originales del código fuente
  Lua y a los puntos de entrada de las funciones.
* `-v`, `--verbose`: Informa el progreso a través de las etapas internas del
  pipeline del compilador mientras se ejecuta.
* `-d`, `--debug`: Muestra información interna/operativa de depuración
  adicional.
* `-w`: Suprime todas las advertencias del compilador.
* `--version`: Muestra la versión del compilador y la información del autor.
* `--help`, `-h`: Muestra las instrucciones de uso de la línea de comandos.

Opciones del cartucho — cada una anula la pista `--#` correspondiente del
código fuente, así que un cartucho de PICO-8 o TIC-80 compila sin editarlo
(`--opt=valor` también funciona):

* `--api pico8|tic80|vircon32`: Selecciona la capa de API. Sin ella, la API
  se detecta: un `.p8` es PICO-8, un `.tic` es TIC-80, y un `.lua` usa su
  propia pista `--#api`/`--#p8` — o, si no tiene ninguna, sus puntos de
  entrada (`TIC()` → tic80; `_draw()`/`_update()`/`_update60()` → pico8;
  si no, nativa).
* `--title "texto"`: Título del cartucho, usado tal cual. Sin ella: la pista
  `--#title`, si no el título propio del cartucho (los metadatos
  `-- title:` de TIC-80, la primera línea de comentario de PICO-8) o el
  nombre del archivo — con el prefijo `[PICO8] ` o `[TIC80] ` en esos modos
  de API.
* `--rate 11025|22050|44100`: Frecuencia de muestreo del sonido sintetizado
  a partir de un cartucho de PICO-8 o TIC-80 (por defecto 22050; ver
  [doc/PICO8.md](doc/PICO8.md#sound) y [doc/TIC80.md](doc/TIC80.md#sound)).
  `--p8rate` es el nombre antiguo.
* `--bezel arte.png`: paneles laterales de PICO-8 a partir de tu propio arte
  en lugar de los integrados (ver
  [doc/PICO8.md](doc/PICO8.md#side-panels)); `--no-bezel`: márgenes negros.
* `--fast-circles`: los círculos rellenos de TIC-80/PICO-8 de radio mayor
  que 31 se dibujan como un disco escalado.

Los valores por defecto de estas opciones (frecuencias de muestreo por API,
paneles laterales activados/desactivados y un archivo de arte de panel por
defecto, círculos rápidos, advertencias) se definen en `inc/config.h`:
cámbialos allí y recompila, o pásalos al compilar
(`make CFLAGS="... -DV32LUA_DEFAULT_PICO8_RATE=11025"`). Precedencia: la
opción de línea de comandos, luego la pista `--#` del código fuente, luego
`config.h`.

```bash
$ v32lua celeste.p8 --title "celeste" --rate 11025     # API detectada a partir del .p8
$ v32lua game.tic                                        # cartucho binario de TIC-80
```

Archivos de entrada: `.lua`, `.p8` (cartucho de PICO-8), `.tic` (cartucho
de TIC-80, solo cartuchos en Lua; se leen el código y los tiles, sprites,
mapa, banderas, paleta, formas de onda y SFX del banco 0 — los mismos datos
que lleva una exportación `.lua` de TIC-80).

---

## Capas de Compatibilidad de API

`v32lua` admite tres superficies de API distintas, seleccionadas con la
pista de cartucho `--#api` (la API nativa de Vircon32 es la opción por
defecto cuando no hay ninguna pista `--#api` presente):

```lua
--#api "tic80"   -- opta por la superficie de API compatible con TIC-80
--#api "pico8"   -- opta por la superficie de API compatible con PICO-8
```

* **API nativa de Vircon32** (por defecto) — acceso directo y de costo cero
  a los IOPorts propios de la consola: `ioports.gpu.*`, `ioports.spu.*`,
  `ioports.inp.*`, `music.*`/`sfx.*`, `system.*`, `rect()`/`rectfill()`,
  la API nativa `tilemap.*`, un teclado completo a través de un
  dispositivo v32kbd (`key()`/`keyp()`, texto escrito con `kbd.read()`) y
  un ratón a través de un dispositivo v32mouse (`mouse()`, `mouse.*`).
  Documentada por completo en [doc/API.es.md](doc/API.es.md).
* **Capa de compatibilidad TIC-80** (`--#api "tic80"`) — llamadas con la
  forma de TIC-80 (`spr()`, `btn()`/`btnp()`, `map()`/`mset()`/`mget()`,
  funciones de sonido/música, y las secciones de recursos al estilo de
  consola de fantasía) compiladas hacia instrucciones nativas de Vircon32,
  incluyendo el escalado de coordenadas necesario para mapear la pantalla
  lógica de 240×136 de TIC-80 a la resolución física de Vircon32.
  `sfx()`/`music()` reproducen los `WAVES`/`SFX`/`PATTERNS`/`TRACKS` del
  propio cartucho, sintetizados al compilar por un port del motor de sonido
  de TIC-80 (ver [doc/TIC80.md](doc/TIC80.md)); `spr()` rota; Start pausa
  el juego (como en la capa PICO-8). `print()` respeta su color y devuelve
  el ancho del texto. `key()`/`keyp()` leen un teclado real a través de un
  dispositivo v32kbd (códigos de tecla de TIC-80, con autorrepetición), y
  `mouse()` un ratón real a través de un dispositivo v32mouse.
  `map()` acepta todos los argumentos opcionales de TIC-80, incluido `scale`
  (no la función de reasignación); `fget()` devuelve un booleano y `fset()`
  recibe uno. `peek`/`peek1`/`peek2`/`peek4`, `poke`/`poke1`/`poke2`/`poke4`,
  `memcpy` y `memset` trabajan sobre una RAM de TIC-80 emulada de 96 KB,
  creada en el primer uso con la paleta, los tiles, los sprites y el mapa
  del cartucho; las zonas del mapa (0x08000), del mando (0x0FF80) y de las
  banderas de sprites (0x14404) son vistas en vivo de `mget`/`mset`, de los
  botones y de `fget`/`fset`. Las demás escrituras se guardan pero no
  cambian la pantalla ni el sonido. `pmem` tiene las 256 ranuras de 32 bits
  de TIC-80 en la tarjeta de memoria. En ambas capas de consola de fantasía,
  los círculos son un único dibujo de GPU cada uno hasta radio 31
  (prerrenderizados al compilar, idénticos píxel a píxel a los de las
  consolas). Una función que el propio programa define
  (`function pal(...)`) reemplaza a la integrada del mismo nombre, como en
  Lua.
* **Capa de compatibilidad PICO-8** (`--#api "pico8"`) — el equivalente con
  la forma de PICO-8: `spr`/`map`/`mget`/`mset`/`fget`/`fset`, `cls`,
  `rectfill`/`rect`/`circfill`/`circ`/`line`/`pset`/`print` (con color),
  `camera`/`color`, `btn`/`btnp` (autorrepetición de PICO-8), `add`/`del`/
  `count`/`foreach`/`for v in all(t)` (seguro ante borrados), matemáticas
  de PICO-8 (`flr`, `rnd`, `mid`, `sin`/`cos` en vueltas, ...), `sspr`,
  `split`, `tostr`/`tonum`, `_ENV[nombre]`, los atajos de sintaxis de
  PICO-8 (`?`, `\`, `f"cad"`, glifos de botones, ...), `sfx`/`music` que
  reproducen el `__sfx__`/`__music__` del propio cartucho (sintetizado al
  compilar), `time`/`t`, `peek`/`poke` (8/16/32 bits, y los operadores
  `@ % $`), `memcpy`/`memset`/`reload`/`sget`/`sset` sobre una RAM emulada
  de 64 KB con la disposición de PICO-8 (mapa, banderas, lápiz, cámara y
  botones en vivo; las escrituras en pantalla se dibujan),
  `cartdata`/`dget`/`dset` guardados en la tarjeta de memoria, el ratón
  del devkit (`stat(32..34)`, más el `mouse()` de TIC-80) a través de un
  dispositivo v32mouse, y
  `_init`/`_update` (30 fps)/`_update60`/`_draw`. La pantalla de 128×128 se
  escala 2,75× y se centra; lo que se dibuja fuera de ella queda
  enmascarado. **Un cartucho `.p8` compila directamente**
  (`v32lua juego.p8`): su sección `__lua__` es el programa y sus secciones
  `__gfx__`/`__gff__`/`__map__` se convierten en la hoja de sprites, las
  banderas de sprites y el mapa. Un `.lua` simple puede tomar esos recursos
  de un cartucho con `--#p8 "juego.p8"`. Ver [doc/PICO8.md](doc/PICO8.md).

Solo una superficie de API está activa por cartucho; seleccionar `tic80` o
`pico8` reemplaza la superficie de llamadas nativa en lugar de añadirse a
ella.


### Teclado y ratón (v32io)

> **⚠ La entrada de teclado y ratón necesita hardware adicional o un
> emulador modificado.** La consola Vircon32 no tiene teclado ni ratón:
> solo cuatro mandos. Las funciones de teclado y ratón de v32lua
> (`key()`/`keyp()`/`kbd.*` y `mouse()`/`mouse.*` nativas, `key()`/`keyp()`/
> `mouse()` de TIC-80, `stat(32..34)` de PICO-8) leen un teclado o un ratón
> **disfrazado de mando**, y funcionan **solo** con una de estas opciones:
>
> * el **adaptador de hardware v32io** — una placa Waveshare RP2350-USB-A
>   (sin la resistencia R13) con el firmware v32io: un teclado o ratón USB
>   conectado a ella aparece en el ordenador como un mando (`v32io:kbd` /
>   `v32io:mouse`), así que funciona con **cualquier** emulador de Vircon32,
>   incluido el original, una vez configurado su perfil de joystick;
> * un **emulador de Vircon32 modificado**, que lee el teclado y el ratón
>   del propio ordenador como dispositivos v32io (sin hardware): el fork
>   [wedge1020/ComputerSoftware](https://github.com/wedge1020/ComputerSoftware),
>   [rama `v32io`](https://github.com/wedge1020/ComputerSoftware/tree/v32io)
>   (con `v32kbd` y `v32mouse`), o las fuentes del DesktopEmulator original
>   con los parches `emulator/v32kbd.patch` y `emulator/v32mouse.patch` del
>   proyecto v32io aplicados.
>
> **Sin una de ellas, el acceso al teclado y al ratón no es posible:** los
> programas compilan y se ejecutan, pero ninguna tecla está pulsada nunca
> y el ratón no se mueve. Los programas que los necesiten deberían
> indicarlo y, si es posible, ofrecer también controles con mando.

El teclado se lee por defecto del puerto de mando 2 (el tercero) y el
ratón del puerto 3 (el cuarto), lo que deja los puertos 0 y 1 para mandos
normales (`--keyboard N`, `--mouse N`, `--#keyboard N`, `--#mouse N`, o
`kbd.port(n)` / `mouse.port(n)` en tiempo de ejecución). Los puertos se
numeran desde 0; los menús del emulador llaman al puerto 2 "Gamepad 3" y
al puerto 3 "Gamepad 4". Los protocolos,
la lectura en cada cuadro que añade el compilador y la configuración se
describen en [doc/API.es.md](doc/API.es.md#teclado-y-ratón-qué-se-necesita-v32io).

---

## Pistas de Recursos del Cartucho

`v32lua` te permite incrustar metadatos de cartucho de Vircon32 directamente
en tu código fuente Lua usando comentarios de línea especiales `--#`. El
compilador analiza estas pistas para autogenerar la definición ROM `.xml`
del proyecto y asignar IDs de recursos de hardware secuenciales.

Pistas soportadas:

| Pista | Propósito |
| --- | --- |
| `--#version "X.Y"` | Establece el campo de versión del cartucho en el XML. |
| `--#title "TÍTULO"` | Establece el título del cartucho. |
| `--#api "tic80"` / `--#api "pico8"` | Selecciona una capa de compatibilidad de API (ver arriba). |
| `--#p8 "cart.p8"` | PICO-8: toma la hoja de sprites, las banderas de sprites y el mapa de un cartucho `.p8` (implica `--#api pico8`). |
| `--#rate 11025` \| `22050` \| `44100` | Frecuencia de muestreo del sonido sintetizado a partir de un cartucho de PICO-8 o TIC-80 (por defecto 22050; `--#p8rate` es el nombre antiguo; ver [doc/PICO8.md](doc/PICO8.md#sound)). |
| `--#bezel off` \| `on` \| `"arte.png"` | PICO-8: los paneles laterales junto a la pantalla de 128×128 — ninguno, el arte integrado o el tuyo propio (ver [doc/PICO8.md](doc/PICO8.md#side-panels)). |
| `--#fast-circles` | TIC-80/PICO-8: los círculos rellenos de radio mayor que 31 se dibujan como un único disco escalado (más rápido, los bordes difieren ligeramente). |
| `--#keyboard 0`–`3` | Puerto de mando de un teclado v32kbd (requiere un adaptador v32io o el emulador modificado, ver [Teclado y ratón](#teclado-y-ratón-v32io)), para `key()`/`keyp()`/`kbd.*` (2 por defecto; ver [doc/API.es.md](doc/API.es.md#teclado-key--keyp--kbd)). |
| `--#mouse 0`–`3` | Puerto de mando de un ratón v32mouse (requiere un adaptador v32io o el emulador modificado, ver [Teclado y ratón](#teclado-y-ratón-v32io)), para `mouse()`/`mouse.*` y `stat(32..34)` de PICO-8 (3 por defecto; ver [doc/API.es.md](doc/API.es.md#ratón-mouse--mouse)). |
| `--#texture NOMBRE "ruta/imagen.png"` | Registra un recurso de textura y lo vincula a una constante `NOMBRE` en tiempo de compilación. El XML nombra el archivo `.vtex` (`imagen.vtex`) que `png2vircon` genera a partir del PNG. |
| `--#sound NOMBRE "ruta/sonido.wav"` | Registra un recurso de sonido y lo vincula a una constante `NOMBRE` en tiempo de compilación. El XML nombra el archivo `.vsnd` que genera `wav2vircon`. |
| `--#tilemap NOMBRE "ruta/mapa.csv"` | Registra un mapa de mosaicos desde un archivo CSV, incrustado directamente en la imagen ROM (ver [doc/API.es.md](doc/API.es.md#mapa-de-mosaicos-tilemap)). |
| `--#include "archivo.lua"` | Empalma textualmente otro archivo Lua en este punto, antes de que comience el análisis (ver abajo). |

```lua
--#version "1.1"
--#title "Space Grinder: Tech Demo"

-- Registra texturas (vincula automáticamente 'bg_space' al ID 0, 'spr_ship' al ID 1)
--#texture bg_space "assets/background.png"
--#texture spr_ship "assets/player.png"

function init()
    -- ¡Las variables declaradas en las pistas están disponibles globalmente en Lua en tiempo de ejecución!
    ioports.gpu.texture = bg_space
end
```

Al compilar, `v32lua` genera tanto el ensamblador `.asm` compilado como un
archivo completo de definición de cartucho XML de Vircon32 que enlaza los
recursos `.vtex` y `.vsnd`. Con esto, y el procesamiento adecuado de
cualquier dato PNG y WAV, puedes proceder al paso de `packrom`. Los IDs de
recursos se asignan en el orden del código fuente y se garantiza que
coincidan con su posición en el XML generado.

**Proyectos Multi-Archivo (`--#include`)**

Debido a que los cartuchos de Vircon32 son una ROM fija ensamblada por
completo en tiempo de compilación — no existe un sistema de archivos en
tiempo de ejecución — `v32lua` no admite el `require`/`dofile` dinámico de
Lua real. En su lugar, `--#include "archivo.lua"` es un pegado textual en
tiempo de compilación, resuelto por un paso de preprocesamiento antes de
que el lexer vea siquiera el archivo, exactamente igual que el `#include`
de C:

```lua
--#include "src/physics.lua"
--#include "src/entities.lua"
```

* Los archivos incluidos se empalman en el nivel superior genuino del
  chunk — sin envolverlos en `do...end` ni en un cuerpo de función — de
  modo que una `local` de nivel superior en un archivo incluido se
  comporta de forma idéntica a una declarada en el archivo de entrada.
* Los destinos de inclusión se resuelven buscando, en este orden: el
  directorio del archivo que incluye; el directorio de trabajo actual del
  compilador; cada entrada de la variable de entorno `V32LUA_INCLUDE` si
  está definida (una lista separada por dos puntos; por punto y coma en
  Windows); y finalmente la ruta de inclusión por defecto integrada,
  `/usr/local/Vircon32/v32tools/include/v32lua` (se fija al compilar: ver
  `inc/config.h`, o [Instalación](#instalacion) para la compilación con
  CMake). Ahí es donde `make sysinstall` y `cmake --install` colocan los
  ports de la biblioteca estándar de `lib/`, para que cualquier proyecto
  pueda hacer `--#include "string.lua"` sin copiar la biblioteca.
  Las rutas absolutas se usan tal cual.
* Se detectan las inclusiones cíclicas, y cada archivo resuelto se incluye
  como máximo una vez a lo largo de toda la expansión.
* Las pistas de recursos de cartucho (`--#texture`, `--#sound`,
  `--#tilemap`) declaradas dentro de un archivo incluido reciben IDs de
  recursos correctos y el orden correcto en el XML.
* Los mensajes de error dentro de un archivo incluido reportan el archivo
  fuente y el número de línea correctos, mediante una tabla interna de
  remapeo de líneas.
* Dos archivos incluidos que cada uno declare una `local` de nivel
  superior con el mismo nombre comparten una sola global — idéntico a lo
  que haría el código monolítico equivalente.

---

## Proceso de Compilación

**Flujo de Compilación**

1. **Análisis Léxico y Sintáctico**: Flex/Bison analiza el código fuente
   Lua en un Árbol de Sintaxis Abstracta (AST) tipado.
2. **Resolución de Símbolos y Ámbitos**: Resuelve variables a través de
   los ámbitos léxicos, mapeando las globales a direcciones RAM
   secuenciales y las locales a posiciones de pila `[BP - offset]`.
3. **Generación de Código**: Emite instrucciones de ensamblador de
   Vircon32, aplicando sustituciones de intrínsecos de hardware mientras
   recorre el AST.
4. **Ensamblado del Cartucho**: Emite el archivo `.asm` final, incrusta
   las rutinas de soporte en tiempo de ejecución, genera la sección de
   datos de cadenas de solo lectura, y produce la definición de cartucho
   `.xml`.

**Etapas de Compilación (`-v`)**

Cuando `-v` está habilitado, `v32lua` reporta su progreso a través de sus
etapas de pipeline:

1. **Etapa 1: Lexer** — Tokeniza el código fuente Lua, eliminando los
   comentarios estándar y procesando las secuencias de escape de cadenas
   (`\n`, `\t`, `\r`, `\\`, `\"`).
2. **Etapa 2: Preprocesador** — Expande las directivas `--#include` y
   evalúa las pistas de cartucho (`--#...`) y las sintaxis de comentarios
   personalizadas.
3. **Etapa 3: Parser** — Construye un Árbol de Sintaxis Abstracta (AST)
   completo usando una gramática LALR(1) de Bison con una precedencia de
   operadores estricta (núcleo PEMDAS + lógico).
4. **Etapa 4: Analizador Semántico** — Ejecuta una pre-pasada para
   registrar los símbolos globales de funciones y variables e inicializar
   el ámbito global.
5. **Etapa 5: Emisor** — Recorre el AST para generar ensamblador de
   Vircon32, aplicando la asignación de registros y los desplazamientos de
   ámbito, y finalmente produce el archivo de configuración XML del
   cartucho.

---

## Características Clave del Lenguaje y del Compilador

**Modelos de Ejecución Flexibles: `main()` vs. `game_loop()`**

Para acomodar diferentes estilos de arquitectura de juego, el compilador
admite dos puntos de entrada de función distintos:

* **La Función de Espera Automática (`game_loop`)**: Si tu programa
  declara una función `game_loop()`, el compilador genera automáticamente
  un arnés de ejecución continuo. La CPU llama a `game_loop()`, detiene la
  ejecución del cuadro actual usando la instrucción `WAIT` de la CPU, y
  repite indefinidamente. Esto es ideal para juegos de arcade y demos
  estándar, e imita el comportamiento de otras consolas de fantasía.

* **Control Manual (`main`)**: Si tu programa declara una función
  `main()`, la CPU se detendrá al terminar la función `main()`, imitando
  un comportamiento similar al de la función `main()` de C. Si deseas
  mantener la ejecución, debes establecer algún tipo de bucle de juego, y
  debes ejecutar las instrucciones `WAIT` necesarias para asegurar un
  procesamiento continuo y una visualización fluida de los elementos en
  pantalla. El compilador rastrea si se emite una instrucción `WAIT`
  dentro de `main()`; si falta, `v32lua` emite una advertencia semántica
  en tiempo de compilación.

Además, como paso previo a cualquiera de los anteriores:

* **Gancho de Inicialización**: En ambos modelos, si está presente una
  función `init()`, se garantiza que se ejecute exactamente una vez
  después de las asignaciones de RAM globales de nivel superior y antes
  de que comience el bucle principal.

Un programa debe declarar al menos una de `main()` o `game_loop()` — este
es el punto de entrada designado, y su ausencia es un error de compilación.

**NaN-Boxing: Elementos en RAM vs. ROM**

`v32lua` usa una arquitectura de etiquetado de 32 bits que empaqueta
metadatos de tipo y punteros de carga útil en valores unificados,
manteniendo los **elementos de ROM** inmutables (literales de cadena,
punteros de función) separados de los **objetos de montículo (heap) en
RAM** dinámicos (tablas):

| Tipo de Dato | Máscara/Etiqueta Hex | Descripción de la Arquitectura |
| --- | --- | --- |
| **Nil** | `0xFFC00000` | Representación canónica para valores indefinidos/ausentes. |
| **Booleano Falso** | `0xFFC00001` | Valor falso de cortocircuito. |
| **Booleano Verdadero** | `0xFFC00002` | Valor verdadero de cortocircuito. |
| **Cadena ROM** | `0x7FC00000` | Punteros a secciones de datos de cadena de solo lectura (`__string_%d`) en ROM. |
| **Cadena RAM** | `0xFFC00000` | Cadenas construidas en tiempo de ejecución, en el montículo (carga útil 4 en adelante). |
| **Función** | `0x7F800000` | Dirección de código en ROM, o (con el bit 21 activo) un registro de clausura en RAM. |
| **Tabla** | `0xFF800000` | Direcciones de memoria del montículo empaquetadas (Bit 31=1, Bit 22=0). |
| **Número** | Flotante IEEE 754 | Valores de punto flotante nativos de Vircon32 sin empaquetar, para matemática directa. |

**Intrínsecos de Hardware y Mapeo de E/S**

Los juegos de alto rendimiento de Vircon32 no pueden permitirse búsquedas
en tablas hash para la manipulación de hardware. `v32lua` intercepta
expresiones específicas de acceso a miembros de tabla y llamadas a
funciones, y las compila directamente en instrucciones nativas de E/S de
hardware:

* **Acceso a Hardware de Costo Cero**: Acceder a espacios de nombres como
  `ioports.gpu.*`, `ioports.spu.*`, `ioports.tim.*`, `ioports.rng.*`,
  `ioports.car.*`, `ioports.mem.*`, o `system.*` evita por completo las
  rutinas de búsqueda en tablas. Se compilan directamente en operaciones
  de puertos de hardware (como `GPU_DrawingPointX` o `TIM_FrameCounter`).

* **`music.*` / `sfx.*`**: La API nativa de sonido compila llamadas como
  `music.play(SOUND, channel, loop)` en una secuencia lineal de `OUT`
  cuando todos los argumentos se conocen en tiempo de compilación,
  recurriendo a una pequeña rutina en tiempo de ejecución solo cuando los
  argumentos son dinámicos. Consulta [doc/API.es.md](doc/API.es.md) para ver la
  superficie completa, incluyendo por qué el orden de escritura de los
  puertos SPU (detener → asignar → volumen → reproducir →
  bucle/posición) es importante.

* **`tilemap.*`**: Una API nativa de mapas de mosaicos (`tilemap.get()`,
  `tilemap.set()`, `tilemap.render()`) respaldada por una pista de
  cartucho `--#tilemap`. Los datos del mapa de mosaicos se distribuyen de
  solo lectura en la ROM y se promueven de forma perezosa a una copia
  privada en RAM la primera vez que se escribe en un mapa dado.

* **Sondeo Consolidado del Mando de Juego**: El sondeo de la entrada del
  controlador se optimiza en un único intrínseco de variable
  (`ioports.inp.inputs`). El compilador sondea todos los ejes/botones del
  mando, combina los estados de botón activos en una máscara entera de
  32 bits desplazada, y la convierte en un flotante de Lua en un solo
  registro. Las entradas de mando independientes también están
  disponibles (`ioports.inp.left`, `ioports.inp.A`, etc.) como
  intrínsecos de variable.

* **Rutas Rápidas Integradas**: Las operaciones estándar de Lua como la
  concatenación de cadenas (`..`), la longitud (`#`) y el menos unario
  (`-`) se mapean directamente a subrutinas optimizadas en tiempo de
  ejecución (`__builtin_strcat`, `__builtin_len`, `__builtin_unm`).

Consulta [doc/API.es.md](doc/API.es.md) para la referencia completa y
autoritativa — este README resalta las ideas, el documento de la API cubre
cada llamada.

**Experiencia de Desarrollo y Herramientas de Depuración**

* **Reporte Visual de Errores en ASCII**: Los errores léxicos, sintácticos,
  semánticos e internos del compilador imprimen fragmentos de código ASCII
  resaltados y de múltiples líneas que apuntan directamente a la línea
  ofensora en el archivo fuente.

* **Mapeo de Fuente a Ensamblador (`-g`)**: Pasar la bandera de depuración
  `-g` genera un archivo `.debug` complementario junto al ensamblador de
  salida. Este archivo mapea los desplazamientos de línea relativos del
  ensamblador de Vircon32 a las líneas originales del código fuente Lua y
  a los puntos de entrada de las funciones, habilitando la depuración
  paso a paso bajo [v32sim](https://github.com/g7n-org/v32sim).

* **Burbujas de Ensamblador en Línea y en Bruto**: Puedes escribir
  ensamblador nativo directamente dentro de Lua usando
  `__asm__("tu ASM")` (que respalda y restaura los registros y el puntero
  de pila) o `__rawasm__("tu ASM")` para ejecución sin protección. Ambos
  modos admiten la interpolación de cadenas de variables Lua usando la
  sintaxis `{nombre_var}`.

---

## Características de Lua Soportadas

`v32lua` implementa un subconjunto de Lua, adaptado específicamente para
el desarrollo de juegos en hardware embebido.

**Variables y Ámbito**

* **Variables Globales:** Se registran automáticamente en RAM y se
  acceden mediante símbolos (`[var_nombre]`, `[func_nombre]`). La
  dirección `0` está reservada para el puntero de montículo (heap) y las
  direcciones `1`/`2` son palabras de trabajo (scratch) reservadas
  usadas por la rutina de conversión de flotante a cadena; las variables
  globales ordinarias comienzan en la dirección `3`.

* **Variables Locales:** Declaradas con la palabra clave `local`. Con
  ámbito léxico limitado al bloque envolvente (cuerpos de función, bucles
  o condicionales) y mapeadas a desplazamientos de pila
  (`[BP - offset]`). Una `local` declarada en el nivel superior propio de
  un chunk — fuera de cualquier función — se promueve a una global en su
  lugar, ya que su almacenamiento de otro modo residiría en un marco de
  pila que retorna antes de que se ejecute cualquier código del juego;
  esto se aplica igualmente a las `local`s incorporadas mediante
  `--#include`.

En la jerga de Lua, las funciones son "ciudadanas de primera clase", y
son efectivamente variables. Eso se confirma en `v32lua`, ya que ambas se
transportan dentro del esquema de NaN-boxing.

**Asignación Múltiple**

El compilador admite de forma nativa la asignación múltiple y el
intercambio de variables sin requerir temporales explícitos del usuario:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Sintetiza cadenas de registros temporales para intercambiar valores de forma segura
```

**Operadores a nivel de bits**

Los `&`, `|`, `~` (xor), `<<`, `>>` y `~` unario (not) de Lua 5.3/5.4.
Todo número es un float32, así que cada operación toma sus operandos como
palabras de 32 bits y convierte el resultado de vuelta:

* **Nativa / TIC-80:** enteros. Los operandos se redondean hacia abajo y se
  toman módulo 2^32, así que `0xFFFFFFFF` y `-1` son la misma palabra. El
  signo del valor completo se conserva, de modo que `&`, `|`, `~` coinciden
  con Lua de 64 bits para operandos en [-2^31, 2^32): `-1 & 0xFF` es 255,
  `~0` es -1, `0xFF << 24` es 4278190080. `>>` es lógico; un desplazamiento
  de 32 o más da 0.
* **PICO-8:** punto fijo 16.16, exactamente como lo hace PICO-8 — las
  fracciones participan (`0.5 | 1` es 1.5, `~0` es -1/65536), `>>` es
  aritmético, y se aceptan el `^^` (xor), `>>>` (desplazamiento lógico a la
  derecha), `<<>` / `>><` (rotación) de PICO-8, las formas compuestas
  (`&= |= ^^= <<= >>= >>>= <<>= >><=`), las funciones `band`/`bor`/
  `bxor`/`bnot`/`shl`/`shr`/`lshr`/`rotl`/`rotr` y los literales binarios
  `0b1010`. Los literales hexadecimales `0x8000`–`0xffff` son negativos,
  como en PICO-8 (`0xffff == -1`).

Límite: un float32 tiene 24 bits significativos, así que un resultado como
`0xDEADBEEF` vuelve redondeado; las máscaras y los campos empaquetados con
menos bits significativos (`0xFF000000`, `0xF0F0`) son exactos. Las
expresiones de literales (`1 << 4`) se evalúan en tiempo de compilación.

**Programación Orientada a Objetos y Tablas**

`v32lua` proporciona azúcar sintáctico transparente para modelos de POO
basados en tablas:

* **Desazucarado de Definición de Métodos:** Definir una función en una
  tabla genera automáticamente una etiqueta con nombre alterado y vincula
  la propiedad del puntero de función:

```lua
function Player.move(dx, dy) --[[ cuerpo ]] end
-- Se desazucara a: Player["move"] = __function_Player_move
```

* **Desazucarado de Llamada a Métodos (operador `:`):** Usar el operador
  de dos puntos evalúa automáticamente la expresión de tabla y la inyecta
  como un parámetro implícito `self`:

```lua
Player:move(5, -2)
-- Se desazucara a: Player.move(Player, 5, -2)
```

**Flujo de Control**

* **Bucles:** `while ... do ... end`, `repeat ... until ...`, `for`
  numérico `for i = a, b [, step]` y `for` genérico
  `for k, v in pairs(t)` / `ipairs(t)` (o tu propia función iteradora),
  cada uno con su propio ámbito de bloque.

* **Control de Bucle:** Las sentencias `break` saltan inmediatamente a la
  etiqueta final del bucle más interno actual (rastreado mediante una
  pila interna de compilación de bucles).

* **`goto` / `::etiqueta::`:** etiquetas al estilo de Lua 5.2, con ámbito
  de bloque y referencias hacia adelante — el modismo habitual
  `goto continue` / `::continue::` funciona, incluso con el mismo nombre de
  etiqueta en varios bucles de una misma función.

* **Condicionales:** Estructuras `if <cond> then ... elseif <cond> then
  ... else ... end` con ramificación de cortocircuito.

**Operadores y Expresiones**

* **Aritméticos:** `+`, `-`, `*`, `/` (mapeados a las instrucciones de
  hardware de punto flotante de Vircon32 `FADD`, `FSUB`, `FMUL`, `FDIV`),
  `%`, `^`, `//` (división entera hacia abajo) y menos unario. Una cadena
  que contiene un número se convierte en la aritmética, como en Lua
  (`"5" + 1` es 6). No hay error para otros operandos (`"abc" + 1`,
  `nil + 1`): el resultado no tiene sentido.

* **Relacionales:** `==`, `~=` (mediante `__builtin_eq` con desempaquetado
  de NaN), `<`, `>`, `<=`, `>=` (mediante hardware `FLT`, `FLE`, `FGT`,
  `FGE`).

* **Lógicos:** `and`, `or`, `not` (con evaluación de cortocircuito).

* **Concatenación de Cadenas:** el operador `..` empuja automáticamente
  los operandos e invoca la subrutina en tiempo de ejecución
  `__builtin_strcat`.

* **Literales y métodos de cadena:** cadenas `"dobles"`, `'simples'` y
  largas `[[entre corchetes]]` (sin escapes; se descarta un salto de línea
  justo después de `[[`). Los literales numéricos aceptan exponentes
  (`1e-3`, `2.5E4`). Las funciones de la biblioteca de cadenas funcionan
  como métodos sobre valores de cadena — `s:sub(2, #s)`, `("abc"):upper()`,
  `s:len()`, `rep`, `byte`, `find`, `lower`, `reverse`, `gsub` — y las
  cadenas usadas como claves de tabla se comparan por contenido, así que
  `t["a" .. "b"]` encuentra `t.ab`.

* **Números → cadenas:** los números enteros se imprimen sin punto decimal
  (`"5"`); los demás con hasta 6 dígitos fraccionarios significativos y sin
  ceros finales (`"0.5"`, `"2.25"`) — precisión float32.

* **Operador de Longitud:** el operador `#` invoca `__builtin_len` para
  resolver longitudes de cadenas o tablas.

**Funciones y Retornos de Múltiples Valores**

Los argumentos se pasan por la pila. Las funciones pueden retornar varios
valores: los tres primeros vuelven en los registros `R0`, `R2` y `R3`, y
los demás pasan por un búfer reservado en RAM. Como en Lua, una llamada o
`...` al final de una lista se expande a todos sus valores — en argumentos
(`f(a, g())`), constructores de tabla (`{g()}`), `return x, ...` y
`local a, b = ...` — hasta 32 valores. Las funciones variádicas
(`function f(...)`), las clausuras con upvalues (locales capturadas,
compartidas entre las clausuras que las capturan) y la recursión
funcionan.

**Agrupación de Literales de Cadena**

Todos los literales de cadena declarados en el código fuente (por
ejemplo, `"GAME OVER"`) se recopilan durante la compilación, se
deduplican y se emiten en una sección de datos dedicada al final de la
ROM (`__string_0: string "GAME OVER"`), evitando el consumo redundante de
ROM.

**Evaluación Truthy / Falsy con Cortocircuito**

En Lua, solo `nil` y `false` evalúan como falso en expresiones
condicionales; cualquier otro valor (incluyendo `0` y las cadenas vacías)
es **verdadero (truthy)**. `v32lua` implementa esto mediante dos
primitivas de emisión de ensamblador de alta velocidad:

* **`emit_falsy_jump(reg, label)`**: Comprueba si `reg` coincide con
  `0xFFC00000` (Nil) o `0xFFC00001` (Falso). Si coincide cualquiera de
  los dos, la ejecución salta a la etiqueta objetivo.

* **`emit_truthy_jump(reg, label)`**: Comprueba contra Nil y Falso; si no
  coincide ninguno, la ejecución hace cortocircuito hacia la etiqueta
  objetivo.

Cuando se evalúan los operadores lógicos (`and`, `or`), el resultado
evaluado se deja intacto en el registro de destino, preservando el
idioma de Lua de retornar el valor real del operando en lugar de un
booleano estricto.

---

**Metatablas**

`setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawlen` y
`rawequal`. Se admiten estos eventos:

* `__index`: una tabla, que puede tener su propia metatabla (así
  funcionan las cadenas de clases), o una función `(t, k)`.
* `__newindex`: una tabla o una función `(t, k, v)`, solo para claves
  que la tabla no tiene, como en Lua.
* `__call`: llamar a la tabla, que se pasa como primer argumento.
* `__tostring`, `__len`, `__metatable`.

```lua
Point = {}
Point.__index = Point
function Point.new(x, y) return setmetatable({x = x, y = y}, Point) end
function Point:len2() return self.x * self.x + self.y * self.y end
```

La metatabla solo se consulta cuando una lectura no encuentra nada o una
escritura añade una clave nueva. Las tablas sin metatabla ejecutan el
mismo código que antes. Los eventos aritméticos, de comparación y de
concatenación (`__add`, `__eq`, `__lt`, `__concat`, …) **no** están
soportados: los operadores se compilan a instrucciones de coma flotante
directas, y comprobar en cada una si hay una tabla ralentizaría toda la
aritmética.

## E/S de Hardware e Intrínsecos del Compilador

Una de las características más poderosas de `v32lua` es su **motor de
interceptación de intrínsecos estático**. Cuando el compilador encuentra
accesos a tablas o llamadas a funciones que coinciden con rutas de
sistema específicas (por ejemplo, `ioports.gpu.clear()`), **evita por
completo las búsquedas dinámicas en tablas** y emite instrucciones de E/S
de hardware de Vircon32 directas (`IN`, `OUT`).

**Conversión Automática de Tipos en los Límites de E/S**

Debido a que las variables de Lua se almacenan como flotantes IEEE 754
empaquetados en NaN mientras que los puertos de hardware de Vircon32
esperan enteros de 32 bits o booleanos, `v32lua` inyecta automáticamente
instrucciones de conversión de hardware durante las lecturas y escrituras
de puertos:

* **`CFI` (Convertir Flotante a Entero):** Se emite automáticamente al
  escribir valores numéricos en puertos GPU/Entrada de tipo entero.

* **`CFB` (Convertir Flotante a Booleano):** Se emite al escribir
  banderas booleanas en registros de hardware, decodificando la
  veracidad (truthiness) de Lua (solo `nil`/`false` son falsos) en lugar
  de una prueba cruda de no-cero.

* **`CIF` (Convertir Entero a Flotante):** Se emite inmediatamente
  después de ejecutar una instrucción `IN` desde puertos de hardware de
  tipo entero, asegurando que el valor sea utilizable de inmediato como
  un número de Lua.

* **Lecturas de puertos booleanos:** decodificadas en la representación
  empaquetada `true`/`false` en lugar de un flotante crudo `0.0`/`1.0`,
  ya que `0.0` es verdadero (truthy) en Lua y de otro modo haría que un
  mando desconectado o una tarjeta de memoria se leyeran como
  "conectados".

**Tabla de Referencia Completa de Intrínsecos**

La referencia completa y autoritativa para cada intrínseco —
`ioports.gpu.*`, `ioports.inp.*`, `ioports.spu.*`, `ioports.tim.*`,
`ioports.rng.*`, `ioports.car.*`, `ioports.mem.*`, `music.*`/`sfx.*`,
`tilemap.*`, `memcard.*` y `system.*` — vive en [doc/API.es.md](doc/API.es.md),
incluyendo advertencias sobre el orden de puertos, firmas de llamadas y
ejemplos trabajados. Su [Referencia rápida](doc/API.es.md#quick-reference)
enumera cada intrínseco y cada puerto `ioports.*` (incluidos todos los de
`ioports.gpu.*`) en una sola página. Una breve muestra de las entradas de
uso más común:

*Control y Dibujo GPU (`ioports.gpu.*`)*

| Ruta Lua / Intrínseco | Puerto/Comando Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lectura / Escritura | Establece o lee el ID de textura activo usado para las operaciones de dibujo. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lectura / Escritura | Selecciona la sub-región de textura (cuadro de sprite) a renderizar. |
| **`ioports.gpu.x`** / **`ioports.gpu.y`** | `GPU_DrawingPointX/Y` | Lectura / Escritura | Coordenadas de pantalla para la colocación del dibujo. |
| **`ioports.gpu.minX/minY/maxX/maxY`** | `GPU_RegionMin/MaxX/Y` | Lectura / Escritura | Define los límites en píxeles de la región de textura activa. |
| **`ioports.gpu.hotX/hotY`** | `GPU_RegionHotSpotX/Y` | Lectura / Escritura | Establece el origen de dibujo (hotspot) relativo a la región del sprite. |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Llamada a Función | Ejecuta un comando de dibujo de hardware: `"zoom"`, `"rotate"`, `"rotozoom"`, o el valor por defecto. |
| **`ioports.gpu.clear([color])`**<br>**`ioports.gpu.clear(r, g, b [, a])`** | `GPU_ClearColor` + `GPU_Command` | Llamada a Función | Establece el color de borrado y limpia la pantalla. Admite cadenas de color preestablecidas (`"black"`, `"white"`, `"blue"`, `"red"`, `"green"`), un valor empaquetado `0xAABBGGRR` (un literal, o `rgba()`/`hex()` para un valor en tiempo de ejecución), o componentes separados: `clear(r, g, b [, a])`, cada uno `0`–`255`, con alfa opaco por defecto. |
| **`rgba(r, g, b [, a])`** | — | Intrínseco | La palabra empaquetada `0xAABBGGRR` (en bruto, no un número de Lua) para el `color_mult` de `spr()`, `ioports.gpu.clear(color)`, `ioports.gpu.multiply` / `bgcolor`. Componentes limitados a `0`–`255` y truncados, alfa 255 por defecto; se evalúa en tiempo de compilación cuando todos son literales. Guarda los colores como componentes y llama a `rgba()` donde se dibujan — ver [doc/API.es.md](doc/API.es.md#colors-rgba) para saber por qué. |
| **`color(n)`** | — | Intrínseco | Un número que contiene un color empaquetado (calculado, o leído de una tabla), como palabra en bruto. Redondeado hacia abajo y ajustado a 32 bits; los literales son exactos, los valores en tiempo de ejecución conservan los 24 bits significativos de float32 ([detalles](doc/API.es.md#colors-color)). |
| **`rect(x1, y1, x2, y2 [, color])`**<br>**`rectfill(x1, y1, x2, y2 [, color])`** | `GPU_Command` (dibujo escalado) | Intrínseco | Contorno / rectángulo relleno entre dos esquinas incluidas, en cualquier orden; `color` es una palabra empaquetada como en `spr()` (blanco por defecto). Un dibujo de GPU para `rectfill`, hasta cuatro para `rect`; el estado de la GPU se restaura después ([detalles](doc/API.es.md#gráficos-rect--rectfill)). |

*Mando de Juego y Entrada (`ioports.inp.*`)*

| Ruta Lua / Intrínseco | Puerto/Comando Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lectura / Escritura | Selecciona el índice del controlador activo (`0`-`3`) para el sondeo de entrada. Al leerlo devuelve el último índice asignado (los emuladores no pueden releer el puerto). |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Solo Lectura | Retorna un booleano de Lua: si el mando seleccionado está conectado. |
| **`ioports.inp.left/right/up/down`** | `INP_Gamepad*` | Solo Lectura | Estado direccional del D-Pad (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.A/B/X/Y/L/R/START`** | `INP_GamepadButton*` | Solo Lectura | Estado de botón de acción/gatillo (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.inputs`** | *Subrutina de Acción Personalizada* | Solo Lectura | **Intrínseco de recopilación:** sondea todos los botones/ejes del mando en una sola pasada, los combina en una única máscara de bits de 32 bits, y la convierte a un flotante de Lua. |
| **`key([k])`**, **`keyp([k [, hold, period]])`** | dispositivo v32kbd en un puerto de mando | Intrínseco | **Solo con un adaptador v32io o el emulador modificado** ([por qué](#teclado-y-ratón-v32io)). Un teclado completo a través de un dispositivo v32kbd (puerto de mando 2 por defecto, `--#keyboard N`): tecla pulsada / pulsada en este cuadro, al estilo de TIC-80, con códigos de tecla o nombres literales (`"a"`, `"enter"`, `"shift"`) ([detalles](doc/API.es.md#teclado-key--keyp--kbd)). |
| **`kbd.read()`**, **`kbd.event()`**, **`kbd.port([n])`**, **`kbd.capslock()`**, **`kbd.connected()`**, **`kbd.clear()`** | dispositivo v32kbd | Intrínseco | Texto escrito (con Mayús y Bloq Mayús), eventos de pulsar/soltar, el puerto del teclado, Bloq Mayús, dispositivo presente, descartar eventos no leídos. |
| **`mouse()`** | dispositivo v32mouse en un puerto de mando | Intrínseco | **Solo con un adaptador v32io o el emulador modificado** ([por qué](#teclado-y-ratón-v32io)). Un ratón a través de un dispositivo v32mouse (puerto de mando 3 por defecto, `--#mouse N`): `x, y, left, middle, right, scrollx, scrolly`, como el de TIC-80 (desplazamiento siempre 0) ([detalles](doc/API.es.md#ratón-mouse--mouse)). |
| **`mouse.pressed/released([b])`**, **`mouse.buttons()`**, **`mouse.delta()`**, **`mouse.position([x, y])`**, **`mouse.bounds(...)`**, **`mouse.scale([n])`**, **`mouse.port([n])`**, **`mouse.connected()`** | dispositivo v32mouse | Intrínseco | Cambios de botones en este cuadro, botones pulsados, movimiento en este cuadro, el puntero, sus límites y velocidad, el puerto del ratón, dispositivo presente. |

*Utilidades del Sistema y de Ejecución*

| Ruta Lua / Intrínseco | Instrucción Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Llamada a Función | Emite la instrucción de hardware `HLT`, terminando de inmediato la ejecución de la CPU o congelando el cuadro hasta el siguiente ciclo de interrupción/cuadro. |
| **`system.wait()`** | `WAIT` | Llamada a Función | Emite la instrucción de hardware `WAIT`, pausando la ejecución hasta el siguiente ciclo de interrupción/cuadro. |
| **`system.frames()`** / **`system.cycles()`** | `TIM_FrameCounter` / `TIM_CycleCounter` | Solo Lectura | Cuadros desde el encendido / ciclos de CPU usados hasta ahora en este cuadro (el `()` es opcional). |
| **`print(x, y, value)`** | `__builtin_tostring` + `__builtin_print` | Llamada a Función | Convierte `value` en cadena y lo dibuja en pantalla con la fuente de la BIOS, en la posición en píxeles `x`, `y`. |

---

## Ensamblador en Línea (`__asm__` y `__rawasm__`)

Para bucles internos críticos en rendimiento o manipulación avanzada del
hardware de Vircon32, `v32lua` proporciona inyección directa de
ensamblador en línea.

**Ensamblador en Línea Estándar (`__asm__`)**

La directiva `__asm__` permite incrustar cadenas de ensamblador crudo de
Vircon32 directamente dentro de funciones Lua. Fundamentalmente, admite
**interpolación de variables**, permitiendo un puente fluido entre los
símbolos de ámbito de Lua y los registros de ensamblador:

```lua
local speed = 5.0
__asm__("MOV R0, {speed}\nFADD R0, 1.5\nMOV {speed}, R0")
```

* **Cómo funciona:** Cualquier identificador envuelto en llaves (por
  ejemplo, `{speed}`) se reemplaza en tiempo de compilación por el
  operando de memoria de la variable: `[BP - n]` para una local,
  `[BP + n]` para un parámetro, `[var_speed]` para una global. El código
  debe ser un único literal de cadena (escribe los saltos de línea como
  `\n`). Una local capturada por una clausura contiene un puntero a su
  caja en lugar del valor.

* Cada línea de ensamblador interpolado pasa a través del motor de
  formato del compilador, asegurando una indentación y alineación de
  comentarios consistentes en el archivo `.asm` de salida.

* Este ensamblador en línea estándar aplica algunas salvaguardas y
  protecciones leves, en la forma de respaldar cualquier registro
  existente en uso junto con la pila. Aunque no previene problemas, puede
  ayudar a mitigar algunos causados por accidente. Cualquier cambio de
  registro hecho aquí se pierde fuera de la "burbuja" en línea.

**Ensamblador en Bruto (`__rawasm__`)**

La directiva `__rawasm__` produce la cadena literal directamente en el
flujo de ensamblador sin ninguna salvaguarda aplicada. Esto puede ser
bastante peligroso, y solo debería usarlo el usuario de ensamblador más
conocedor y experimentado. También es la base del propio arnés de
pruebas unitarias del compilador: un archivo de prueba es típicamente un
envoltorio `function main() ... end` alrededor de una secuencia de
bloques `__rawasm__` con etiquetas `__debugN:` para establecer puntos de
interrupción bajo [v32sim](https://github.com/g7n-org/v32sim).

---

## Mapa de Memoria de Referencia

| Dirección RAM | Designación | Uso |
| --- | --- | --- |
| `0` | `HEAP_POINTER` | Almacena la dirección de inicio dinámica para las asignaciones de tablas/cadenas en tiempo de ejecución. |
| `1`, `2` | `FTOA_SCRATCH_PTR_A`/`B` | Palabras de trabajo (scratch) reservadas usadas por la rutina de conversión de flotante a cadena. |
| `3` a `HEAP_START - 1` | RAM Global | Ranuras asignadas secuencialmente para variables globales de Lua, IDs de recursos y `local`s de nivel superior promovidas. |
| `HEAP_START` en adelante | Montículo (Heap) Dinámico | Memoria en tiempo de ejecución gestionada por el asignador de tablas y las rutinas de cadenas. |
| Tope de la Pila (`SP`) | Pila de Llamadas | Registros de activación de funciones, variables locales y estados de registros guardados. |

`HEAP_START` se calcula después de que ha terminado toda la generación
de código, de modo que la generación de código de las sentencias de
nivel superior que registra globales tardías nunca pueda colisionar con
el montículo.

---

## Peculiaridades y supuestos del compilador

Aunque `v32lua` intenta ser un compilador de Lua funcional, de ninguna
manera es una implementación completa y conforme a la especificación del
lenguaje. Para empezar, no hay máquina virtual de bytecode, ni
intérprete — Lua se compila directamente a ensamblador nativo.

Además, existen algunas desviaciones explícitas respecto a una
implementación estándar del lenguaje para adaptarse mejor al entorno
autónomo (freestanding) de Vircon32:

* `print()` requiere, como sus primeros dos parámetros, la posición `x`
  e `y` en pantalla.

* Las sentencias `return` independientes no funcionan (generarán un
  error de sintaxis). Dale algo (`nil`, `0`, etc.) para que funcione.

* La ejecución del programa DEBE residir dentro de una función. Aunque
  puedes declarar funciones, debes usar uno de los puntos de inicio
  designados para comenzar la cadena de ejecución (`init()`,
  `game_loop()`, o `main()`). No tener una función `main()` o
  `game_loop()` produce un error de compilación. `game_loop()` emite
  automáticamente un `WAIT` antes de llamarse a sí misma de nuevo,
  convirtiéndola en tu ubicación natural de bucle de juego — similar a
  otras consolas de fantasía (como la función `TIC()` en TIC-80, que es
  requerida de forma similar).

* `v32lua` es una implementación **solo de flotantes**: no existe el
  tipo dual entero/flotante de Lua 5.3+. Todos los números son flotantes
  IEEE-754 de 32 bits, por lo que los enteros por encima de 2^24 no se
  pueden representar con exactitud — algo a tener en cuenta para código
  con mucha manipulación de bits.

* Una `local` declarada en un bloque léxicamente fuera de cualquier
  función (un `do...end` desnudo, o un cuerpo `if`/`while`/`for` a nivel
  de chunk) actualmente no tiene ninguna salvaguarda a nivel de
  compilador si una función la lee posteriormente — ver el punto de la
  hoja de ruta más abajo.

Claramente, este esfuerzo está enfocado en crear una herramienta para el
desarrollo en Vircon32, y no en ser una implementación de Lua totalmente
conforme. Se harán esfuerzos por acercarse tanto como sea posible y
factible, sin sacrificar un rendimiento significativo ni alejarse de ser
la herramienta que pretende ser.

## Optimización del Compilador

Al comienzo del desarrollo del compilador, todo el código de optimización
fue eliminado y trasladado a una herramienta separada,
[v32opt](https://github.com/wedge1020/v32opt). Está diseñada como un
optimizador de ensamblador de Vircon32 de propósito general, pensado para
usarse con el compilador de C y el compilador de Lua (junto con
ensamblador escrito a mano). Las pruebas tempranas han mostrado mejoras
leves en el rendimiento, y un ahorro potencial de espacio al eliminar
instrucciones redundantes.

Al momento de escribir esto, esta herramienta todavía está muy en
desarrollo, pero muestra promesa y probablemente funcionará para
escenarios estándar bajo los niveles de optimización `-O1`, `-O2`, e
incluso `-O3`. Está pensada para insertarse en la cadena de compilación
después de compilar y antes de ensamblar. Los Makefiles de las demos la
usan cuando está instalada, generando un `bin/<demo>Opt.v32` optimizado
junto al cartucho normal (ver [Compilar las demos](#building-the-demos) y
[doc/USAGE.es.md](doc/USAGE.es.md#5-opcional-el-optimizador)).

## Hoja de Ruta / Aún No Implementado

Lo siguiente son brechas conocidas y deliberadas, no errores — ya sea
diferidas para mantener avanzando el desarrollo inicial, o pendientes de
una decisión de diseño:

* `pcall`/`error`/`assert`
* `string.match`/`gmatch`; los eventos de metatabla `__add`/`__sub`/…, `__eq`/`__lt`/`__le`,
  `__concat`, `__unm` (ver [Metatablas](#características-de-lua-soportadas))
* `select()`, y `next()` como función invocable (`pairs()` funciona)
* Las listas de múltiples valores están limitadas a 32 valores: los valores
  de retorno de una llamada, un `...` expandido o `unpack(t)` más allá de
  ese límite se descartan (`f(...)`, `{g()}`, `return x, ...`,
  `local a, b = ...` se expanden todos, hasta 32).
* Los operadores a nivel de bits trabajan sobre palabras de 32 bits (los
  números son float32): `x << 32` y resultados más anchos, y `>>` de un
  número negativo, difieren de los enteros de 64 bits de Lua, y un
  resultado con más de 24 bits significativos (`0xDEADBEEF`) se redondea.
  Ver **Operadores a nivel de bits** más arriba.
* `string.format` como método (`("%d"):format(x)`) — use
  `string.format(...)`.
* Recolección de basura: el heap es un asignador lineal, así que cada
  tabla, clausura y cadena en tiempo de ejecución vive hasta el reinicio.
  Los juegos de larga duración deberían reutilizar tablas en lugar de
  crearlas en cada fotograma. Las cadenas ocupan una palabra por carácter,
  así que construir una cadena larga pieza a pieza (`s = s .. c` en un
  bucle) usa memoria de forma cuadrática: nanoman decodifica sus niveles
  así y llena los 4M palabras de RAM tras unos 100 s de juego.
* Audio PICO-8 aún más pequeño: el sonido de un cartucho son ahora sus 64
  SFX a 22050 Hz (Celeste: 18 MB, antes 66 MB). Secuenciar notas sueltas
  en lugar de SFX completos lo reduciría más o menos a la mitad (cerca de
  la mitad de las notas de Celeste se repiten), a costa de un secuenciador
  por notas.
* PICO-8: `pal`/`palt` (compilan a no-ops con una advertencia), `clip`,
  valores reales de `stat` (aparte del ratón), anchos fraccionarios en `spr`, `pget`,
  la carga multicartucho (`reload` desde
  otro archivo, `cstore`); escribir en la memoria de sprites o de sonido
  no tiene efecto y leer la memoria de pantalla solo devuelve lo escrito
  allí (no hay lectura de la GPU); los filtros del editor de SFX en el
  sonido sintetizado
* TIC-80: `tri`/`trib`, `elli`/`ellib`, `clip`, `font`, la
  función de reasignación de `map()`; el argumento de velocidad de `sfx()`
  y los argumentos tempo/velocidad/sustain de `music()` (ver
  [doc/TIC80.md](doc/TIC80.md#sound)). `peek`/`poke` trabajan sobre una
  RAM emulada, pero escribir en los registros de pantalla, paleta, tiles o
  sonido no tiene efecto visible ni audible. `trace` no hace nada.
* `circ`/`circb`/`rectb` de TIC-80 dibujan un quad de GPU por píxel: un
  cartucho que dibuja muchos contornos grandes en cada cuadro (la pantalla
  de título de witchem_up) funciona por debajo de la velocidad máxima
* Un diagnóstico (advertencia/error) para leer, desde dentro de una
  función, una `local` declarada en un bloque léxicamente fuera de
  cualquier función a nivel de chunk (ver arriba)

---

## Uso de IA

NOTA: Hubo un uso e interacción extensivos de IA a lo largo de este
esfuerzo. Debe hacerse una distinción respecto al "vibe coding", pero sin
duda existe una difuminación entre lo humano y la IA. Al final, ambos se
benefician y podrían compensar las deficiencias del otro.

Este esfuerzo en realidad no se trataba principalmente de desarrollar un
compilador; comenzó como un intento honesto de tener una idea de la IA y
su impacto: su papel y su detrimento en el pensamiento y la educación
humanos. Que tuviera un tema de compilador fue simplemente para acentuar
un punto de interés. Sin duda ha sido una experiencia de aprendizaje. Si
no se hubiera conocido suficientemente los conceptos de compiladores y el
trasfondo necesario antes de comenzar esto, el esfuerzo habría terminado
mucho menos exitosamente.
