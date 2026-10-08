# API nativa de la consola de fantasía Vircon32

Este documento cubre ÚNICAMENTE la API nativa de Vircon32 — la superficie
activa cuando no está seleccionado ni el modo de compatibilidad
`--#api pico8` ni `--#api tic80`. Bajo esos modos, `spr()`/`btn()`/etc. son
en su lugar la propia API de esa consola (ver la documentación de
compatibilidad PICO-8 / TIC-80), y las llamadas de abajo no están
disponibles.

La [Referencia rápida](#quick-reference) de abajo reúne en una sola página
todos los intrínsecos y todos los puertos `ioports.*`; las secciones que
la siguen explican cada parte en detalle.

El orden de escritura de los puertos SPU es importante para el sonido; ver
[Sonido: music.\* / sfx.\*](#sonido-music--sfx).

---

## Tabla de Contenidos

- [Referencia rápida](#quick-reference)
  - [Funciones intrínsecas](#intrinsic-functions)
  - [ioports.\* — todos los puertos de hardware](#ioports--every-hardware-port)
  - [Biblioteca estándar](#standard-library)
- [Sonido: music.\* / sfx.\*](#sonido-music--sfx)
- [ioports.spu.cmd() — la vía de escape en bruto](#ioportsspucmd--la-vía-de-escape-en-bruto)
- [Puertos de E/S booleanos](#puertos-de-es-booleanos)
- [Sistema: system.\*](#sistema-system)
- [Gráficos: spr()](#gráficos-spr)
- [Gráficos: rect() / rectfill()](#gráficos-rect--rectfill)
- [Entrada: btn() / btnp()](#entrada-btn--btnp)
- [Teclado: key() / keyp() / kbd.\*](#teclado-key--keyp--kbd)
- [Ratón: mouse() / mouse.\*](#ratón-mouse--mouse)
- [Mapa de mosaicos: tilemap.\*](#mapa-de-mosaicos-tilemap)
- [Tarjeta de memoria: memcard.\*](#tarjeta-de-memoria-memcard)
- [Otros puertos de E/S en bruto](#otros-puertos-de-es-en-bruto)

---

<a id="quick-reference"></a>
## Referencia rápida

Un **intrínseco** es un nombre que el compilador reconoce y convierte en
instrucciones en línea o en una llamada a una rutina del runtime: no hay
ninguna tabla ni función de Lua detrás. Una función tuya con el mismo
nombre (`spr`, `rgba`, `color`, …) reemplaza al intrínseco.

<a id="intrinsic-functions"></a>
### Funciones intrínsecas

*Gráficos*

| Llamada | Devuelve | Qué hace |
|---|---|---|
| `spr(region, x, y [, sx [, sy [, angle [, color [, blend]]]]])` | nil | Dibuja una región de textura; elige el dibujo simple, escalado, rotado o rotado y escalado según los argumentos. [Detalles](#gráficos-spr) |
| `rect(x1, y1, x2, y2 [, color])` | nil | Contorno de rectángulo de 1 píxel entre dos esquinas incluidas. Color: palabra empaquetada, blanco por defecto. [Detalles](#gráficos-rect--rectfill) |
| `rectfill(x1, y1, x2, y2 [, color])` | nil | Rectángulo relleno, un solo dibujo de la GPU. |
| `print(x, y, value)` | nil | Dibuja `value` (convertido con `tostring`) en el píxel `x, y` con la fuente de la BIOS. |
| `ioports.gpu.clear([color])` / `clear(r, g, b [, a])` | nil | Establece el color de limpieza (opcional) y limpia la pantalla. [Detalles](#gpu-clear) |
| `ioports.gpu.draw([mode])` | nil | Dibuja la región seleccionada en `gpu.x, gpu.y`. `mode`: `"draw"` (por defecto), `"zoom"`, `"rotate"`, `"rotozoom"`, o `0`–`3`. |
| `ioports.gpu.blending(mode)` | nil | Establece el modo de mezcla: `"alpha"`/`"default"`, `"add"`, `"subtract"` (literal de cadena). |
| `ioports.gpu.sync()` | nil | Espera al siguiente cuadro (`WAIT`); igual que `system.wait()`. |
| `rgba(r, g, b [, a])` | palabra empaquetada | Empaqueta un color en la palabra `0xAABBGGRR` de la GPU. Componentes limitados a 0–255, alfa 255 por defecto. [Detalles](#colors-rgba) |
| `color(n)` | palabra empaquetada | Convierte un número que contiene un color empaquetado en la palabra (para colores calculados o cargados). [Detalles](#colors-color) |
| `hex("0x…")` | palabra empaquetada | Un literal de cadena con dígitos hexadecimales, como la palabra exacta de 32 bits. |

*Entrada*

| Llamada | Devuelve | Qué hace |
|---|---|---|
| `btn(id [, pad])` | booleano | El botón `id` (0–10, orden de hardware) está presionado. [Detalles](#entrada-btn--btnp) |
| `btnp(id [, pad])` | booleano | El botón `id` se presionó en este cuadro. |

*Teclado* (dispositivo v32kbd) — [detalles](#teclado-key--keyp--kbd)

| Llamada | Devuelve | Qué hace |
|---|---|---|
| `key([k])` | booleano | La tecla `k` (código o nombre literal: `"a"`, `"enter"`, `"shift"`) está pulsada; sin `k`: cualquier tecla. |
| `keyp([k [, hold, period]])` | booleano | La tecla `k` se pulsó en este cuadro (autorrepetición con `hold`/`period`, como TIC-80). |
| `kbd.read()` | número / nil | Siguiente pulsación como el carácter que escribe (Mayús y Bloq Mayús aplicados). |
| `kbd.event()` | número / nil | Siguiente evento: `+código` pulsada, `-código` soltada. |
| `kbd.port([n])` | número | Puerto de mando del teclado (1 por defecto); cambiarlo empieza de nuevo. |
| `kbd.capslock()`, `kbd.connected()` | booleano | Estado de Bloq Mayús; dispositivo conectado. |
| `kbd.clear()` | nil | Descarta los eventos no leídos. |

*Ratón* (dispositivo v32mouse) — [detalles](#ratón-mouse--mouse)

| Llamada | Devuelve | Qué hace |
|---|---|---|
| `mouse()` | x, y, left, middle, right, scrollx, scrolly | Puntero (píxeles de pantalla) y botones (booleanos), como el de TIC-80; el desplazamiento es siempre 0. |
| `mouse.pressed([b])`, `mouse.released([b])` | booleano | Un botón de `b` (1 izquierdo, 2 derecho, 4 central; sumas; ninguno: cualquiera) se pulsó / soltó en este cuadro. |
| `mouse.buttons()` | número | Botones pulsados, 1 + 2 + 4. |
| `mouse.delta()` | dx, dy | El movimiento de este cuadro, en píxeles. |
| `mouse.position([x, y])` | x, y | El puntero; lo mueve si se dan valores. |
| `mouse.bounds(x1, y1, x2, y2)` | nil | Zona en la que se queda el puntero (por defecto, la pantalla). |
| `mouse.scale([n])`, `mouse.port([n])` | número | Píxeles por paso (2 por defecto); puerto de mando (3 por defecto). |
| `mouse.connected()` | booleano | Dispositivo conectado. |

*Sonido* — [detalles](#sonido-music--sfx)

| Llamada | Devuelve | Qué hace |
|---|---|---|
| `music.play(snd [, ch [, loop [, vol [, start]]]])` | canal | Reproduce un sonido, en el canal 0 por defecto. |
| `music.pause([ch])`, `music.resume([ch])`, `music.stop([ch])` | nil | Control del canal. |
| `music.playing([ch])` | booleano | Si el canal se está reproduciendo. |
| `music.volume(vol [, ch])` | nil | Volumen del canal. |
| `sfx.play(snd [, ch [, vol [, speed]]])` | canal | Reproduce un efecto en el siguiente de los canales 1–15. |
| `sfx.stop([ch])`, `sfx.volume(vol [, ch])` | nil | Detiene los efectos (canales 1–15), establece el volumen. |
| `ioports.spu.cmd(mode)` (o `.command`) | nil | Comando SPU en bruto sobre el canal seleccionado. [Detalles](#ioportsspucmd--la-vía-de-escape-en-bruto) |

*Mapas de mosaicos, tarjeta de memoria, sistema*

| Llamada | Devuelve | Qué hace |
|---|---|---|
| `tilemap.get(MAP, x, y)` | número / nil | Mosaico en `x, y` de un `--#tilemap`. [Detalles](#mapa-de-mosaicos-tilemap) |
| `tilemap.set(MAP, x, y, v)` | v | Cambia un mosaico (el mapa se copia a RAM en la primera escritura). |
| `tilemap.render(MAP, sx, sy, w, h, x, y, tw, th [, skip])` | nil | Dibuja un bloque de mosaicos. |
| `memcard.save(v [, pos])`, `memcard.load([pos])` | v | Lee/escribe una palabra en la tarjeta de memoria. [Detalles](#tarjeta-de-memoria-memcard) |
| `memcard.load_table(pos)` | tabla / nil | Carga una tabla guardada con `memcard.save(t)`. |
| `memcard.title(str)` | nil | Establece el título de guardado de la tarjeta. |
| `memcard[pos]`, `memcard[pos] = v` | | Igual que `load` / `save`. |
| `system.wait()` / `system.halt()` | nil | `WAIT` hasta el siguiente cuadro / `HLT`. [Detalles](#sistema-system) |
| `system.date()` / `system.time()` | cadena, 3 números | `"YYYY-MM-DD", a, m, d` / `"HH:MM:SS", h, m, s`. |
| `system.frames()` / `system.cycles()` | número | Cuadros desde el encendido / ciclos de CPU en el cuadro actual (también sin `()`). |

*Lenguaje y ensamblador en línea*

| Llamada | Qué hace |
|---|---|
| `tostring(v)`, `tonumber(s [, base])`, `type(v)` | Como en Lua. |
| `pairs(t)`, `ipairs(t)` | Iteradores para `for k, v in …`. |
| `setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawlen`, `rawequal` | Metatablas: `__index`, `__newindex`, `__call`, `__tostring`, `__len`, `__metatable`. |
| `__asm__("…")` | Ensamblador en línea con sustitución `{var}`; los registros y la pila se guardan a su alrededor. |
| `__rawasm__("…")` | Ensamblador copiado tal cual en la salida. |

`print` e `ioports.*` son nombres del modo nativo; bajo `--#api pico8` o
`--#api tic80`, `print`, `spr`, `btn`, etc. son en su lugar las funciones
de esa consola (ver [PICO8.md](PICO8.md) y [TIC80.md](TIC80.md)).
No disponibles: `printf`, `pcall`/`error`/`assert`, `select`, `next`,
`string.match`/`gmatch`, `os.*`, `io.*`, `coroutine.*`.

<a id="ioports--every-hardware-port"></a>
### ioports.\* — todos los puertos de hardware

Cada propiedad lee o escribe directamente un puerto de E/S de Vircon32
(`IN`/`OUT`), sin consultar ninguna tabla. Tipos:

* **int** — un número entero. Leer da un número de Lua; escribir un
  número lo trunca hacia cero (`CFI`). Un literal numérico se escribe en
  cambio como la palabra exacta de 32 bits, así que
  `ioports.gpu.bgcolor = 0xFF003366` e `ioports.gpu.x = -5` guardan
  ambos lo que escribiste (ver
  [Puertos enteros y literales](#integer-ports-and-literals)).
* **float** — un número de Lua, guardado tal cual.
* **bool** — un booleano de Lua: las lecturas dan `true`/`false`, las
  escrituras evalúan la veracidad (truthiness) de Lua. Ver
  [Puertos de E/S booleanos](#puertos-de-es-booleanos).
* **color** — un puerto int que contiene una palabra empaquetada
  `0xAABBGGRR`. Escribe un literal, `rgba()`, `color()` o `hex()`; un
  número en tiempo de ejecución se convierte a entero, que no son los
  mismos bits.

L = lectura, E = escritura.

**ioports.gpu.\* — gráficos**

| Propiedad | Puerto | Acceso | Tipo | Significado |
|---|---|---|---|---|
| `ioports.gpu.texture` | `GPU_SelectedTexture` | L/E | int | Textura que usan la configuración de regiones y los dibujos (nombres de `--#texture`, o -1 para la textura de la BIOS). |
| `ioports.gpu.region` | `GPU_SelectedRegion` | L/E | int | Región (0–4095) de la textura seleccionada que se define o dibuja. |
| `ioports.gpu.minX`, `minY` | `GPU_RegionMinX/Y` | L/E | int | Esquina superior-izquierda de la región, en píxeles de textura. Escribir uno también pone `hotX`/`hotY` al mismo valor. |
| `ioports.gpu.maxX`, `maxY` | `GPU_RegionMaxX/Y` | L/E | int | Esquina inferior-derecha de la región (inclusive). |
| `ioports.gpu.hotX`, `hotY` | `GPU_RegionHotSpotX/Y` | L/E | int | Hotspot de la región: el punto que se coloca en `gpu.x, gpu.y`. Se establece después de `minX/minY`. |
| `ioports.gpu.x`, `y` | `GPU_DrawingPointX/Y` | L/E | int | Posición en pantalla del siguiente dibujo. |
| `ioports.gpu.scaleX`, `scaleY` | `GPU_DrawingScaleX/Y` | L/E | float | Escala de los dibujos escalados. |
| `ioports.gpu.angle` | `GPU_DrawingAngle` | L/E | float | Ángulo de los dibujos rotados, en radianes. |
| `ioports.gpu.bgcolor` | `GPU_ClearColor` | L/E | color | Color que usa `clear()`. |
| `ioports.gpu.multiply` | `GPU_MultiplyColor` | L/E | color | Color por el que se multiplica cada dibujo (`0xFFFFFFFF` = sin cambio). |
| `ioports.gpu.blending` | `GPU_ActiveBlending` | L/E | int | Número del modo de mezcla (alpha `0x20`, add `0x21`, subtract `0x22`); o llama a `ioports.gpu.blending("add")`. |
| `ioports.gpu.pixels` | `GPU_RemainingPixels` | L | int | Píxeles que la GPU aún puede dibujar en este cuadro. |

Métodos: `ioports.gpu.clear()`, `ioports.gpu.draw()`,
`ioports.gpu.blending()`, `ioports.gpu.sync()` (ver la tabla de arriba).

**ioports.inp.\* — mandos**

| Propiedad | Puerto | Acceso | Tipo | Significado |
|---|---|---|---|---|
| `ioports.inp.gamepad` | `INP_SelectedGamepad` | L/E | int | Mando (0–3) que leen las demás propiedades. Al leerlo da el último valor asignado (los emuladores no pueden releer este puerto; ver [El puerto de mando](#teclado-key--keyp--kbd)). |
| `ioports.inp.status` | `INP_GamepadConnected` | L | bool | Si el mando seleccionado está conectado. |
| `ioports.inp.left`, `right`, `up`, `down` | `INP_GamepadLeft/…` | L | int | Cruceta: cuadros mantenido (> 0) o cuadros desde que se soltó (< 0). |
| `ioports.inp.A`, `B`, `X`, `Y`, `L`, `R`, `START` | `INP_GamepadButton*` | L | int | Botones, misma codificación. |
| `ioports.inp.inputs` | (todos los anteriores) | L | int | Todos los botones del mando seleccionado en una máscara de bits, presionado = 1: bit 10 izquierda, 9 derecha, 8 arriba, 7 abajo, 6 START, 5 A, 4 B, 3 X, 2 Y, 1 L, 0 R. |

**ioports.spu.\* — sonido**

| Propiedad | Puerto | Acceso | Tipo | Significado |
|---|---|---|---|---|
| `ioports.spu.volume` | `SPU_GlobalVolume` | L/E | float | Volumen general. |
| `ioports.spu.channel` | `SPU_SelectedChannel` | L/E | int | Canal (0–15) sobre el que actúan las propiedades `chan*` y `cmd()`. |
| `ioports.spu.sound` | `SPU_SelectedSound` | L/E | int | Sonido (nombre de `--#sound`) sobre el que actúan las propiedades de sonido. |
| `ioports.spu.length` | `SPU_SoundLength` | L | int | Longitud del sonido seleccionado, en muestras. |
| `ioports.spu.soundloop` | `SPU_SoundPlayWithLoop` | L/E | bool | El sonido seleccionado hace bucle por defecto. |
| `ioports.spu.loopstart`, `loopend` | `SPU_SoundLoopStart/End` | L/E | int | Puntos de bucle del sonido seleccionado, en muestras. |
| `ioports.spu.state` | `SPU_ChannelState` | L | int | Canal seleccionado: 0x40 detenido, 0x41 en pausa, 0x42 reproduciendo. |
| `ioports.spu.chansound` | `SPU_ChannelAssignedSound` | L/E | int | Sonido asignado al canal seleccionado. |
| `ioports.spu.chanvolume` | `SPU_ChannelVolume` | L/E | float | Volumen del canal. |
| `ioports.spu.chanspeed` | `SPU_ChannelSpeed` | L/E | float | Velocidad de reproducción del canal (1.0 = normal). |
| `ioports.spu.chanloop` | `SPU_ChannelLoopEnabled` | L/E | bool | El canal hace bucle. Se establece **después de** `cmd("play")`. |
| `ioports.spu.chanpos` | `SPU_ChannelPosition` | L/E | int | Posición de reproducción del canal, en muestras. |

Método: `ioports.spu.cmd(mode)` / `ioports.spu.command(mode)` —
`"play"`, `"pause"`, `"stop"`, `"resume"`, `"pauseall"`, `"stopall"`,
`"resumeall"`.

**ioports.tim.\*, rng, car, mem — temporizador, números aleatorios, cartucho, tarjeta de memoria**

| Propiedad | Puerto | Acceso | Tipo | Significado |
|---|---|---|---|---|
| `ioports.tim.date` | `TIM_CurrentDate` | L | int | Año × 65536 + día del año (`system.date()` lo decodifica). |
| `ioports.tim.time` | `TIM_CurrentTime` | L | int | Segundos desde la medianoche (`system.time()` lo decodifica). |
| `ioports.tim.frames` | `TIM_FrameCounter` | L | int | Cuadros desde el encendido (= `system.frames`). |
| `ioports.tim.cycles` | `TIM_CycleCounter` | L | int | Ciclos de CPU en este cuadro (= `system.cycles`). |
| `ioports.rng.value` | `RNG_CurrentValue` | L | int | Siguiente número aleatorio del hardware. |
| `ioports.rng.seed` | `RNG_CurrentValue` | E | int | Siembra el generador del hardware. |
| `ioports.car.connected` | `CAR_Connected` | L | bool | Hay un cartucho insertado. |
| `ioports.car.romsize` | `CAR_ProgramROMSize` | L | int | Tamaño de la ROM de programa, en palabras. |
| `ioports.car.numvtex`, `numvsnd` | `CAR_NumberOfTextures/Sounds` | L | int | Texturas / sonidos del cartucho. |
| `ioports.mem.connected` | `MEM_Connected` | L | bool | Hay una tarjeta de memoria insertada. |

Escribir en un puerto de solo lectura, leer uno de solo escritura, o un
nombre desconocido (`ioports.gpu.colour`) es un error de compilación que
lista los nombres válidos.

<a id="standard-library"></a>
### Biblioteca estándar

| Biblioteca | Funciones |
|---|---|
| `math` | `abs acos asin atan atan2 ceil cos cosh deg exp floor fmod frexp ldexp log log10 max min modf pow rad random randomseed sin sinh sqrt tan tanh`, constantes `pi huge e` |
| `string` | `byte char find format gsub len lower rep reverse sub upper` (también como métodos: `s:sub(1, 3)`) |
| `table` | `concat insert move pack remove sort unpack` |
| operadores | `+ - * / % ^ //`, `..`, `#`, `== ~= < > <= >=`, `and or not`, `& | ~ << >>` (ver el README) |

Los números son float32 (24 bits significativos); las cadenas que parecen
números se convierten en la aritmética (`"5" + 1` es 6), como en Lua.

---

## Sonido: music.\* / sfx.\*

```
music.play(SOUND [, CHANNEL [, LOOP [, VOL [, START]]]])  -> canal usado
music.pause  ([CHANNEL])
music.resume ([CHANNEL])
music.stop   ([CHANNEL])
music.playing([CHANNEL])                                  -> booleano
music.volume (VOL [, CHANNEL])

sfx.play(SOUND [, CHANNEL [, VOL [, SPEED]]])             -> canal usado
sfx.stop([CHANNEL])
sfx.volume(VOL [, CHANNEL])

ioports.spu.cmd(MODE)   -- vía de escape en bruto, ver abajo
```

`music` usa por defecto el canal 0. `sfx.play()` sin canal rota de forma
cíclica (round-robin) sobre los canales 1–15 mediante una palabra de RAM
reservada por el compilador (`VIRCON32_SFX_CURSOR`), de modo que un efecto
nunca corta la música. `sfx` nunca hace bucle: cualquier cosa sostenida es
`music.play(..., true)` en su propio canal.

`sfx.stop()` sin canal detiene únicamente los canales 1–15, deliberadamente
NO `StopAllChannels`, lo cual silenciaría también la música. Eso es
`__builtin_vircon32_sfx_stop_all`.

El cursor avanza incondicionalmente en lugar de buscar un canal inactivo:
buscar costaría hasta 15 `IN` + comparaciones en la ruta caliente
(`sfx.play()` se ejecuta en cada salto y cada paso) para protegerse contra
un caso que solo surge cuando se solapan 15 efectos, donde el más antiguo
es de todos modos el correcto para perder.

**Vircon32 SPU: el orden de escritura de puertos**

*La regla*

```asm
OUT SPU_SelectedChannel, ch
OUT SPU_Command, SPUCommand_StopSelectedChannel   ; 1
OUT SPU_ChannelAssignedSound, snd
OUT SPU_ChannelVolume, R                          ; puerto flotante
OUT SPU_Command, SPUCommand_PlaySelectedChannel
OUT SPU_ChannelLoopEnabled, 0|1                   ; 2 - DESPUÉS del comando
OUT SPU_ChannelPosition, samples                  ; 3 - DESPUÉS del comando
```

Tres comportamientos de la consola imponen esto. Los tres fallan **de forma
silenciosa** — sin error, sin rechazo de la escritura del puerto, solo el
sonido equivocado.

**1. Un sonido solo se asigna a un canal DETENIDO.**
**2 y 3. El comando de reproducción sobrescribe el bucle Y la posición.**

Una bandera de bucle o un seek escrito *antes* del comando se descarta.
Nótese que la bandera de bucle es reemplazada por el `PlayWithLoop` del
SONIDO, que es falso a menos que algo haya establecido
`SPU_SoundPlayWithLoop` en ese sonido — así que el bucle a nivel de canal
solo funciona si se escribe después del comando. Escríbelo incluso cuando
sea 0, ya que el comando acaba de reemplazarlo con la bandera del sonido.

Para un canal **En Pausa (Paused)**, `PlayChannel()` no toma ninguna de las
dos ramas — solo establece `State = Playing`. Eso es lo que hace que Play
sea el resume correcto por canal, y por qué resume nunca perturba la
posición o el bucle.

*Estados de canal y qué significa realmente resume*

`channel_stopped 0x40`, `channel_paused 0x41`, `channel_playing 0x42`.
`SPU_ChannelState` es **de solo lectura** (`WriteSPUChannelState` devuelve
falso).

No existe un comando `ResumeSelectedChannel`. `ResumeAllChannels` es
literalmente un bucle que llama a `PlayChannel()` en cada canal en pausa,
así que `resume(ch)` = `PlaySelectedChannel` es el equivalente correcto por
canal.

**Un "resume" que reinicia desde el principio significa que el canal
estaba DETENIDO, no en pausa.** Esa es la firma diagnóstica de una bandera
de bucle perdida: el sonido llegó a su fin, el canal pasó a Detenido, y
Play lo rebobinó.

`PauseChannel()` establece `State = Paused` incondicionalmente — *no*
comprueba si el canal ya está detenido, a pesar de que la documentación de
la API en C dice que pausar "no tiene efecto si ya está detenido". Así que
pausar un canal terminado lo deja En Pausa en la posición 0, y un resume
posterior reproduce desde el inicio. Protégete con una comprobación
`SPU_ChannelState == 0x42` si eso importa.

*Tipos de puerto*

`SPU_ChannelPosition` es un puerto **ENTERO** — un índice de muestra,
acotado por la consola a `0 .. SoundLength-1`. `audio.h` declara
`set_channel_position( int )`, y `WriteSPUChannelPosition()` lee
`Value.AsInteger`. La tabla IOPortMap tenía `ioports.spu.chanpos` como
`IOPORT_TYPE_FLOAT`, lo cual escribía patrones de bits de flotante en
bruto en él; corregido a `IOPORT_TYPE_INTEGER`.

Puertos genuinamente flotantes: `SPU_ChannelVolume` (acotado 0–8),
`SPU_ChannelSpeed` (0–128, cambia el tono), `SPU_GlobalVolume` (acotado
0–2). Las escrituras de NaN/inf en cualquiera de estos se ignoran en lugar
de rechazarse.

**music.volume(VOL [, CHANNEL]) / sfx.volume(VOL [, CHANNEL])**

Establece el volumen de reproducción. `VOL` es obligatorio. `CHANNEL`
tiene **tres** significados distintos según lo que escriba el sitio de
llamada:

| Llamada | Significado |
|---|---|
| `music.volume(VOL)` | aplica `VOL` a cada canal que **este espacio de nombres posee actualmente** (ver seguimiento de propiedad de canal, abajo) |
| `music.volume(VOL, -1)` | el volumen **global** real del hardware (`SPU_GlobalVolume`, acotado 0–2) — cada canal, incondicionalmente |
| `music.volume(VOL, N)` | el volumen de ese canal específico (`SPU_ChannelVolume`, acotado 0–8), `N` entre 0–15 |

`sfx.volume` se comporta de forma idéntica, contra los propios canales
rastreados de `sfx`.

```lua
music.play(MUSIC, 0, true)   -- reclama el canal 0 para la música
sfx.play(BLIP)                -- reclama algún canal 1-15 para el sfx

sfx.volume(0.3)               -- atenúa SOLO el/los canal(es) sfx de arriba;
                               -- el canal 0 (música) no se toca
music.volume(0.5)             -- baja la música; el sfx no se toca
music.volume(1.0, 0)          -- canal 0 específicamente, volumen total
sfx.volume(0.0, -1)           -- silencio global real, ambos espacios de nombres
```

Los números de canal explícitos (`N` o `-1`) nunca cambian la propiedad —
solo `.play()` hace eso. Un canal en pausa o detenido sigue siendo
encontrado por el modo "canales rastreados" sin argumentos; solo reproducir
un canal *diferente* bajo el otro espacio de nombres lo libera.

*Seguimiento de propiedad de canal*

Dos palabras de RAM reservadas por el compilador, `VIRCON32_MUSIC_CHANNEL_MASK`
y `VIRCON32_SFX_CHANNEL_MASK`, cada una una máscara de bits sobre los
canales 0–15: el bit *N* activado significa que al canal *N* se le asignó
por última vez un sonido mediante el `.play()` de ese espacio de nombres.
La propiedad es exclusiva por construcción — cada `music.play(S, ch)`
reclama `ch` para música y lo limpia de la máscara de sfx, y cada
`sfx.play(S, ch)` hace lo inverso — ya que un canal en realidad no
pertenece a ninguno de los dos espacios de nombres a nivel de hardware,
solo por convención en cómo las llamadas `.play()` del juego lo han estado
usando. Ambas máscaras comienzan en 0 (nada reclamado);
`music.volume(VOL)`/`sfx.volume(VOL)` sin canal es un no-op hasta que algo
haya reproducido realmente en ese espacio de nombres.

Solo `.play()` toca las máscaras. `.pause()`, `.resume()`, `.stop()`, y
`.volume()` mismo nunca lo hacen — así que un canal que está actualmente
en pausa o detenido sigue siendo "propiedad" de quien reprodujo por última
vez en él, y sigue siendo captado por el modo de volumen sin argumentos.

*Generación de código*

Una llamada totalmente literal (`music.volume(0.5, 0)`, `sfx.volume(0.0, -1)`)
se pliega en una secuencia lineal de `OUT` en tiempo de compilación, igual
que el resto de esta superficie. `music.volume(VOL)`/`sfx.volume(VOL)` sin
argumento de canal es **siempre** un `CALL` — qué canales están actualmente
en propiedad solo se sabe en tiempo de ejecución — a
`__builtin_vircon32_volume_mask`, que recorre los bits 0–15 de la máscara
del espacio de nombres y escribe `SPU_ChannelVolume` para cada uno que esté
activado. Cualquier otra llamada con valor en tiempo de ejecución va a
`__builtin_vircon32_volume`, que comprueba el valor del canal contra `-1`
(global) en tiempo de ejecución y acota en caso contrario.

**Por qué desaparecieron los nombres simples**

`play` / `pause` / `resume` / `stop` eran los cuatro identificadores más
propensos a colisión que un juego podría querer para sí mismo, que es lo
que la antigua salvaguarda de desvío `resolve_symbol()` en el despachador
solucionaba. Han desaparecido; los espacios de nombres los reemplazan, y el
mecanismo de alias los restaura por elección en lugar de por defecto.

**Alias en tiempo de compilación**

`play = music.play` registra un alias y no emite nada. Las llamadas
posteriores a `play(...)` compilan a la secuencia `OUT` en línea idéntica —
sin valor en tiempo de ejecución, sin CALL, sin RAM. La superficie
que admite alias es `music.play`, `music.pause`, `music.resume`,
`music.stop`, `music.playing`, `music.volume`, `sfx.play`, `sfx.stop`, y
`sfx.volume`.

- `register_intrinsic_aliases_prepass()` se ejecuta antes de la generación
  de código, así que un alias declarado al final de un archivo gobierna una
  llamada al principio.
- La resolución ocurre en `try_emit_call_intrinsic()` inmediatamente
  después de `resolve_static_path()`, así que una llamada con alias es
  indistinguible de la ruta real en todo lo que sigue.
- `node_multiple_assignment()` no emite nada para una declaración de alias;
  `node_identifier()` produce un error si uno se lee como un valor.

Límites, todos ellos deliberados:

- Un alias es un NOMBRE, no un VALOR. `{ hit = sfx.play }` o pasarlo a una
  función es un error de compilación que nombra la limitación, no una mala
  compilación.
- Los alias son de ámbito de todo el programa. `local p = music.play`
  compila pero advierte — el `local` no lo delimita.
- No se admite el alias de espacios de nombres (`m = music` y luego
  `m.play()`).
- Los objetivos de alias siguen consumiendo una palabra de RAM global, ya
  que `register_all_globals_prepass` los ve como objetivos de asignación.
  Una palabra cada uno; no vale la pena desestabilizar la tabla de símbolos
  por esto.

Si alguna vez se desean valores de función de sonido de primera clase, el
precedente es `__mathfn_sin` / `__mathfn_log` en runtime.s — etiquetas
reales empaquetadas con `BOXED_FUNCTION`, resueltas en
`try_emit_table_get_intrinsic()` donde `math.sin` como valor ya existe. Eso
sería aditivo; la tabla de alias permanece como la ruta de costo cero.

**music.playing() y por qué una bandera de Lua es el interruptor equivocado**

`SPU_ChannelState` es un puerto entero de solo lectura que devuelve
`channel_stopped` 0x40, `channel_paused` 0x41, `channel_playing` 0x42.
`music.playing(ch)` selecciona el canal, lo lee, y devuelve un booleano de
Lua real.

Un interruptor de pausa/resume construido sobre una bandera de Lua se
desincroniza en el momento en que un sonido termina por sí solo: el
programa todavía cree que se está reproduciendo, así que la siguiente
pulsación pausa un canal ya detenido en lugar de reanudarlo. Preguntarle al
hardware no puede desincronizarse.

**Generación de código: plegado híbrido**

Todos los argumentos conocidos en tiempo de compilación → secuencia lineal
de `OUT`, sin CALL. Cualquier cosa dinámica → empuja y hace CALL a la
rutina en tiempo de ejecución, que hace el establecimiento de valor por
defecto para nil, la decodificación de veracidad (truthiness) de Lua, y la
acotación de canal. Todo o nada: un solo argumento dinámico envía toda la
llamada por la ruta en tiempo de ejecución.

`sfx.play()` además requiere un canal *literal explícito* para poder
plegarse, ya que la ruta automática debe leer y avanzar el cursor.
`sfx.play(BLIP)` — la forma común — es por lo tanto siempre un CALL, que
también es la emisión más pequeña.

Los nombres de `--#sound` cuentan como conocidos en tiempo de compilación:
`node_cart_hint()` ya le asigna a `MUSIC` su id de recurso, así que
`music.play(MUSIC, 0)` emite `OUT SPU_ChannelAssignedSound, 0` en lugar de
leer la global de RAM. El plegado se suprime cuando `spu_name_is_rebound()`
encuentra que el nombre fue asignado, usado como variable de bucle,
declarado como parámetro, o mencionado en ensamblador en línea en
cualquier parte del AST.

---

## ioports.spu.cmd() — la vía de escape en bruto

Emite un comando SPU en bruto contra lo que sea que `SPU_SelectedChannel`
nombre actualmente. Sin selección de canal, sin asignación de sonido, sin
valores por defecto — combínalo con las propiedades `ioports.spu.*` para
secuencias que los intrínsecos no cubren (crossfades, búsqueda precisa por
muestra, puntos de bucle personalizados).

Lleva las mismas restricciones de orden de puertos que todo lo demás:
establece `chanloop` **después de** `cmd("play")`, nunca antes.

Modos: `"play"` 0, `"pause"` 1, `"stop"` 2, `"pauseall"` 3, `"resume"` 4,
`"allstop"` 5, más los alias `"resumeall"` y `"stopall"`. Omitido o nil →
`"play"`.

---

## Puertos de E/S booleanos

Un booleano de Lua no es un flotante. `true`/`false`/`nil` son patrones de
bits empaquetados en NaN; los puertos de hardware trafican en enteros 0 y
1. Las escrituras decodifican la veracidad (truthiness) de Lua (solo `nil`
y `false` son falsos), con literales que se pliegan a un inmediato 0/1 en
bruto. Las lecturas ramifican hacia `BOXED_TRUE`/`BOXED_FALSE`.

Afecta a `ioports.spu.chanloop`, `ioports.spu.soundloop`,
`ioports.inp.status`, `ioports.car.connected`, `ioports.mem.connected`.

Los puertos booleanos devuelven `true`/`false`, no `1.0`/`0.0`. La
aritmética sobre uno de ellos necesita reescribirse como
`if p then 1 else 0`.

---

## Sistema: system.\*

```
system.wait()   -> nil   (WAIT hasta la siguiente señal de nuevo ciclo)
system.halt()   -> nil   (HLT -- detiene la CPU)
system.date()   -> cadena, año, mes, día
system.time()   -> cadena, hora, minuto, segundo
```

**system.wait() / system.halt()**

`system.wait()` compila directamente a `WAIT` — la misma instrucción que
usa `ioports.gpu.sync()`, e intercambiable con ella; ambas simplemente
esperan la siguiente señal de nuevo ciclo del temporizador. `system.halt()`
compila a `HLT`, deteniendo la CPU por completo — para un programa que ha
completado su trabajo y no le queda nada por renderizar.

**system.date() / system.time()**

Ambas decodifican el reloj de tiempo real del chip temporizador (ver la
Especificación del Sistema Vircon32, Parte 7, sección 1.2 — esto es un
reloj de pared/RTC real, no un contador monótono desde el arranque) y
devuelven **cuatro** valores: una cadena formateada, seguida de los tres
componentes numéricos.

```lua
local date_str, year, month, day     = system.date()   -- "2026-09-06", 2026, 9, 6
local time_str, hour, minute, second = system.time()    -- "03:00:04", 3, 0, 4
```

La cadena de `system.date()` es `"AAAA-MM-DD"`; la de `system.time()` es
`"HH:MM:SS"`. Ambas siempre se rellenan con ceros a un ancho fijo
(`printf` con `%0*d`, no un límite estricto) — `year` se rellena a 4
dígitos pero nunca se trunca, así que un año más allá de 9999 (hasta el
máximo de hardware de `CurrentYear`, 65535) todavía se imprime completo,
solo que más ancho de 4 caracteres; mes/día/hora/minuto/segundo siempre
tienen exactamente 2 dígitos. Los años bisiestos usan la regla gregoriana
estándar (divisible entre 4, excepto los siglos a menos que sean
divisibles entre 400) — la especificación confirma que el rango de
conteo de días se extiende a 365 en un año bisiesto pero no define la
regla en sí, así que esta es la única lectura sensata y universal de
ella. No hay soporte de cadena de formato ni construcción de tablas al
estilo `os.time()`/`os.date()` — esto es una decodificación de forma fija
del registro de hardware, no una biblioteca de fechas general.

**system.frames / system.cycles**

```lua
local f = system.frames()   -- TIM_FrameCounter -- cuadros desde el encendido
local c = system.cycles()   -- TIM_CycleCounter -- ciclos de CPU desde que empezó este cuadro
```

Ambos son contadores de hardware de solo lectura, y ninguno es tiempo de
reloj de pared. `system.frames()` cuenta los cuadros desde el encendido;
`system.cycles()` cuenta los ciclos de CPU desde que empezó el cuadro
actual y vuelve a 0 en cada cuadro, así que leerlo justo antes de
`system.wait()` muestra cuánto del presupuesto de CPU del cuadro se ha
usado. `system.frames()` es el ajuste natural para
temporización del tipo "cada N cuadros, haz X" (esto es exactamente lo que
usa la demo de desplazamiento del mapa de mosaicos para marcar el ritmo de
su velocidad de desplazamiento) ya que se ejecuta libremente sin importar
lo que haga el programa, a diferencia de una variable contadora hecha a
mano que hay que recordar e incrementar cada cuadro. Ambos también son
accesibles como puertos en bruto (`ioports.tim.frames`,
`ioports.tim.cycles`) — ver [Otros puertos de E/S en bruto](#otros-puertos-de-es-en-bruto)
— los nombres `system.*` son idénticos, solo que bajo el espacio de
nombres más fácil de descubrir.

---

## Gráficos: spr()

```
spr(region_id, x, y [, scale_x [, scale_y [, angle_deg [, color_mult [, blend_mode]]]]])
```

Dibuja la región de textura `region_id` de la GPU (según la declara una
pista `--#texture`, o un índice de región en bruto) en la posición de
píxel `(x, y)`.

| Argumento | Por defecto | Notas |
|---|---|---|
| `region_id` | obligatorio | índice de región de la GPU (`GPU_SelectedRegion`) |
| `x`, `y` | obligatorios | posición de dibujo superior-izquierda, `GPU_DrawingPointX/Y` |
| `scale_x`, `scale_y` | `1.0` | factores de escala X/Y independientes |
| `angle_deg` | `0` | rotación, en **grados**, sentido antihorario; convertido internamente a radianes (el `GPU_DrawingAngle` de la consola está en radianes) |
| `color_mult` | `0xFFFFFFFF` | color de multiplicación RGBA empaquetado — `0xFFFFFFFF` es "sin cambio" |
| `blend_mode` | `"alpha"` (`0x20`) | una cadena con el nombre del modo o su valor numérico — ver los modos de mezcla abajo |

Un argumento puede **omitirse** (simplemente dejar de suministrar
argumentos finales) o pasarse como un **`nil` explícito** para saltarlo y
llegar a uno posterior — `spr(id, x, y, nil, nil, 45)` para rotar sin
tocar la escala — ambos significan "usa el valor por defecto."

Modos de mezcla — pasa la cadena con el nombre o el número:

| Cadena | Número | Efecto |
|---|---|---|
| `"alpha"` o `"default"` | `0x20` | mezcla alfa normal (el valor por defecto) |
| `"add"` | `0x21` | aditiva — aclara lo que hay debajo |
| `"subtract"` | `0x22` | sustractiva — oscurece lo que hay debajo |

```lua
spr(7, 100, 80, nil, nil, nil, nil, "add")       -- efecto de brillo / luz
spr(7, 100, 80, nil, nil, nil, nil, 0x21)        -- lo mismo, numérico
spr(7, 100, 80, nil, nil, nil, 0x80FFFFFF, "alpha")
```

La cadena del modo debe ser un **literal de cadena**; se resuelve a su
número en tiempo de compilación, y cualquier otra cadena (`"multiply"`,
una errata) es un error de compilación. Una cadena guardada en una
variable no se reconoce (no hay despacho de cadenas en tiempo de
ejecución — llegaría a la GPU como un puntero, no como un modo); guarda el
modo en una variable como número (`local mode = 0x21`). Los números se
pasan tal cual, como antes.

`spr()` no devuelve nada (`nil` de Lua), a la par de que la consola no
tiene ningún valor significativo que devolver de una llamada de dibujo.
Más de 8 argumentos es una advertencia en tiempo de compilación; los
extras se ignoran.

**Despacho en tiempo de ejecución, no plegado en tiempo de compilación**

A diferencia de la API de sonido, `spr()` siempre llama a
`__builtin_vircon32_spr` — no hay una ruta rápida de `OUT` lineal para una
llamada totalmente literal. La rutina lee los valores reales en tiempo de
ejecución de `scale_x`/`scale_y`/`angle_deg` en *cada* llamada y elige el
más barato de los cuatro comandos de dibujo de la GPU cada vez:

| Condición | Comando |
|---|---|
| escala = 1,1 y ángulo = 0 | `GPUCommand_DrawRegion` |
| escala ≠ 1 y ángulo = 0 | `GPUCommand_DrawRegionZoomed` |
| escala = 1,1 y ángulo ≠ 0 | `GPUCommand_DrawRegionRotated` |
| escala ≠ 1 y ángulo ≠ 0 | `GPUCommand_DrawRegionRotozoomed` |

`color_mult` y `blend_mode` se escriben incondicionalmente en cada
llamada, antes de ese despacho — `GPU_MultiplyColor` y
`GPU_ActiveBlending` son estado persistente de la GPU que cada variante de
dibujo consulta, a diferencia de `GPU_DrawingScaleX/Y`/`GPU_DrawingAngle`,
que solo se escriben en las ramas que realmente los usan (inofensivo
dejarlos obsoletos, ya que por ejemplo `DrawRegionRotated` está definido
para ignorar la escala por completo).

`color_mult` es una palabra empaquetada `0xAABBGGRR` y se escribe en
`GPU_MultiplyColor` tal cual, sin conversión de flotante a entero (el
mismo modelo que `ioports.gpu.clear(color)`). Un literal numérico
(`0xFFFFFFFF`, `0x80FFFFFF`, `-1`) se convierte en esa palabra al compilar.
Cualquier otra expresión debe contener ya la palabra empaquetada:
`rgba(r, g, b [, a])` (ver [Colores: rgba()](#colors-rgba)),
`hex("0xFF8080FF")`, o una variable asignada desde uno de ellos. Un número
calculado en tiempo de ejecución *no* se convierte — un float32 no puede
representar exactamente un color de 32 bits. Para un color que cambia en
ejecución (un fundido), guarda los componentes como números y empaquétalos
al dibujar:

```lua
spr(REGION_SOLID, x, y, w, h, 0, rgba(0, 0, 0, frame * 8))   -- fundido a negro
```

Un `nil` pasado explícitamente para un argumento opcional (por ejemplo,
`spr(id, x, y, nil, nil, 45)`) se trata idénticamente a que ese argumento
esté completamente omitido — ambos recurren al valor por defecto. Una
llamada situada en un contexto de expresión (`local unused = spr(1, 10, 10)`)
recibe correctamente `nil` asignado, igual que cualquier otro intrínseco
en este archivo.

<a id="gpu-clear"></a>
**ioports.gpu.clear([color]) / ioports.gpu.clear(r, g, b [, a])**

Limpia la pantalla: escribe `GPU_ClearColor` (si se da un color) y luego
emite `GPUCommand_ClearScreen`. Omite los argumentos para limpiar con lo
que `GPU_ClearColor` contenga actualmente. El color puede darse de cuatro
formas:

| Forma | Ejemplo | Notas |
|---|---|---|
| nombre preestablecido | `clear("black")` | `"black"`, `"white"`, `"blue"`, `"red"`, `"green"` — literal de cadena, resuelto en tiempo de compilación; cualquier otro nombre es un error de compilación |
| literal empaquetado | `clear(0xFF202020)` | `0xAABBGGRR`; se pliega en tiempo de compilación a la palabra cruda de 32 bits |
| palabra empaquetada | `clear(rgba(32, 32, 32))`, `clear(hex("0xFF202020"))`, `clear(c)` | un valor no literal se escribe al puerto sin tocar, así que ya debe contener la palabra cruda — es decir, venir de `rgba()` o de `hex()` |
| componentes | `clear(32, 32, 32)`, `clear(r, g, b, 128)` | rojo, verde, azul, alfa, cada uno `0`–`255`; alfa es opcional y por defecto vale `255` (opaco) |

```lua
ioports.gpu.clear("black")
ioports.gpu.clear(0xFF202020)       -- 0xAABBGGRR empaquetado, gris oscuro
ioports.gpu.clear(32, 32, 32)       -- el mismo gris oscuro, por componentes
ioports.gpu.clear(r, g, b)          -- también con variables; alfa = 255
ioports.gpu.clear(0, 0, 64, 128)    -- azul oscuro semitransparente
ioports.gpu.clear()                 -- reutiliza el último ClearColor establecido
```

Ten en cuenta que el orden de bytes de la GPU es `0xAABBGGRR` — el rojo
es el byte *bajo* — que es la razón principal de la forma por
componentes: `clear(r, g, b)` lo empaqueta en el orden correcto por ti.

La forma por componentes acepta 3 o 4 argumentos (2, o más de 4, es un
error de compilación). Cuando todos los componentes son literales se
pliega a una sola constante empaquetada en tiempo de compilación — los
literales fuera de rango se limitan a `0`–`255` con una advertencia. En
otro caso cada componente se evalúa como una expresión normal, se limita
a `0`–`255`, se trunca a entero y se empaqueta en tiempo de ejecución. Un
`nil` explícito para `a` significa opaco, igual que omitirlo, y también un
alfa que sea `nil` en ejecución; no hay comprobación de nil en tiempo de
ejecución en el rojo, el verde y el azul, así que una variable que sea
`nil` ahí da un color indefinido.

*Por qué una variable empaquetada necesita `rgba()` o `hex()`:* los
números de v32lua son float32, así que un número como `0xFF202020`
guardado en una variable contiene un flotante, no los bits del color, y
`clear()` no puede distinguirlos en tiempo de ejecución. Los literales
escritos directamente en la llamada funcionan, porque se pliegan en tiempo
de compilación.

<a id="colors-rgba"></a>
**Colores: rgba(r, g, b [, a])**

Devuelve la palabra empaquetada `0xAABBGGRR` de la GPU para un color — la
palabra cruda de 32 bits, *no* un número Lua — para todo lo que espera una:
el `color_mult` de `spr()`, `ioports.gpu.clear(color)`,
`ioports.gpu.multiply`, `ioports.gpu.bgcolor`.

```lua
spr(id, x, y, 1, 1, 0, rgba(255, 255, 255, alpha))   -- fundido
ioports.gpu.multiply = rgba(r, g, b)                 -- sin conversión a flotante
ioports.gpu.clear(rgba(16, 16, 48))
```

* 3 o 4 argumentos (cualquier otra cantidad es un error de compilación).
  El alfa vale 255 por defecto; un alfa `nil` (literal o en ejecución)
  también vale 255.
* Cada componente se limita a `0`–`255` y se trunca (`127.9` → 127),
  exactamente como `clear(r, g, b [, a])`, con quien comparte el código.
* Con todos los argumentos literales se pliega al compilar en una sola
  constante (`rgba(1, 2, 3, 4)` es `0x04030201`); los literales fuera de
  rango se limitan con una advertencia. Si no, se empaqueta en ejecución;
  los componentes que llaman a funciones son seguros.
* Solo en modo Vircon32 nativo. Una función tuya llamada `rgba` tiene
  prioridad.

**Cuidado — guarda los componentes, no la palabra.** Una palabra cruda
cuyos bits altos coinciden con una de las etiquetas de valor del lenguaje
*es* ese valor para el resto del programa: `rgba(0, 0, 192, 255)` es
`0xFFC00000`, es decir `nil`, y `0xFF8xxxxx` se lee como una tabla.
Pasarla directamente a una llamada o a un puerto siempre es seguro (solo
se copia). Guardarla en una tabla (un valor `nil` borra la clave),
comprobarla (`if c then`) o compararla con `nil` no lo es. `hex()` tiene
el mismo problema. Lo seguro es guardar los componentes como números y
llamar a `rgba()` donde se usa el color, como en los ejemplos de arriba.

<a id="colors-color"></a>
**Colores: color(n)**

Convierte un número que contiene un color empaquetado `0xAABBGGRR` en la
palabra cruda, para los colores que tienes como número en lugar de como
componentes: uno calculado con aritmética, leído de una tabla de colores o
cargado desde la tarjeta de memoria.

```lua
local palette = { 0xFF1D2B53, 0xFF7E2553, 0xFF008751 }
ioports.gpu.multiply = color(palette[i])
spr(id, x, y, 1, 1, 0, color(base + fade * 0x01000000))
```

* Un argumento (cualquier otra cantidad es un error de compilación; un
  literal de cadena, `nil` o booleano también).
* El número se redondea hacia abajo y se ajusta a 32 bits, así que los
  números negativos dan su palabra en complemento a dos (`color(-1)` es
  `0xFFFFFFFF`). Los valores fuera de `[-2^31, 2^32)` se saturan.
* Un literal se pliega al compilar y es exacto: `color(0x802040FF)` es
  `0x802040FF`.
* En tiempo de ejecución el número es un float32, que solo guarda 24 bits
  significativos, así que un color cuyos bits ocupan más de 24 se redondea
  antes de que `color()` lo vea: una variable que contiene `0x802040FF`
  da `0x80204100`. Los colores con alfa `0xFF` y muchos otros valores
  habituales son exactos (`0xFF003366`, `0x80FFFFFF`), pero cuando
  importan los bits exactos, guarda los componentes y usa `rgba()`.
* El mismo cuidado que con `rgba()` respecto a las palabras que parecen
  `nil` o una tabla.
* Solo en modo Vircon32 nativo. Una función tuya llamada `color` tiene
  prioridad (el `color()` de PICO-8 es la función propia de PICO-8).

<a id="integer-ports-and-literals"></a>
**Puertos enteros y literales**

Un número escrito en un puerto entero (`ioports.gpu.x`, `bgcolor`,
`multiply`, …) se convierte con `CFI`, truncando hacia cero. Un
**literal numérico** se escribe en cambio como su palabra exacta de 32
bits, calculada al compilar: `ioports.gpu.bgcolor = 0xFF003366` guarda
`0xFF003366` (una conversión de flotante lo saturaría),
`ioports.gpu.x = -5` guarda `-5`, e `ioports.gpu.y = 12.7` guarda `12`.
Los literales fuera de `[-2^31, 2^32)` se saturan con una advertencia.

**Definiendo regiones de textura**

El `region_id` de `spr()` no se refiere a nada hasta que se haya recortado
realmente una región de una textura cargada. No hay autoría de regiones
del lado del compilador — esto son seis escrituras de puertos en bruto,
normalmente hechas una vez en `init()` (o una vez por textura al
principio de `main()` si no hay un `init()` separado), una región a la
vez:

```lua
ioports.gpu.texture = SPRITES   -- selecciona de qué textura cargada se recorta esta región
ioports.gpu.region  = 1         -- selecciona la RANURA de región 1 a definir (este es el id que spr() usará)
ioports.gpu.minX = 6            -- esquina superior-izquierda de la región, en píxeles de textura
ioports.gpu.minY = 156
ioports.gpu.maxX = 58           -- esquina inferior-derecha, inclusive
ioports.gpu.maxY = 208
ioports.gpu.hotX = 6            -- ver abajo -- NO 0
ioports.gpu.hotY = 156          -- ver abajo -- NO 0
```

*Hotspots de región: consideraciones y comportamiento del compilador*

Aunque los hotspots de región permiten dibujar las regiones respecto a un
par de coordenadas de hotspot, olvidarse de establecerlos puede causar
problemas de dibujo, ya que las coordenadas de hotspot sin establecer
pueden valer 0, 0 por defecto. Si quedan lo bastante lejos de los
extremos X e Y definidos para la región, puede que la región no se dibuje
donde quieres, o que ni siquiera aparezca en la pantalla.

Por eso `v32lua` establece automáticamente `ioports.gpu.hotX` e
`ioports.gpu.hotY`, de modo que, aunque se descuiden las coordenadas del
hotspot al definir una región, esta se siga dibujando de forma visible:

Al establecer el X y el Y mínimos de una región, el X y el Y del hotspot
correspondiente se establecen exactamente a los mismos valores. Así, por
defecto el hotspot queda en la esquina superior-izquierda.

Si quieres poner el hotspot en otro punto que no sea la esquina
superior-izquierda de la región, basta con establecerlo DESPUÉS de fijar
el X y el Y mínimos.

`GPU_RegionMinX/MinY/MaxX/MaxY/HotSpotX/HotSpotY` son los puertos en bruto
detrás de `ioports.gpu.minX` etc. — ver la tabla completa de puertos en
[Otros puertos de E/S en bruto](#otros-puertos-de-es-en-bruto) para todo
lo demás que `ioports.gpu.*` expone (punto de dibujo, escala, ángulo,
color de multiplicación, mezcla, y el contador de solo lectura de
GPU-ocupada `ioports.gpu.pixels`).

---

## Gráficos: rect() / rectfill()

```
rect(x1, y1, x2, y2 [, color])       -- contorno de 1 píxel
rectfill(x1, y1, x2, y2 [, color])   -- relleno
```

`(x1, y1)` y `(x2, y2)` son esquinas opuestas, ambas **incluidas**, en
cualquier orden: `rectfill(10, 20, 19, 24)` cubre 10 × 5 píxeles, columnas
10–19 y filas 20–24, y `rectfill(19, 24, 10, 20)` es el mismo rectángulo.
Las coordenadas se redondean hacia abajo (`rectfill(9.8, ...)` empieza en
la columna 9); `nil` o algo que no sea un número cuenta como 0. Si las dos
esquinas coinciden se dibuja un píxel.

`color` es una palabra empaquetada `0xAABBGGRR`, igual que el `color_mult`
de `spr()`: un literal (`0xFF0000FF`), `rgba()`, `color()`, `hex()`, o una
variable que contenga uno de ellos. Ausente o `nil`: blanco opaco. Un color
con alfa menor que 255 se mezcla con el modo de mezcla actual
(`ioports.gpu.blending`), que `rect()` no cambia.

```lua
rectfill(0, 0, 639, 359, rgba(0, 0, 64))      -- toda la pantalla, azul oscuro
rect(100, 50, 199, 99, 0xFF00FFFF)           -- marco amarillo de 100 x 50
rectfill(px, py, px + 15, py + 15, rgba(255, 0, 0, 128))   -- rojo translúcido
```

**Cómo dibuja**

Ambas dibujan con la textura de la BIOS (`-1`), región 256: un píxel
blanco que define la BIOS, en (469, 29), con su punto de anclaje en él. No
se añade nada al cartucho. `rectfill()` es **un** dibujo escalado de esa
región con escala (ancho, alto), teñido con el color de multiplicación —
exacto al píxel en cualquier tamaño (la corrección de escalado de la GPU
mantiene el muestreo dentro de ese único píxel). `rect()` son hasta 4 dibujos que no se solapan (bordes superior e
inferior de ancho completo, los laterales entre ellos), así que un contorno
translúcido no queda más oscuro en las esquinas.

El estado de la GPU que usa la llamada se restaura después: textura y
región seleccionadas, color de multiplicación, escala de dibujo. Un
`rect()` puede ir en medio de código de dibujo con `ioports.gpu.*` sin
alterarlo.

Cada dibujo cuesta píxeles de GPU como cualquier otro
(`ioports.gpu.pixels`), más la penalización de escalado de la GPU; un
`rectfill()` de pantalla completa cuesta una pantalla de píxeles.

Una función propia llamada `rect` o `rectfill` reemplaza a la incorporada,
como con todo intrínseco. Con `--#api pico8` los dos nombres son las
versiones de PICO-8 con colores de paleta (ver [PICO8.md](PICO8.md)); con
`--#api tic80`, `rect(x, y, w, h, color)` / `rectb(...)` son las de TIC-80
(ver [TIC80.md](TIC80.md)).

---

## Entrada: btn() / btnp()

```
btn(id [, player])   -> booleano, actualmente mantenido presionado
btnp(id [, player])  -> booleano, verdadero solo en el cuadro en que se presionó por primera vez
```

`player` selecciona un mando 0–3 (`INP_SelectedGamepad`); omitido o `nil`
usa el mando que ya esté seleccionado sin escribir el puerto.

**IDs de botones**

Orden de hardware de Vircon32, no el de PICO-8 ni el de TIC-80:

| id | Botón | IOPort |
|---|---|---|
| 0 | Izquierda | `INP_GamepadLeft` |
| 1 | Derecha | `INP_GamepadRight` |
| 2 | Arriba | `INP_GamepadUp` |
| 3 | Abajo | `INP_GamepadDown` |
| 4 | Start | `INP_GamepadButtonStart` |
| 5 | A | `INP_GamepadButtonA` |
| 6 | B | `INP_GamepadButtonB` |
| 7 | X | `INP_GamepadButtonX` |
| 8 | Y | `INP_GamepadButtonY` |
| 9 | L (gatillo izquierdo) | `INP_GamepadButtonL` |
| 10 | R (gatillo derecho) | `INP_GamepadButtonR` |

Un `id` fuera de 0–10, o una combinación no mapeada, devuelve `false` en
lugar de dar un error — no hay una ruta de error a nivel de sistema
operativo disponible en este objetivo (ver `pcall`/`error`/`assert` en la
lista de características diferidas del compilador).

**btn(): sondeo directo**

`__builtin_vircon32_btn` lee el puerto `INP_Gamepad*` mapeado para el
mando seleccionado y devuelve `true` cuando el hardware reporta que está
presionado (`>= 1`).

**btnp(): detección de flanco**

`btnp()` necesita un estado que el hardware no rastrea por sí mismo: "¿no
estaba este botón presionado en el cuadro anterior, y está presionado
ahora?" Ese estado vive en `VIRCON32_BTN_PREV_STATE`, un rango fijo de RAM
de 44 palabras reservado por el compilador — una palabra por par
(jugador, botón), `player * 11 + button_id` — actualizado en cada llamada
a `btnp()` sin importar el resultado. Solo una transición genuina de
no-presionado → presionado devuelve `true`; un botón mantenido a través de
múltiples cuadros devuelve `true` una vez, y luego `false` en cada cuadro
subsiguiente hasta que se suelta y se presiona de nuevo.

Un `player` fuera de rango (un valor explícito fuera de 0–3) se acota a
0–3 antes de usarse como índice en esa tabla de 44 palabras, en lugar de
permitir que compute una dirección fuera de ella.

**ioports.inp.inputs — máscara de una palabra**

```lua
local mask = ioports.inp.inputs   -- mando actual, los 11 botones en una sola lectura
```

Lee cada puerto `INP_Gamepad*` para el mando que esté actualmente
seleccionado (`ioports.inp.gamepad`) y los combina en un único número de
11 bits de una sola vez, en lugar de once llamadas separadas a `btn()`.
Distribución de bits, de MSB a LSB:

| Bit | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Botón | Izquierda | Derecha | Arriba | Abajo | Start | A | B | X | Y | L | R |

Cada bit es `1` si ese botón actualmente se lee como presionado (`> 0`),
la misma semántica de "actualmente mantenido" que `btn()` — esto es una
instantánea de estado mantenido, no una activada por flanco; no hay un
equivalente en máscara de bits de `btnp()`. Útil para pasar la entrada de
un cuadro completo como un solo valor (por ejemplo, en un registro de
repetición/entrada) en lugar de para la lógica de juego cotidiana por
botón, donde `btn()`/`btnp()` se leen con más claridad.

**Lo que deliberadamente NO está aquí**

- Ninguna forma de campo de bits/"cualquier botón" (`btn()` sin
  argumentos) al estilo de PICO-8 — cada llamada nombra un botón
  específico.
- Ningún reporte de stick analógico o presión de gatillo; el modelo de
  mando de Vircon32 es digital según la lista de IOPort anterior.
- No existe ningún puerto de salida de vibración/rumble en la consola
  para exponer.

Estos coinciden con el hardware subyacente de Vircon32 en lugar de las
convenciones de PICO-8/TIC-80; esa emulación vive por completo en las
capas de compatibilidad `--#api pico8`/`--#api tic80`, no aquí.

---

## Teclado: key() / keyp() / kbd.\*

```
key([k])                      -> booleano, k pulsada (sin k: cualquier tecla)
keyp([k [, hold, period]])    -> booleano, k se pulsó en este cuadro (+ autorrepetición)
kbd.read()                    -> siguiente carácter escrito (un número), o nil
kbd.event()                   -> siguiente evento: +código pulsada, -código soltada, o nil
kbd.port([n])                 -> puerto de mando del teclado (y lo cambia)
kbd.capslock()                -> booleano, Bloq Mayús activo
kbd.connected()               -> booleano, hay algo conectado en ese puerto
kbd.clear()                   -- descarta los eventos aún no leídos
```

Leen un teclado completo a través de un dispositivo **v32kbd**: un
adaptador USB de teclado que la consola ve como un mando normal, cuyos 11
controles transportan eventos de teclas en lugar de botones (ver el
proyecto v32kbd). Se conecta en un puerto de mando — **el puerto 1 (el
segundo) por defecto**, dejando el puerto 0 para un mando normal. Se cambia
con `--keyboard N` en la línea de órdenes, una pista `--#keyboard N` en el
código, o `kbd.port(n)` en tiempo de ejecución.

`key()`/`keyp()` siguen a los de TIC-80: mismos nombres, mismas reglas, con
códigos de tecla de v32kbd. Con `--#api tic80` las mismas dos llamadas usan
los códigos de TIC-80 (ver [TIC80.md](TIC80.md#input)); `kbd.*` funciona con
todas las API. Una global propia llamada `kbd` (una tabla que asignes)
reemplaza a las funciones `kbd.*` incorporadas.

**Códigos de tecla**

Un código nombra una **tecla**, no un carácter: las teclas que escriben un
carácter usan ese carácter sin mayúsculas, distribución de EE. UU. —
`'a'`–`'z'` (97–122), `'0'`–`'9'` (48–57), espacio (32) y
`` ` - = [ ] \ ; ' , . / `` — y las demás:

| Código | Tecla | Código | Tecla |
|---|---|---|---|
| 1 | Arriba | 11 | Ctrl derecho |
| 2 | Abajo | 12 | Alt izquierdo (Option) |
| 3 | Izquierda | 13 | Intro |
| 4 | Derecha | 14–25 | F1–F12 |
| 5 | Bloq Mayús | 26 | Alt derecho (Option) |
| 6 | Mayús izquierda | 27 | Escape |
| 7 | Mayús derecha | 28 | GUI izquierda (Command, Windows) |
| 8 | Retroceso | 29 | GUI derecha |
| 9 | Tabulador | 127 | Suprimir |
| 10 | Ctrl izquierdo | | |

Las teclas del teclado numérico dan los mismos códigos que sus equivalentes
del teclado principal.

`k` también puede ser un **literal de cadena**, convertido al código al
compilar: un carácter (`"a"`, `"/"`, `" "`; un carácter con mayúsculas
nombra su tecla, así que `"A"` es la tecla a y `"!"` la tecla 1), o un
nombre — `up` `down` `left` `right` `enter` (`return`) `tab` `space`
`backspace` `delete` (`del`) `escape` (`esc`) `capslock` `lshift` `rshift`
`lctrl` `rctrl` `lalt` `ralt` `lgui` `rgui` `f1`–`f12`, sin distinguir
mayúsculas. Cuatro nombres valen por cualquiera de los dos lados: `shift`,
`ctrl`, `alt`, `gui` (`key("shift")` es verdadero mientras cualquiera de
las dos Mayús esté pulsada). Un nombre desconocido es un error de
compilación. Solo se convierten literales: una cadena guardada en una
variable no es una tecla (`false`).

```lua
function game_loop()
    if key("left")  then x = x - 2 end
    if key("right") then x = x + 2 end
    if keyp("space") then fire() end
    if key("ctrl") and keyp("s") then save() end
    if keyp("down", 20, 4) then menu_next() end   -- se repite mientras se mantiene
end
```

**key([k]), keyp([k [, hold, period]])**

`key(k)` es verdadero mientras la tecla está pulsada. `keyp(k)` es
verdadero en el cuadro en que se pulsa; con `hold` y `period` dados y
≥ 0, también mientras la tecla siga pulsada, desde `hold` cuadros, cada
`period` cuadros (`period` 0: cada cuadro) — contando los cuadros después
del primero, como hacen `keyp` y `btnp` de TIC-80. No hay autorrepetición
por defecto. Sin `k`, `key()` es "alguna tecla pulsada" y `keyp()` "alguna
tecla se pulsó en este cuadro". Un código sin tecla detrás es `false`.

**Texto escrito: kbd.read()**

```lua
local text = ""
function game_loop()
    local c = kbd.read()
    while c do
        if c == 8 then                          -- Retroceso
            text = string.sub(text, 1, -2)
        elseif c >= 32 and c < 127 then
            text = text .. string.char(c)
        end
        c = kbd.read()
    end
    print(0, 0, text .. "_")
end
```

`kbd.read()` devuelve la siguiente **pulsación** como el carácter que
escribe, con Mayús y Bloq Mayús aplicados tal como estaban al pulsarla
(`"A"`, `"!"`, `"{"` ... como números, según la fuente de la BIOS), y las
teclas sin carácter como su código (Intro 13, Retroceso 8, flechas 1–4...).
Las liberaciones se saltan. `nil` cuando no queda nada.

`kbd.event()` devuelve en cambio todos los eventos, pulsaciones y
liberaciones, como el código de tecla sin Mayús: positivo al pulsar,
negativo al soltar (`-97`: se soltó la tecla a). Ambas leen la misma cola:
usa una u otra. La cola guarda 64 eventos; a partir de ahí los nuevos se
descartan hasta que se lea (`kbd.clear()` la vacía; las teclas pulsadas
que ve `key()` no se ven afectadas).

**kbd.port([n]), kbd.capslock(), kbd.connected()**

`kbd.port(n)` mueve el teclado al puerto de mando `n` (0–3, acotado) y
empieza de nuevo: se olvidan las teclas pulsadas, los eventos en cola y el
Bloq Mayús, y el estado actual del dispositivo se toma como punto de
partida. Devuelve el puerto; `kbd.port()` solo lo devuelve.
`kbd.capslock()` es el estado de Bloq Mayús, llevado contando sus
pulsaciones (empieza desactivado). `kbd.connected()` es verdadero cuando
hay algo conectado en el puerto del teclado.

**Leer en cada cuadro**

El dispositivo informa como mucho de un evento de tecla por cuadro y lo
mantiene hasta el siguiente, así que hay que leerlo **en cada cuadro** o se
pierden eventos. El compilador se encarga de ello cuando el programa usa
el teclado:

- cada llamada a `key`/`keyp`/`kbd.*` lee el dispositivo (una vez por
  cuadro);
- los controladores de `game_loop()` y de `TIC()` de TIC-80 lo leen antes
  de cada cuadro;
- `system.wait()` e `ioports.gpu.sync()` lo leen antes de su `WAIT` (lo que
  llega entonces cuenta para el cuadro siguiente, así que `keyp()` lo sigue
  viendo).

Así, un bucle `main()` que espera con `system.wait()` no pierde nada,
aunque solo mire el teclado de vez en cuando. Un `__rawasm__("WAIT")`
desnudo se salta esa lectura. Nada de esto está en un programa que no use
el teclado.

**El puerto de mando**

El puerto del teclado se lee sin alterar el mando que el programa tiene
seleccionado: `btn()`, `btnp()` e `ioports.inp.*` siguen leyendo el mando
que leían antes. No leas el puerto del teclado con `btn()`: sus "botones"
son bits del código de tecla.

El mando seleccionado lo recuerda el entorno de ejecución (`V32IO_GAMEPAD`)
en lugar de leerlo de `INP_SelectedGamepad`: los emuladores de Vircon32
devuelven un valor erróneo al leer ese puerto. Las lecturas de
`ioports.inp.gamepad` también dan el valor recordado. Una escritura en el
puerto con `__rawasm__` se lo salta.

---

## Ratón: mouse() / mouse.\*

```
mouse()                       -> x, y, left, middle, right, scrollx, scrolly
mouse.pressed([b])            -> booleano, un botón de b se pulsó en este cuadro
mouse.released([b])           -> booleano, un botón de b se soltó en este cuadro
mouse.buttons()               -> botones pulsados: 1 izquierdo + 2 derecho + 4 central
mouse.delta()                 -> dx, dy: el movimiento de este cuadro
mouse.position([x, y])        -> x, y (y mueve el puntero ahí)
mouse.bounds(x1, y1, x2, y2)  -- la zona en la que se queda el puntero
mouse.scale([n])              -> píxeles que se mueve el puntero por paso (y lo cambia)
mouse.port([n])               -> puerto de mando del ratón (y lo cambia)
mouse.connected()             -> booleano, hay algo conectado en ese puerto
```

Leen un ratón a través de un dispositivo **v32mouse**: un adaptador USB de
ratón que la consola ve como un mando normal (ver el proyecto v32io). Se
conecta en un puerto de mando — **el puerto 3 (el cuarto) por defecto**,
como en la demo de ratón de v32io, así caben a su lado un teclado (puerto 1)
y el mando de un jugador (puerto 0). Se cambia con `--mouse N` en la línea
de órdenes, una pista `--#mouse N` en el código, o `mouse.port(n)` en tiempo
de ejecución.

`mouse()` es el de TIC-80: `x, y` del puntero, luego `left, middle, right`
como booleanos, y luego `scrollx, scrolly`, que son siempre 0 — el
dispositivo no tiene sitio para la rueda. La misma llamada, con los mismos 7
valores, funciona también con `--#api tic80` y `--#api pico8`, en las
unidades de pantalla de esa consola (ver [TIC80.md](TIC80.md#input) y
[PICO8.md](PICO8.md#api)); `mouse.*` funciona con todas las API. Una función
o global propia llamada `mouse` las reemplaza todas.

```lua
function game_loop()
    local x, y, left = mouse()
    if mouse.pressed(1) then          -- se pulsó el botón izquierdo
        click_at(x, y)
    end
    if left then
        draw_at(x, y)                 -- mantenido
    end
    rectfill(x - 1, y - 1, x + 1, y + 1)
end
```

**El puntero**

El dispositivo informa del movimiento, no de una posición, así que el
entorno de ejecución lleva un puntero: empieza en el centro de la pantalla
(320, 180), se mueve **pasos × escala** (escala 2 por defecto: 2 píxeles por
paso) y se queda dentro de sus límites (toda la pantalla de 640 × 360 por
defecto, ambos bordes incluidos). `mouse.bounds()` lo limita a una zona (un
`nil` deja ese borde como está) y lo mueve dentro; `mouse.position(x, y)` lo
coloca (cada coordenada dada se redondea hacia abajo y se mantiene dentro de
los límites; `nil` la conserva); `mouse.scale(n)` fija la velocidad (n ≥ 1).
Las tres devuelven sus valores actuales, así que `mouse.position()` y
`mouse.scale()` solo leen. `mouse.delta()` es el movimiento de este cuadro
en píxeles (después de la escala, antes de los límites); 0, 0 si no se
movió.

**Botones**

`left`, `middle` y `right` siguen pulsados mientras lo estén los botones.
Para `mouse.pressed(b)`, `mouse.released(b)` y `mouse.buttons()`, los
botones son números: **1 izquierdo, 2 derecho, 4 central**, sumados para
"cualquiera de estos" (`mouse.pressed(3)`: izquierdo o derecho). Sin `b`,
cualquier botón. `pressed` / `released` solo son verdaderos en el cuadro en
que cambió el botón. El adaptador mantiene cada cambio de botón al menos
25 ms, así que hasta un clic rápido dura más de un cuadro.

**Cómo se lee**

El dispositivo lleva dos contadores, uno por eje, que recorren 12
posiciones, cambiando un control del mando por paso; cada lectura los
compara con la anterior, lo que da de −5 a +5 pasos por eje (6 no se
distingue de −6 y cuenta como sin movimiento). Así que, como el teclado, el
ratón hay que leerlo **en cada cuadro** — y el compilador se encarga cuando
el programa lo usa: cada llamada a `mouse`/`mouse.*` lo lee (una vez por
cuadro), los controladores de `game_loop()`, TIC-80 y PICO-8 lo leen en cada
cuadro, y `system.wait()`, `ioports.gpu.sync()` y el `flip()` de PICO-8 lo
leen antes de su `WAIT` (lo que llega entonces cuenta para el cuadro
siguiente). Un bucle `main()` que espera con `system.wait()` no pierde
movimiento aunque solo mire el ratón de vez en cuando. El movimiento solo se
mide entre dos lecturas de un dispositivo conectado separadas como mucho 2
cuadros; cualquier otro caso — un dispositivo recién conectado, cuadros
pasados en una pantalla de pausa, un bucle con `__rawasm__("WAIT")` — solo
toma los contadores como nuevo punto de partida, así que el puntero nunca
salta.

`mouse.port(n)` mueve el ratón al puerto de mando `n` (0–3, acotado) y
empieza de nuevo desde el estado actual del dispositivo (el puntero se queda
donde está). `mouse.connected()` es verdadero cuando hay algo conectado en
el puerto del ratón. Como con el teclado, leer el puerto del ratón no altera
el mando que el programa tiene seleccionado.

---

## Mapa de mosaicos: tilemap.\*

```
tilemap.get(NAME, x, y)        -> número o nil (fuera de límites)
tilemap.set(NAME, x, y, v)     -> v (la escritura fuera de límites es un no-op silencioso)
tilemap.render(NAME, sx, sy, w, h, x, y, tile_w, tile_h [, skip_id])
```

`NAME` siempre es un identificador simple declarado con `--#tilemap`,
resuelto por completo en tiempo de compilación — nunca un valor en tiempo
de ejecución, la misma restricción (y la misma razón) que tienen los
nombres `--#sound`/`--#texture`: no hay nada sensato contra lo cual pueda
resolverse un nombre calculado dinámicamente, ya que todo el punto es que
el compilador conoce el ancho/alto y la ubicación en ROM del mapa de
mosaicos por nombre antes de que se ejecute cualquier código.

A diferencia de `--#texture`/`--#sound`, un mapa de mosaicos **no** es un
recurso de cart-XML — sin entrada `<textures>`/`<sounds>`, sin id de
recurso horneado en el código generado. Sus datos se incrustan como
valores literales directamente en el programa ensamblado.

**--#tilemap NOMBRE "archivo" y el formato CSV**

```lua
--#tilemap LEVEL1 "level1.csv"
```

El archivo es texto plano: filas de ids de mosaico separados por comas,
una fila por línea. El número de filas se convierte en la altura del
mapa de mosaicos; el número de valores de la primera fila se convierte en
su ancho, y cada otra fila debe coincidir exactamente con ese conteo o es
un error de compilación — un mapa irregular que lee basura en silencio
más allá de una fila corta es peor que negarse a compilar. Un id de
mosaico es simplemente un número; no hay un significado requerido, pero el
natural (y el que asume `tilemap.render()`) es un id de región de GPU,
listo para entregarse a `spr()`.

Este formato es deliberadamente lo bastante simple como para que la
salida de **Export As... CSV** (por capa) de Tiled pueda usarse
directamente sin ningún paso de conversión — no hay análisis de TMX/TSX
en ninguna parte de este compilador.

**tilemap.get() / tilemap.set()**

```lua
local id = tilemap.get(LEVEL1, 4, 2)   -- mosaico en columna 4, fila 2
tilemap.set(LEVEL1, 4, 2, 99)          -- sobrescribirlo
```

Ambos son indexados desde 0, `(x, y)` = `(columna, fila)`. `tilemap.get()`
fuera de límites (cualquier eje, cualquier dirección) devuelve `nil`, lo
mismo que leer más allá del final de una tabla de Lua. `tilemap.set()`
fuera de límites es un no-op silencioso — no hay un valor sensato que
devolver por "intentaste escribir en ningún lugar", así que simplemente
declina, reflejando cómo el `mset()` de la capa de compatibilidad TIC-80
ya trata una escritura fuera de rango.

Los valores se almacenan y devuelven como números simples **sin
acotación** — a diferencia del `mset()` de la capa TIC-80, que acota a
0–255 porque los ids de sprite de TIC-80 tienen tamaño de byte. Un valor
de mosaico aquí es simplemente lo que el código que llama quiera que
signifique, típicamente un id de región de GPU, que puede superar
ampliamente los 255.

**Promoción perezosa de ROM a RAM**

Un mapa de mosaicos comienza su vida de solo lectura, sentado donde sea
que el compilador colocara sus datos en la imagen del programa —
`tilemap.get()` antes de cualquier escritura lee directamente de ahí, sin
costo de RAM. El **primer** `tilemap.set()` contra un mapa de mosaicos
dado lo promueve: asigna una copia privada en RAM y copia cada celda a
través, y solo después de eso el mapa de mosaicos se vuelve mutable. Cada
lectura o escritura a un mapa de mosaicos *diferente* que no ha sido
promovido no se ve afectada — la promoción se rastrea por mapa de
mosaicos, no globalmente. Un segundo `tilemap.set()` posterior en un mapa
de mosaicos ya promovido escribe directamente, sin volver a copiar ni
perturbar escrituras anteriores.

**tilemap.render()**

```lua
tilemap.render(LEVEL1, sx, sy, w, h, x, y, tile_w, tile_h)
tilemap.render(LEVEL1, sx, sy, w, h, x, y, tile_w, tile_h, skip_id)
```

Dibuja una región de `w` por `h` celdas, comenzando en la celda del mapa
de mosaicos `(sx, sy)`, hacia la pantalla comenzando en el píxel
`(x, y)`, separadas `tile_w`/`tile_h` píxeles por celda — una llamada
`spr(tile_value, screen_x, screen_y)` por celda visible, de solo lectura
(nunca promueve). `sx`/`sy` se acotan a `0 .. max(0, dimension - w_o_h)`,
la misma filosofía de acotación que ya usa el `map()` de la capa de
compatibilidad TIC-80, así que una posición de desplazamiento puede
caminar más allá del borde real del mapa sin dibujar basura ni necesitar
que quien llama la acote primero.

`tile_w`/`tile_h` son **obligatorios**, a diferencia del `map()` de
TIC-80, que asume una cuadrícula fija de 8×8 — esta API no tiene una
suposición equivalente a la cual recurrir, ya que las regiones de la GPU
pueden ser de cualquier tamaño. Solo controlan el *espaciado* en píxeles
entre las celdas dibujadas; `render()` dibuja cada región en su propio
tamaño nativo sin importar `tile_w`/`tile_h`, así que una región más
angosta o más corta que el paso queda al ras contra un borde de su celda
en lugar de estirarse para llenarla.

`skip_id` (opcional) — una celda cuyo valor sea igual a `skip_id` no
recibe ninguna llamada `spr()`, útil para un mapa disperso donde la
mayoría de las celdas son "nada aquí". Este es un mecanismo más burdo que
la transparencia por colorkey del `map()` de TIC-80 (que mezcla por
píxel); las regiones nativas ya llevan alfa real, así que la necesidad
común es simplemente "no te molestes en dibujar esta celda", no "dibújala
pero mezcla ciertos píxeles para que desaparezcan".

**El desplazamiento tiene granularidad de celda, no de sub-píxel.**
`sx`/`sy` son índices de celda; no hay ningún desplazamiento de origen
fraccionario en ninguna parte del diseño, así que caminar `sx` en 1 mueve
el contenido dibujado un `tile_w` completo en pantalla — la misma
limitación que tiene el propio `map()` de TIC-80. Un desplazamiento suave
por píxel necesitaría dibujar una fila/columna extra más allá de `w`/`h`
y desplazar el origen de pantalla de todo el bloque por un resto de
píxel de sub-mosaico; esa es una extensión real y separada, no
implementada aquí.

**Lo que deliberadamente NO está aquí**

- Sin desplazamiento suave/de sub-píxel — ver arriba.
- Sin nomenclatura `mget()`/`mset()`/`map()` — esos nombres pertenecen a
  la capa de compatibilidad TIC-80; esta es una superficie nativa
  distinta, no una extensión de ella.
- Sin soporte multi-capa — una pista `--#tilemap` es una cuadrícula plana.
  El apilamiento por capas es asunto del código llamante (declarar varios
  mapas de mosaicos, renderizarlos en orden).
- Sin ayudantes de colisión/consulta más allá del propio `tilemap.get()`
  — comprobar "¿es esto una pared?" es simplemente comparar el id de
  mosaico devuelto.

---

## Tarjeta de memoria: memcard.\*

```
memcard.save(value, position)   -> value   (escritura en bruto, exactamente 1 palabra)
memcard.save(value)             -> value   (auto-anexado; ver abajo)
memcard.load(position)          -> value   (lectura en bruto, exactamente 1 palabra)
memcard.load()                  -> value   (posición 0)
memcard.load_table(position)    -> table o nil   (ver Tablas, abajo)
memcard.title(str)              -> nil     (establece el título de 20 palabras)

memcard[position]                  == memcard.load(position)
memcard[position] = value          == memcard.save(value, position)
```

La tarjeta de memoria es un periférico de hardware real de Vircon32: un
rango de almacenamiento fijo y persistente en la dirección física
`0x30000000`, completamente separado de la ROM del cartucho y de la RAM
de Vircon32. A diferencia de la RAM, sobrevive un ciclo de energía — es el
dispositivo de guardado de partidas de la consola.

**Esta VM está direccionada por palabra en todas partes**, y la tarjeta
de memoria sigue la misma convención: una dirección (y una `position`)
avanza en palabras completas de 4 bytes, no en bytes individuales. Esto
coincide con cómo esta VM ya almacena las cadenas de Lua internamente —
una palabra por carácter (ver `string.len()`) — en lugar de una
representación empaquetada por byte.

**memcard.save() / memcard.load()**

Hay dos formas distintas, elegidas según si se da una `position`:

**Con una `position` explícita** — la primitiva de bajo nivel. Escribe (o
lee) exactamente una palabra en bruto en `position`, sin ningún tipo de
contabilidad. `position 0` es la primera palabra de la región de datos;
ver **Diseño de direcciones** abajo para el rango
completo, incluyendo cómo las posiciones negativas alcanzan el título.
Eres plenamente responsable de saber qué pones dónde — escribir la misma
posición dos veces simplemente la sobrescribe.

```lua
memcard.save(1234, 0)     -- palabra 0: número en bruto
memcard.save(true, 1)     -- palabra 1: booleano en bruto
local hi = memcard.load(0)  -- 1234
```

**Sin ninguna `position`** — `memcard.save(value)` auto-anexa mediante un
cursor persistente almacenado *en la propia tarjeta* (no en RAM), así que
los guardados repetidos sin posición siguen extendiendo un registro a
través de muchas sesiones de juego en lugar de sobrescribir la palabra 0
en cada ejecución. Esta forma es consciente del tipo: guardar una cadena
de Lua real escribe su contenido completo (etiquetado y con prefijo de
longitud, ver **Etiquetas de tipo**),
no solo un puntero en bruto.

```lua
memcard.save("high score run")   -- anexado en el cursor actual
memcard.save(9001)               -- anexado justo después
```

El propio cursor — "cuántas palabras se han auto-anexado hasta ahora" —
se puede leer en cualquier momento como `memcard.load(-1)` /
`memcard[-1]`; no hay una función de conteo separada.

`memcard.load()` sin `position` siempre lee la palabra 0 — **no** sigue el
cursor de auto-anexado de la forma en que lo hace `memcard.save()`. Leer
de vuelta una entrada escrita por la forma de auto-anexado significa leer
tú mismo su palabra de etiqueta en una posición conocida (ver
**Etiquetas de tipo**), o
simplemente saber qué escribiste ahí.

**memcard[position]**

`memcard[position]` y `memcard[position] = value` son abreviaturas de la
forma de posición explícita de `load`/`save` de arriba — nunca de la
forma de auto-anexado, ya que la sintaxis de corchetes de Lua no tiene
forma de decir "sin índice".

```lua
memcard[0] = 1234
local hi = memcard[0]        -- 1234
local cursor = memcard[-1]    -- lee el cursor de auto-anexado
```

**memcard.title(str) -> nil**

Establece el título de la tarjeta de memoria — hasta 20 caracteres, una
palabra por carácter, coincidiendo con la representación interna de
cadenas de esta VM. Las cadenas más largas se truncan; las más cortas se
rellenan con ceros. Esto es independiente de cualquier pista de cartucho
`--#title`, que nombra al *cartucho*, no a los *datos guardados* — un solo
cartucho puede tener muchas tarjetas de memoria en circulación, cada una
con su propio título.

```lua
memcard.title("My Save File")
```

**Tablas: memcard.save() / memcard.load_table()**

`memcard.save(a_table)` — **solamente** la forma de auto-anexado sin
posición — escribe un **volcado en bruto** del contenido de la tabla: un
recorrido directo de su almacenamiento interno de cubetas hash (hash
buckets), de la misma forma en que harías `fwrite()` de un struct a un
archivo en C. No es un serializador recursivo general.

```lua
local highscores = { alice = 500, bob = 350, carol = 900 }
memcard.save(highscores)

local restored = memcard.load_table(0)
print(10, 10, restored.alice)   -- 500
```

`memcard.save(a_table, position)` (la forma de **posición explícita**) no
se ve afectada por nada de esto — todavía escribe una única palabra de
puntero en bruto, exactamente como siempre lo ha hecho guardar una tabla
de esa manera. El formato de volcado de tabla de abajo es exclusivamente
una característica de la forma de auto-anexado sin posición.

**Por qué "el lado hash" y no un arreglo**: la implementación de tablas de
este compilador tiene en principio una ruta rápida de parte-arreglo, pero
su ruta de reasignación es actualmente un stub sin implementar — la
capacidad nunca crece más allá de 0, así que **cada** tabla, ya sea que
parezca con forma de arreglo (`{1, 2, 3}`) o no, ya se almacena
completamente en la cadena de cubetas hash. No hay hoy un "caso de
arreglo" separado y más simple para tratar como caso especial; volcar el
lado hash cubre todas las tablas tal como realmente existen ahora mismo.

**Qué se copia, y qué no**: cada clave y valor se escribe exactamente
como está empaquetado (boxed). Una clave/valor número, booleano, o nil
sobrevive el ciclo de ida y vuelta correctamente para siempre. Una clave o
valor que sea a su vez una tabla, cadena, o función se escribe como su
puntero en bruto — **no** se desempaqueta recursivamente — así que solo
es significativo dentro de la misma ejecución que lo escribió; volverlo a
cargar en una sesión futura (o después de que el objetivo del puntero se
haya movido o sido recolectado) es indefinido. Este es el mismo límite de
seguridad que el resto de `memcard.*` ya traza (ver
*Nota de seguridad*) — un volcado de tabla no lo
cruza, simplemente lo aplica por entrada en lugar de una sola vez.

**`memcard.load_table(position)`** reconstruye una tabla nueva a partir de
un volcado escrito de esta forma. `position` es **obligatoria** — a
diferencia de `memcard.load()`, no hay un valor por defecto sensato de
"posición 0" para algo cuyo tamaño en palabras no se conoce hasta que se
lee la propia entrada. Valida la palabra de etiqueta antes de confiar en
nada después de ella; leer en una posición que no contiene un volcado de
tabla devuelve `nil` en lugar de leer mal palabras no relacionadas como un
conteo de pares y claves/valores basura.

**Diseño de direcciones**

```
0x30000000  +-------------------------------------+  posición -24
            |  título: 20 caracteres               |
            |  (memcard.title() escribe aquí)      |  posición -5
            +-------------------------------------+
            |  reservado (3 palabras, sin usar)    |  posición -4 .. -2
            +-------------------------------------+
            |  cursor de auto-anexado               |  posición -1
0x30000018  +-------------------------------------+  posición 0
            |  región de datos                     |
            |  (memcard.save()/.load()/[pos])     |
            |  ...                                 |
0x3003FFFF  +-------------------------------------+  última palabra válida
```

`position` siempre es relativa al inicio de la región de datos
(`0x30000018`). Las posiciones negativas alcanzan hacia atrás dentro del
bloque de título/metadatos — alcanzable, pero solo yendo negativo a
propósito. Nótese que la región de metadatos (4 palabras, posiciones
-4..-1) está separada del bloque de título (20 palabras, posiciones
-24..-5) — anteriormente los metadatos se extraían de las *últimas 4
palabras del propio título*, limitando el título utilizable a 16
caracteres; los 20 completos están disponibles ahora.

| Constante | Valor | Significado |
|---|---|---|
| `VIRCON32_MEMCARD_BASE` | `0x30000000` | inicio de la tarjeta; posición `-24` |
| `VIRCON32_MEMCARD_DATA_BASE` | `0x30000018` | posición `0` |
| `VIRCON32_MEMCARD_CURSOR_ADDR` | `0x30000017` | el cursor de auto-anexado; posición `-1` |
| `VIRCON32_MEMCARD_END` | `0x3003FFFF` | última palabra válida, inclusive |

**Etiquetas de tipo (solo la forma de auto-anexado)**

`memcard.save(value)` sin posición escribe una de tres formas en el
cursor, y luego avanza el cursor por la cantidad de palabras que esa
forma usó:

| Tipo de valor | Distribución | Palabras usadas |
|---|---|---|
| Cadena real de Lua | `[TAG_STRING][length][char 0][char 1]...` | `2 + length` |
| Tabla | `[TAG_TABLE][pair_count][key 0][val 0]...` | `2 + 2 * pair_count` |
| Número / booleano / nil / función | `[TAG_SCALAR][raw value]` | `2` |

`TAG_SCALAR` es `0`, `TAG_STRING` es `1`, `TAG_TABLE` es `2`. Una función
guardada de esta forma se almacena como su puntero empaquetado en bruto
bajo `TAG_SCALAR` — ver la nota de seguridad abajo, esto no es una
serialización general.

La forma de `position` explícita (`memcard.save(value, position)` /
`memcard[position] = value`) nunca escribe una etiqueta — siempre es
exactamente una palabra en bruto, sin importar el tipo de valor. Esto
incluye tablas: una tabla guardada con una posición explícita es una
única palabra de puntero en bruto, no un volcado — ver
**Tablas** arriba.

*Nota de seguridad*

Un número, booleano, o nil sobrevive el ciclo de ida y vuelta
correctamente para siempre — ese patrón de bits significa lo mismo en
cualquier ejecución. Una cadena o tabla real de Lua guardada mediante la
forma de auto-anexado también sobrevive el ciclo de ida y vuelta
correctamente — los caracteres reales de una cadena se copian, y los
pares clave/valor reales de una tabla se copian, restaurables con
`memcard.load_table()`. Una tabla guardada mediante la forma de
*posición explícita*, una cadena guardada mediante la forma de *posición
explícita* (que almacena un puntero en bruto, no el contenido real de la
cadena), o un valor de función — incluyendo cualquier valor de este tipo
encontrado como *clave o valor dentro de una tabla guardada*, ya que
esas no se desempaquetan recursivamente — sobreviven el ciclo de ida y
vuelta bien **dentro de la misma ejecución** — su puntero sigue siendo
válido — pero carecen de sentido después de que un arranque nuevo los lea
de vuelta desde una tarjeta de memoria real, ya que no se garantiza que
la distribución de heap/ROM coincida entre ejecuciones. Cíñete a
números/booleanos/nil (o cadenas/tablas reales de tales, mediante la
forma de auto-anexado) para cualquier cosa destinada a sobrevivir un
ciclo real de guardado/recarga.

**Lo que deliberadamente NO está aquí**

- Sin serialización de tablas *recursiva* — un volcado de tabla copia
  solo sus pares clave/valor directos; una tabla anidada dentro de una es
  un puntero en bruto, un nivel, igual que en cualquier otra parte de
  `memcard.*`.
- El valor por defecto sin posición de `memcard.load()` no sigue el
  cursor de auto-anexado de la forma en que lo hace `memcard.save()` —
  siempre lee la palabra 0.
- Sin llamada de formateo/borrado — una tarjeta se formatea escribiendo
  en ella, no mediante una llamada separada.

Tanto `dget()`/`dset()` de PICO-8 como `pmem()` de TIC-80 son APIs no
relacionadas que también usan este mismo rango de direcciones físicas
bajo sus propias distribuciones — `memcard.*` no está disponible (es un
error de compilación) bajo `--#api pico8`/`--#api tic80` para evitar que
un programa mezcle ambos y corrompa el que no esté direccionando en ese
momento.

---

## Otros puertos de E/S en bruto

Cada puerto `ioports.*` vive en una sola tabla (`IOPortMap` de `core.c`),
organizada bajo siete categorías: `tim`, `rng`, `gpu`, `spu`, `inp`, `car`,
`mem`. Las categorías de sonido (`spu`), gráficos (`gpu`, parcialmente —
ver **Definiendo regiones de textura**), y
entrada (`inp`, parcialmente — ver [btn()/btnp()](#entrada-btn--btnp))
se cubren arriba donde tienen un envoltorio de más alto nivel. Lo que
queda es o bien hardware en bruto sin ningún envoltorio, o un envoltorio
que solo cubre parte de una categoría. La tabla completa de puertos está
en la [Referencia rápida](#ioports--every-hardware-port).

Una categoría o nombre de propiedad desconocido es un error de
compilación que lista las categorías válidas, no un no-op silencioso ni
una lectura de global no declarada — ver `validate_ioports_path()`.

**ioports.tim.\* — temporizador en bruto**

```lua
local d = ioports.tim.date    -- TIM_CurrentDate:  año * 65536 + día del año
local t = ioports.tim.time    -- TIM_CurrentTime:  segundos desde la medianoche
local f = ioports.tim.frames  -- TIM_FrameCounter: igual que system.frames()
local c = ioports.tim.cycles  -- TIM_CycleCounter: igual que system.cycles()
```

`ioports.tim.date`/`ioports.tim.time` son los registros empaquetados en
bruto que `system.date()`/`system.time()` decodifican en una cadena
formateada y tres números separados — recurre a `system.date()`/
`system.time()` a menos que la representación empaquetada en sí misma sea
lo que se necesita (por ejemplo, almacenar una palabra en una tarjeta de
memoria en lugar de tres campos separados).

**ioports.rng.\* — RNG por hardware**

```lua
local r = ioports.rng.value   -- RNG_CurrentValue, lectura: el siguiente valor aleatorio
ioports.rng.seed = 12345      -- RNG_CurrentValue, escritura: resembrar el generador
```

El mismo registro de hardware subyacente para ambas direcciones — leer
devuelve el valor aleatorio actual (y avanza el generador), escribir lo
resembra. Este es el propio RNG por hardware de la consola, independiente
de `math.random()` (que es un PRNG por software en el tiempo de
ejecución, sembrado por separado) — los dos no comparten estado y no
producirán la misma secuencia a partir de la misma semilla.

**ioports.car.\* — información del cartucho**

```lua
local ok   = ioports.car.connected  -- CAR_Connected,        booleano
local size = ioports.car.romsize    -- CAR_ProgramROMSize,   entero
local ntex = ioports.car.numvtex    -- CAR_NumberOfTextures, entero
local nsnd = ioports.car.numvsnd    -- CAR_NumberOfSounds,   entero
```

Introspección de solo lectura del cartucho actualmente insertado — el
tamaño de su ROM de programa en palabras, y cuántas texturas/sonidos
declaró su cart-XML. Dado que el propio cartucho de un programa en
ejecución siempre está conectado, que `ioports.car.connected` lea `false`
no es un caso que el código de cartucho normal necesite manejar; existe
por completitud de la tabla de puertos más que como una condición de
ramificación práctica; realmente solo algo transaccionado en el BIOS.

**ioports.mem.connected — presencia de tarjeta de memoria**

```lua
if ioports.mem.connected then
    memcard.save(highscore)
end
```

`MEM_Connected`, booleano, solo lectura — si una tarjeta de memoria está
realmente presente antes de que las llamadas de `memcard.*` la toquen.
