# API nativa de la consola de fantasía Vircon32

Este documento cubre ÚNICAMENTE la API nativa de Vircon32 — la superficie
activa cuando no está seleccionado ni el modo de compatibilidad
`--#api pico8` ni `--#api tic80`. Bajo esos modos, `spr()`/`btn()`/etc. son
en su lugar la propia API de esa consola (ver la documentación de
compatibilidad PICO-8 / TIC-80), y las llamadas de abajo no están
disponibles.

Archivos: `v32lua_sound_intrinsics.c`, `v32lua_sound_namespaces.c`,
`v32lua_spu_cmd_intrinsic.c`, `v32lua_ioport_boolean.c`,
`intrinsics_vircon32.c`, `intrinsics_vircon32_memcard.c`,
`runtime_vircon32_sound.s`, `runtime_vircon32_sfx.s`, `runtime_vircon32_spr.s`,
`runtime_vircon32_input.s`, `runtime_vircon32_memcard.s`.

Ver también `vircon32-spu-port-ordering.md` — el orden de escritura de los
puertos SPU es importante y todos los emisores de sonido aquí dependen de
él.

---

## Tabla de Contenidos

- [Sonido: music.\* / sfx.\*](#sonido-music--sfx)
  - [Orden de escritura de puertos SPU](#vircon32-spu-el-orden-de-escritura-de-puertos)
  - [music.volume() / sfx.volume()](#musicvolumevol--channel--sfxvolumevol--channel)
  - [Por qué desaparecieron los nombres simples](#por-qué-desaparecieron-los-nombres-simples)
  - [Alias en tiempo de compilación](#alias-en-tiempo-de-compilación)
  - [music.playing()](#musicplaying-y-por-qué-una-bandera-de-lua-es-el-interruptor-equivocado)
  - [Generación de código: plegado híbrido](#generación-de-código-plegado-híbrido)
- [ioports.spu.cmd() — la vía de escape en bruto](#ioportsspucmd--la-vía-de-escape-en-bruto)
- [Puertos de E/S booleanos](#puertos-de-es-booleanos)
- [Sistema: system.\*](#sistema-system)
  - [system.wait() / system.halt()](#systemwait--systemhalt)
  - [system.date() / system.time()](#systemdate--systemtime)
  - [system.frames / system.cycles](#systemframes--systemcycles)
- [Gráficos: spr()](#gráficos-spr)
  - [Despacho en tiempo de ejecución](#despacho-en-tiempo-de-ejecución-no-plegado-en-tiempo-de-compilación)
  - [ioports.gpu.clear()](#ioportsgpuclearcolor)
  - [Definiendo regiones de textura](#definiendo-regiones-de-textura)
- [Entrada: btn() / btnp()](#entrada-btn--btnp)
  - [IDs de botones](#ids-de-botones)
  - [btn(): sondeo directo](#btn-sondeo-directo)
  - [btnp(): detección de flanco](#btnp-detección-de-flanco)
  - [ioports.inp.inputs](#ioportsinpinputs--máscara-de-una-palabra)
  - [Lo que deliberadamente no está aquí](#lo-que-deliberadamente-no-está-aquí)
- [Mapa de mosaicos: tilemap.\*](#mapa-de-mosaicos-tilemap)
  - [--#tilemap y el formato CSV](#tilemap-nombre-archivo-y-el-formato-csv)
  - [tilemap.get() / tilemap.set()](#tilemapget--tilemapset)
  - [Promoción perezosa de ROM a RAM](#promoción-perezosa-de-rom-a-ram)
  - [tilemap.render()](#tilemaprender)
  - [Lo que deliberadamente no está aquí](#lo-que-deliberadamente-no-está-aquí-1)
- [Otros puertos de E/S en bruto](#otros-puertos-de-es-en-bruto)
  - [ioports.tim.\* — temporizador en bruto](#ioportstim--temporizador-en-bruto)
  - [ioports.rng.\* — RNG por hardware](#ioportsrng--rng-por-hardware)
  - [ioports.car.\* — información del cartucho](#ioportscar--información-del-cartucho)
  - [ioports.mem.connected — presencia de tarjeta de memoria](#ioportsmemconnected--presencia-de-tarjeta-de-memoria)
- [Tarjeta de memoria: memcard.\*](#tarjeta-de-memoria-memcard)
  - [memcard.save() / memcard.load()](#memcardsave--memcardload)
  - [memcard[position]](#memcardposition)
  - [memcard.title()](#memcardtitlestr---nil)
  - [Tablas: memcard.save() / memcard.load_table()](#tablas-memcardsave--memcardload_table)
  - [Diseño de direcciones](#diseño-de-direcciones)
  - [Etiquetas de tipo (solo la forma de auto-anexado)](#etiquetas-de-tipo-solo-la-forma-de-auto-anexado)
  - [Lo que deliberadamente no está aquí](#lo-que-deliberadamente-no-está-aquí-2)

---

# Sonido: music.\* / sfx.\*

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

## Vircon32 SPU: el orden de escritura de puertos

### La regla

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

### Estados de canal y qué significa realmente resume

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

### Tipos de puerto

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

## music.volume(VOL [, CHANNEL]) / sfx.volume(VOL [, CHANNEL])

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

### Seguimiento de propiedad de canal

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

### Generación de código

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

## Por qué desaparecieron los nombres simples

`play` / `pause` / `resume` / `stop` eran los cuatro identificadores más
propensos a colisión que un juego podría querer para sí mismo, que es lo
que la antigua salvaguarda de desvío `resolve_symbol()` en el despachador
solucionaba. Han desaparecido; los espacios de nombres los reemplazan, y el
mecanismo de alias los restaura por elección en lugar de por defecto.

## Alias en tiempo de compilación

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

## music.playing() y por qué una bandera de Lua es el interruptor equivocado

`SPU_ChannelState` es un puerto entero de solo lectura que devuelve
`channel_stopped` 0x40, `channel_paused` 0x41, `channel_playing` 0x42.
`music.playing(ch)` selecciona el canal, lo lee, y devuelve un booleano de
Lua real.

Un interruptor de pausa/resume construido sobre una bandera de Lua se
desincroniza en el momento en que un sonido termina por sí solo: el
programa todavía cree que se está reproduciendo, así que la siguiente
pulsación pausa un canal ya detenido en lugar de reanudarlo. Preguntarle al
hardware no puede desincronizarse.

## Generación de código: plegado híbrido

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

# ioports.spu.cmd() — la vía de escape en bruto

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

# Puertos de E/S booleanos

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

# Sistema: system.\*

```
system.wait()   -> nil   (WAIT hasta la siguiente señal de nuevo ciclo)
system.halt()   -> nil   (HLT -- detiene la CPU)
system.date()   -> cadena, año, mes, día
system.time()   -> cadena, hora, minuto, segundo
```

## system.wait() / system.halt()

`system.wait()` compila directamente a `WAIT` — la misma instrucción que
usa `ioports.gpu.sync()`, e intercambiable con ella; ambas simplemente
esperan la siguiente señal de nuevo ciclo del temporizador. `system.halt()`
compila a `HLT`, deteniendo la CPU por completo — para un programa que ha
completado su trabajo y no le queda nada por renderizar.

## system.date() / system.time()

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

## system.frames / system.cycles

```lua
local f = system.frames()   -- TIM_FrameCounter -- cuadros desde el encendido
local c = system.cycles()   -- TIM_CycleCounter -- ciclos de CPU desde el encendido
```

Ambos son contadores de hardware de solo lectura, monótonos desde el
arranque — a diferencia de `system.date()`/`system.time()`, estos **no**
son de reloj de pared: miden el tiempo de ejecución propio de la consola,
no el reloj en tiempo real. `system.frames()` es el ajuste natural para
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

# Gráficos: spr()

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
| `blend_mode` | `VIRCON32_BLEND_ALPHA` (`0x20`) | ver los modos de mezcla abajo |

Un argumento puede **omitirse** (simplemente dejar de suministrar
argumentos finales) o pasarse como un **`nil` explícito** para saltarlo y
llegar a uno posterior — `spr(id, x, y, nil, nil, 45)` para rotar sin
tocar la escala — ambos significan "usa el valor por defecto."

Modos de mezcla:

| Constante | Valor |
|---|---|
| `VIRCON32_BLEND_ALPHA` | `0x20` |
| `VIRCON32_BLEND_ADD` | `0x21` |
| `VIRCON32_BLEND_SUBTRACT` | `0x22` |

`spr()` no devuelve nada (`nil` de Lua), a la par de que la consola no
tiene ningún valor significativo que devolver de una llamada de dibujo.
Más de 8 argumentos es una advertencia en tiempo de compilación; los
extras se ignoran.

## Despacho en tiempo de ejecución, no plegado en tiempo de compilación

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

El valor por defecto de `color_mult`, `0xFFFFFFFF`, se pasa a través de la
convención de llamada como un flotante de Lua, y `4294967295.0` no es
exactamente representable en un flotante de 32 bits — se redondea hacia
arriba a `4294967296.0`. El tiempo de ejecución lo convierte mediante
`CFI` (flotante → patrón de bits entero) en lugar de usarlo directamente,
lo cual recupera el `0xFFFFFFFF` correcto de todos modos.

Un `nil` pasado explícitamente para un argumento opcional (por ejemplo,
`spr(id, x, y, nil, nil, 45)`) se trata idénticamente a que ese argumento
esté completamente omitido — ambos recurren al valor por defecto. Una
llamada situada en un contexto de expresión (`local unused = spr(1, 10, 10)`)
recibe correctamente `nil` asignado, igual que cualquier otro intrínseco
en este archivo.

## ioports.gpu.clear([color])

Limpia la pantalla: escribe `GPU_ClearColor` (si se da un argumento de
color) y luego emite `GPUCommand_ClearScreen`. `color` acepta ya sea un
entero RGBA empaquetado o una de cinco cadenas de nombre preestablecidas —
`"black"`, `"white"`, `"blue"`, `"red"`, `"green"` — resueltas en tiempo
de compilación cuando es un literal de cadena. Omite el argumento para
limpiar con lo que `GPU_ClearColor` contenga actualmente.

```lua
ioports.gpu.clear("black")
ioports.gpu.clear(0xFF202020)   -- RGBA empaquetado, no un nombre preestablecido
ioports.gpu.clear()             -- reutiliza el último ClearColor establecido
```

## Definiendo regiones de textura

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

**`hotX`/`hotY` deben establecerse a los mismos valores que `minX`/`minY`,
no a `0`.** Esto se descubrió de la manera difícil al construir
`tilemap.render()`: una región cuyo hotspot se deja sin establecer (o se
pone en cero explícitamente) se dibuja desplazada hacia abajo y hacia la
derecha aproximadamente por su propio `minX`/`minY` — una región recortada
cerca de la esquina superior-izquierda de la hoja se ve bien, que es
exactamente lo que hizo esto fácil de pasar por alto al principio, pero
una región recortada más adentro en la hoja se desvía tanto como de
adentro se recortó. Establecer `hotX`/`hotY` para que coincidan con
`minX`/`minY` ancla el punto de dibujo en la propia esquina
superior-izquierda de la región, que es lo que todo ejemplo en este
documento asume que significa `spr(id, x, y, ...)`. Esto necesita hacerse
para **cada** región que un cartucho defina — no es una configuración
global de una sola vez.

`GPU_RegionMinX/MinY/MaxX/MaxY/HotSpotX/HotSpotY` son los puertos en bruto
detrás de `ioports.gpu.minX` etc. — ver la tabla completa de puertos en
[Otros puertos de E/S en bruto](#otros-puertos-de-es-en-bruto) para todo
lo demás que `ioports.gpu.*` expone (punto de dibujo, escala, ángulo,
color de multiplicación, mezcla, y el contador de solo lectura de
GPU-ocupada `ioports.gpu.pixels`).

---

# Entrada: btn() / btnp()

```
btn(id [, player])   -> booleano, actualmente mantenido presionado
btnp(id [, player])  -> booleano, verdadero solo en el cuadro en que se presionó por primera vez
```

`player` selecciona un mando 0–3 (`INP_SelectedGamepad`); omitido o `nil`
usa el mando que ya esté seleccionado sin escribir el puerto.

## IDs de botones

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

## btn(): sondeo directo

`__builtin_vircon32_btn` lee el puerto `INP_Gamepad*` mapeado para el
mando seleccionado y devuelve `true` cuando el hardware reporta que está
presionado (`>= 1`).

## btnp(): detección de flanco

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

## ioports.inp.inputs — máscara de una palabra

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

## Lo que deliberadamente NO está aquí

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

# Mapa de mosaicos: tilemap.\*

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

## --#tilemap NOMBRE "archivo" y el formato CSV

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

## tilemap.get() / tilemap.set()

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

## Promoción perezosa de ROM a RAM

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

## tilemap.render()

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

## Lo que deliberadamente NO está aquí

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

# Otros puertos de E/S en bruto

Cada puerto `ioports.*` vive en una sola tabla (`IOPortMap` de `core.c`),
organizada bajo seis categorías: `tim`, `rng`, `gpu`, `spu`, `inp`, `car`,
`mem`. Las categorías de sonido (`spu`), gráficos (`gpu`, parcialmente —
ver [Definiendo regiones de textura](#definiendo-regiones-de-textura)), y
entrada (`inp`, parcialmente — ver [btn()/btnp()](#entrada-btn--btnp))
se cubren arriba donde tienen un envoltorio de más alto nivel. Lo que
queda es o bien hardware en bruto sin ningún envoltorio, o un envoltorio
que solo cubre parte de una categoría.

Una categoría o nombre de propiedad desconocido es un error de
compilación que lista las categorías válidas, no un no-op silencioso ni
una lectura de global no declarada — ver `validate_ioports_path()`.

## ioports.tim.\* — temporizador en bruto

```lua
ioports.tim.date     -- TIM_CurrentDate,   solo lectura, entero empaquetado
ioports.tim.time     -- TIM_CurrentTime,   solo lectura, entero empaquetado
ioports.tim.frames    -- TIM_FrameCounter, solo lectura -- igual que system.frames()
ioports.tim.cycles    -- TIM_CycleCounter, solo lectura -- igual que system.cycles()
```

`ioports.tim.date`/`ioports.tim.time` son los registros empaquetados en
bruto que `system.date()`/`system.time()` decodifican en una cadena
formateada y tres números separados — recurre a `system.date()`/
`system.time()` a menos que la representación empaquetada en sí misma sea
lo que se necesita (por ejemplo, almacenar una palabra en una tarjeta de
memoria en lugar de tres campos separados).

## ioports.rng.\* — RNG por hardware

```lua
ioports.rng.value            -- RNG_CurrentValue, lectura: el valor aleatorio actual
ioports.rng.seed = 12345      -- RNG_CurrentValue, escritura: resembrar el generador
```

El mismo registro de hardware subyacente para ambas direcciones — leer
devuelve el valor aleatorio actual (y avanza el generador), escribir lo
resembra. Este es el propio RNG por hardware de la consola, independiente
de `math.random()` (que es un PRNG por software en el tiempo de
ejecución, sembrado por separado) — los dos no comparten estado y no
producirán la misma secuencia a partir de la misma semilla.

## ioports.car.\* — información del cartucho

```lua
ioports.car.connected  -- CAR_Connected,          booleano, solo lectura
ioports.car.romsize    -- CAR_ProgramROMSize,     entero, solo lectura
ioports.car.numvtex    -- CAR_NumberOfTextures,   entero, solo lectura
ioports.car.numvsnd    -- CAR_NumberOfSounds,     entero, solo lectura
```

Introspección de solo lectura del cartucho actualmente insertado — el
tamaño de su ROM de programa en palabras, y cuántas texturas/sonidos
declaró su cart-XML. Dado que el propio cartucho de un programa en
ejecución siempre está conectado, que `ioports.car.connected` lea `false`
no es un caso que el código de cartucho normal necesite manejar; existe
por completitud de la tabla de puertos más que como una condición de
ramificación práctica; realmente solo algo transaccionado en el BIOS.

## ioports.mem.connected — presencia de tarjeta de memoria

```lua
if ioports.mem.connected then
    memcard.save(highscore)
end
```

`MEM_Connected`, booleano, solo lectura — si una tarjeta de memoria está
realmente presente antes de que las llamadas de `memcard.*` la toquen.

---

# Tarjeta de memoria: memcard.\*

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

## memcard.save() / memcard.load()

Hay dos formas distintas, elegidas según si se da una `position`:

**Con una `position` explícita** — la primitiva de bajo nivel. Escribe (o
lee) exactamente una palabra en bruto en `position`, sin ningún tipo de
contabilidad. `position 0` es la primera palabra de la región de datos;
ver [Diseño de direcciones](#diseño-de-direcciones) abajo para el rango
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
longitud, ver [Etiquetas de tipo](#etiquetas-de-tipo-solo-la-forma-de-auto-anexado)),
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
[Etiquetas de tipo](#etiquetas-de-tipo-solo-la-forma-de-auto-anexado)), o
simplemente saber qué escribiste ahí.

## memcard[position]

`memcard[position]` y `memcard[position] = value` son abreviaturas de la
forma de posición explícita de `load`/`save` de arriba — nunca de la
forma de auto-anexado, ya que la sintaxis de corchetes de Lua no tiene
forma de decir "sin índice".

```lua
memcard[0] = 1234
local hi = memcard[0]        -- 1234
memcard[-1]                  -- lee el cursor de auto-anexado
```

## memcard.title(str) -> nil

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

## Tablas: memcard.save() / memcard.load_table()

`memcard.save(a_table)` — **solamente** la forma de auto-anexado sin
posición — escribe un **volcado en bruto** del contenido de la tabla: un
recorrido directo de su almacenamiento interno de cubetas hash (hash
buckets), de la misma forma en que harías `fwrite()` de un struct a un
archivo en C. No es un serializador recursivo general.

```lua
local highscores = { alice = 500, bob = 350, carol = 900 }
memcard.save(highscores)

local restored = memcard.load_table(0)
print(restored.alice)   -- 500
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
[Nota de seguridad](#nota-de-seguridad)) — un volcado de tabla no lo
cruza, simplemente lo aplica por entrada en lugar de una sola vez.

**`memcard.load_table(position)`** reconstruye una tabla nueva a partir de
un volcado escrito de esta forma. `position` es **obligatoria** — a
diferencia de `memcard.load()`, no hay un valor por defecto sensato de
"posición 0" para algo cuyo tamaño en palabras no se conoce hasta que se
lee la propia entrada. Valida la palabra de etiqueta antes de confiar en
nada después de ella; leer en una posición que no contiene un volcado de
tabla devuelve `nil` en lugar de leer mal palabras no relacionadas como un
conteo de pares y claves/valores basura.

## Diseño de direcciones

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

## Etiquetas de tipo (solo la forma de auto-anexado)

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
[Tablas](#tablas-memcardsave--memcardload_table) arriba.

### Nota de seguridad

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

## Lo que deliberadamente NO está aquí

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
