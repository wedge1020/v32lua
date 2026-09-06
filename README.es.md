# v32lua: Compilador de Lua para Vircon32

[Versión en inglés / in English](README.md) | [Versión en francés / en français](README.fr.md)

**Arquitectura Objetivo:** Consola de Fantasía Vircon32 (32-bit)

**Lenguaje de Implementación:** C (Flex/Bison + Emisor Semántico Personalizado)

**Repositorio:** [github.com/wedge1020/v32lua](https://github.com/wedge1020/v32lua)

**Referencia de la API:** [doc/API.md](doc/API.md) — la API nativa completa
de Vircon32 (sonido, gráficos, entrada, mapas de mosaicos, tarjeta de
memoria y puertos de E/S en bruto).

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
fantasía retro, `v32lua` cuenta con intrínsecos de hardware de costo cero,
[NaN-boxing](doc/NaN_boxing.md) personalizado y — más allá de la API nativa
de Vircon32 — dos capas de compatibilidad de API para que los cartuchos
escritos para **TIC-80** y **PICO-8** puedan compilarse y ejecutarse en
hardware de Vircon32 con poca o ninguna modificación del código fuente.

```
+------------------+     +-------------------+     +------------------+
| Fuente (.lua)    | --> | Lexer y Parser    | --> | Construcción del  |
+------------------+     | (Flex / Bison)    |     | AST               |
                         +-------------------+     +------------------+
                                                            |
                                                            v
+------------------+     +-------------------+     +------------------+
| Configuración    | <-- | Ensamblador de     | <-- | Emisor Semántico |
| del Cartucho     |     | Vircon32 (.asm)    |     |                  |
| (.xml)           |     |                    |     |                  |
+------------------+     +-------------------+     +------------------+
```

---

## Tabla de Contenidos

- [Primeros Pasos](#primeros-pasos)
  - [Requisitos](#requisitos)
  - [Compilando el Compilador](#compilando-el-compilador)
  - [Objetivos del Makefile](#tabla-de-referencia-de-objetivos-del-makefile)
  - [Tu Primer Cartucho](#tu-primer-cartucho)
  - [Uso desde la Línea de Comandos](#uso-desde-la-línea-de-comandos)
- [Capas de Compatibilidad de API](#capas-de-compatibilidad-de-api)
- [Pistas de Recursos del Cartucho (`--#...`)](#pistas-de-recursos-del-cartucho)
  - [Proyectos Multi-Archivo (`--#include`)](#proyectos-multi-archivo---include)
- [Proceso de Compilación](#proceso-de-compilación)
- [Características Clave del Lenguaje y del Compilador](#características-clave-del-lenguaje-y-del-compilador)
  - [Modelos de Ejecución: `main()` vs `game_loop()`](#modelos-de-ejecución-flexibles-main-vs-game_loop)
  - [NaN-Boxing: Elementos en RAM vs ROM](#nan-boxing-elementos-en-ram-vs-rom)
  - [Intrínsecos de Hardware y Mapeo de E/S](#intrínsecos-de-hardware-y-mapeo-de-es)
  - [Herramientas para el Desarrollador](#experiencia-de-desarrollo-y-herramientas-de-depuración)
- [Características de Lua Soportadas](#características-de-lua-soportadas)
  - [Variables y Ámbito](#variables-y-ámbito)
  - [Asignación Múltiple](#asignación-múltiple)
  - [Programación Orientada a Objetos y Tablas](#programación-orientada-a-objetos-y-tablas)
  - [Flujo de Control](#flujo-de-control)
  - [Operadores y Expresiones](#operadores-y-expresiones)
  - [Funciones y Retornos de Múltiples Valores](#funciones-y-retornos-de-múltiples-valores)
  - [Agrupación de Literales de Cadena](#agrupación-de-literales-de-cadena)
  - [Evaluación Truthy / Falsy con Cortocircuito](#evaluación-truthy--falsy-con-cortocircuito)
- [E/S de Hardware e Intrínsecos del Compilador](#es-de-hardware-e-intrínsecos-del-compilador)
  - [Conversión Automática de Tipos en los Límites de E/S](#conversión-automática-de-tipos-en-los-límites-de-es)
  - [Tabla de Referencia Completa de Intrínsecos](#tabla-de-referencia-completa-de-intrínsecos)
- [Ensamblador en Línea (`__asm__` y `__rawasm__`)](#ensamblador-en-línea-__asm__--__rawasm__)
- [Mapa de Memoria de Referencia](#mapa-de-memoria-de-referencia)
- [Peculiaridades, Supuestos y Limitaciones Conocidas del Compilador](#peculiaridades-y-supuestos-del-compilador)
- [Optimización del Compilador](#optimización-del-compilador)
- [Hoja de Ruta / Aún No Implementado](#hoja-de-ruta--aún-no-implementado)
- [Uso de IA](#uso-de-ia)

---

## Primeros Pasos

### Requisitos

* Una cadena de herramientas de C (`gcc`/`clang` + `make`) capaz de compilar
  fuentes generadas por `flex`/`bison`.
* `flex` y `bison` propiamente dichos, para regenerar el lexer/parser si
  estás compilando desde el árbol de fuentes dividido en lugar de una
  versión pregenerada.
* La cadena de herramientas de Vircon32 (ensamblador y `packrom`) si
  pretendes llegar completamente desde `.lua` hasta un cartucho `.v32`
  ejecutable, más `v32sim` si quieres ejecutar o depurar el resultado.

### Compilando el Compilador

El repositorio incluye un Makefile en la raíz que gestiona la compilación
del binario del compilador, la ejecución de la suite de pruebas y el
mantenimiento general del proyecto. Para compilar el binario principal del
compilador desde el código fuente, ejecuta el objetivo por defecto desde la
raíz del repositorio:

```bash
make
```

Esto produce el binario `v32lua` (bajo `bin/`), que convierte un archivo
fuente `.lua` en un archivo `.asm` de Vircon32 más un `.xml` de cartucho
que lo acompaña. A partir de ahí, ensamblar y empaquetar sigue los mismos
pasos que cualquier otro proyecto de Vircon32 (ensamblar → `packrom` →
ejecutar bajo `v32sim` o en hardware real).

#### Tabla de Referencia de Objetivos del Makefile

| Objetivo | Descripción | Acciones Principales y Dependencias |
| --- | --- | --- |
| **`all`** | **Objetivo por defecto.** Compila el ejecutable principal del compilador. | Invoca el proceso de compilación de forma nativa dentro del subdirectorio `src/`. |
| **`clean`** | Utilidad estándar de limpieza del espacio de trabajo. | Elimina de forma recursiva los artefactos de compilación intermedios de `src/` y borra los archivos generados en `testing/` y `demos/`. |
| **`install`** | Instala el binario del compilador en el sistema anfitrión. | Pasa el objetivo hacia los scripts de instalación localizados en el directorio `src/`. |
| **`tests`** | Ejecuta la suite automatizada de pruebas de compilación. | Depende de que el binario del compilador (`bin/v32lua`) esté compilado primero, y luego activa las rutinas de prueba dentro de `testing/`. |
| **`demos`** | Compila la colección de demos disponibles. | Depende de que el binario del compilador (`bin/v32lua`) esté compilado primero, y luego compila cada demo bajo `demos/`. |
| **`asmcheck`** | Valida la corrección del ensamblador. | Requiere que `bin/v32lua` esté presente, y luego procesa las validaciones de ensamblador a través de la suite `testing/`. |
| **`monofiles`** | Genera variantes de archivo monolítico simplificadas (usadas para pegar todo el proyecto en una conversación de un solo archivo). | Ejecuta el flujo de creación de `monofile` de forma secuencial tanto en `src/` como en `testing/`. |

### Tu Primer Cartucho

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

    -- Actualiza el estado usando matemática de punto flotante pura
    if ioports.inp.left > 1 then
        x_pos = x_pos - speed
    else if ioports.inp.right > 1 then
        x_pos = x_pos + speed
    end

    -- Dibujo directo por hardware
    ioports.gpu.x = x_pos
    ioports.gpu.y = y_pos
    ioports.gpu.draw()

    -- Acceso a tablas y concatenación de cadenas integrada
    local frame = system.frames
    if frame > 1000 then
        local msg = "Demo Running: Frame " .. frame
        print(msg)
    end
end
```

Compílalo con:

```bash
$ v32lua -o program.asm program.lua
```

`v32lua` emite `program.asm` y `program.xml` a su lado; entrega ambos al
ensamblador de Vircon32 y a `packrom` para producir un cartucho ejecutable.

### Uso desde la Línea de Comandos

```bash
$ v32lua [opciones] archivo
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
  al hardware propio de la consola: `ioports.gpu.*`, `ioports.spu.*`,
  `ioports.inp.*`, `music.*`/`sfx.*`, `system.*` y la API nativa
  `tilemap.*`. Documentada por completo en [doc/API.md](doc/API.md).
* **Capa de compatibilidad TIC-80** (`--#api "tic80"`) — llamadas con la
  forma de TIC-80 (`spr()`, `btn()`/`btnp()`, `map()`/`mset()`/`mget()`,
  funciones de sonido/música, y las secciones de recursos al estilo de
  consola de fantasía) compiladas hacia instrucciones nativas de Vircon32,
  incluyendo el escalado de coordenadas necesario para mapear la pantalla
  lógica de 240×136 de TIC-80 a la resolución física de Vircon32.
* **Capa de compatibilidad PICO-8** (`--#api "pico8"`) — el equivalente con
  la forma de PICO-8, en una etapa de completitud anterior a la de la capa
  TIC-80.

Solo una superficie de API está activa por cartucho; seleccionar `tic80` o
`pico8` reemplaza la superficie de llamadas nativa en lugar de añadirse a
ella.

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
| `--#texture NOMBRE "ruta/imagen.png"` | Registra un recurso de textura y lo vincula a una constante `NOMBRE` en tiempo de compilación. |
| `--#sound NOMBRE "ruta/sonido.vsnd"` | Registra un recurso de sonido y lo vincula a una constante `NOMBRE` en tiempo de compilación. |
| `--#tilemap NOMBRE "ruta/mapa.csv"` | Registra un mapa de mosaicos desde un archivo CSV, incrustado directamente en la imagen ROM (ver [doc/API.md](doc/API.md#tilemap-tilemap)). |
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

### Proyectos Multi-Archivo (`--#include`)

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
* Las rutas se resuelven de forma relativa al archivo que incluye; se
  detectan las inclusiones cíclicas, y cada ruta absoluta se incluye como
  máximo una vez a lo largo de toda la expansión.
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

### Flujo de Compilación

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

### Etapas de Compilación (`-v`)

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

### Modelos de Ejecución Flexibles: `main()` vs. `game_loop()`

Para acomodar diferentes estilos de arquitectura de juego, el compilador
admite dos paradigmas distintos de punto de entrada:

* **El Arnés de Ticking Automático (`game_loop`)**: Si tu programa declara
  una función `game_loop()`, el compilador genera automáticamente un
  arnés de ejecución continuo. La CPU llama a `game_loop()`, detiene la
  ejecución del cuadro actual usando la instrucción de hardware `WAIT`, y
  repite indefinidamente. Esto es ideal para juegos de arcade y demos
  estándar, y imita el comportamiento de otras consolas de fantasía.

* **Control Manual (`main`)**: Si tu programa declara una función
  `main()`, el control se entrega directamente a `__function_main`. Tomas
  la propiedad completa del ciclo de cuadro y debes ejecutar manualmente
  ensamblador en línea o esperas de hardware. El compilador rastrea si se
  emite una instrucción `WAIT` dentro de `main()`; si falta, `v32lua`
  emite una advertencia semántica en tiempo de compilación.

* **Gancho de Inicialización**: En ambos modelos, si está presente una
  función `init()`, se garantiza que se ejecute exactamente una vez
  después de las asignaciones de RAM globales de nivel superior y antes
  de que comience el bucle principal.

Un programa debe declarar al menos una de `main()` o `game_loop()` — este
es el punto de entrada designado, y su ausencia es un error de compilación.

### NaN-Boxing: Elementos en RAM vs. ROM

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
| **Tabla / Objeto Empaquetado** | `0xFF800000` | Direcciones de memoria del montículo empaquetadas (Bit 31=1, Bit 22=0). |
| **Número** | Flotante IEEE 754 | Valores de punto flotante nativos de Vircon32 sin empaquetar, para matemática directa. |

### Intrínsecos de Hardware y Mapeo de E/S

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
  argumentos son dinámicos. Consulta [doc/API.md](doc/API.md) para ver la
  superficie completa, incluyendo por qué el orden de escritura de los
  puertos SPU (detener → asignar → volumen → reproducir →
  bucle/posición) es fundamental.

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

Consulta [doc/API.md](doc/API.md) para la referencia completa y
autoritativa — este README resalta las ideas, el documento de la API cubre
cada llamada.

### Experiencia de Desarrollo y Herramientas de Depuración

* **Reporte Visual de Errores en ASCII**: Los errores léxicos, sintácticos,
  semánticos e internos del compilador imprimen fragmentos de código ASCII
  resaltados y de múltiples líneas que apuntan directamente a la línea
  ofensora en el archivo fuente.

* **Mapeo de Fuente a Ensamblador (`-g`)**: Pasar la bandera de depuración
  `-g` genera un archivo `.debug` complementario junto al ensamblador de
  salida. Este archivo mapea los desplazamientos de línea relativos del
  ensamblador de Vircon32 a las líneas originales del código fuente Lua y
  a los puntos de entrada de las funciones, habilitando la depuración
  paso a paso bajo `v32sim`.

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

### Variables y Ámbito

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

### Asignación Múltiple

El compilador admite de forma nativa la asignación múltiple y el
intercambio de variables sin requerir temporales explícitos del usuario:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Sintetiza cadenas de registros temporales para intercambiar valores de forma segura
```

### Programación Orientada a Objetos y Tablas

`v32lua` proporciona azúcar sintáctico transparente para modelos de POO
basados en tablas:

* **Desazucarado de Definición de Métodos:** Definir una función en una
  tabla genera automáticamente una etiqueta con nombre alterado y vincula
  la propiedad del puntero de función:

```lua
function Player.move(dx, dy) ... end
-- Se desazucara a: Player["move"] = __function_Player_move
```

* **Desazucarado de Llamada a Métodos (operador `:`):** Usar el operador
  de dos puntos evalúa automáticamente la expresión de tabla y la inyecta
  como un parámetro implícito `self`:

```lua
Player:move(5, -2)
-- Se desazucara a: Player.move(Player, 5, -2)
```

### Flujo de Control

* **Bucles:** Se admiten sentencias `while <cond> do ... end` con ámbito
  de bloque completo.

* **Control de Bucle:** Las sentencias `break` saltan inmediatamente a la
  etiqueta final del bucle más interno actual (rastreado mediante una
  pila interna de compilación de bucles).

* **Condicionales:** Estructuras `if <cond> then ... elseif <cond> then
  ... else ... end` con ramificación de cortocircuito.

### Operadores y Expresiones

* **Aritméticos:** `+`, `-`, `*`, `/` (mapeados a las instrucciones de
  hardware de punto flotante de Vircon32 `FADD`, `FSUB`, `FMUL`, `FDIV`),
  y menos unario (`-` mediante `__builtin_unm`).

* **Relacionales:** `==`, `~=` (mediante `__builtin_eq` con desempaquetado
  de NaN), `<`, `>`, `<=`, `>=` (mediante hardware `FLT`, `FLE`, `FGT`,
  `FGE`).

* **Lógicos:** `and`, `or`, `not` (con evaluación de cortocircuito).

* **Concatenación de Cadenas:** el operador `..` empuja automáticamente
  los operandos e invoca la subrutina en tiempo de ejecución
  `__builtin_strcat`.

* **Operador de Longitud:** el operador `#` invoca `__builtin_len` para
  resolver longitudes de cadenas o tablas.

### Funciones y Retornos de Múltiples Valores

Las funciones pueden retornar múltiples valores simultáneamente. La
convención de llamada optimiza las primeras tres expresiones retornadas
colocándolas directamente en los registros `R0`, `R2` y `R3`. Cualquier
valor de retorno adicional (4º en adelante) se derrama directamente en el
marco de pila del llamador.

### Agrupación de Literales de Cadena

Todos los literales de cadena declarados en el código fuente (por
ejemplo, `"GAME OVER"`) se recopilan durante la compilación, se
deduplican y se emiten en una sección de datos dedicada al final de la
ROM (`__string_0: string "GAME OVER"`), evitando el consumo redundante de
ROM.

### Evaluación Truthy / Falsy con Cortocircuito

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

## E/S de Hardware e Intrínsecos del Compilador

Una de las características más poderosas de `v32lua` es su **motor de
interceptación de intrínsecos estático**. Cuando el compilador encuentra
accesos a tablas o llamadas a funciones que coinciden con rutas de
sistema específicas (por ejemplo, `ioports.gpu.clear()`), **evita por
completo las búsquedas dinámicas en tablas** y emite instrucciones de E/S
de hardware de Vircon32 directas (`IN`, `OUT`).

### Conversión Automática de Tipos en los Límites de E/S

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

### Tabla de Referencia Completa de Intrínsecos

La referencia completa y autoritativa para cada intrínseco —
`ioports.gpu.*`, `ioports.inp.*`, `ioports.spu.*`, `ioports.tim.*`,
`ioports.rng.*`, `ioports.car.*`, `ioports.mem.*`, `music.*`/`sfx.*`,
`tilemap.*`, `memcard.*` y `system.*` — vive en [doc/API.md](doc/API.md),
incluyendo advertencias sobre el orden de puertos, firmas de llamadas y
ejemplos trabajados. Una breve muestra de las entradas de uso más común:

#### Control y Dibujo GPU (`ioports.gpu.*`)

| Ruta Lua / Intrínseco | Puerto/Comando Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lectura / Escritura | Establece o lee el ID de textura activo usado para las operaciones de dibujo. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lectura / Escritura | Selecciona la sub-región de textura (cuadro de sprite) a renderizar. |
| **`ioports.gpu.x`** / **`ioports.gpu.y`** | `GPU_DrawingPointX/Y` | Lectura / Escritura | Coordenadas de pantalla para la colocación del dibujo. |
| **`ioports.gpu.minX/minY/maxX/maxY`** | `GPU_RegionMin/MaxX/Y` | Lectura / Escritura | Define los límites en píxeles de la región de textura activa. |
| **`ioports.gpu.hotX/hotY`** | `GPU_RegionHotSpotX/Y` | Lectura / Escritura | Establece el origen de dibujo (hotspot) relativo a la región del sprite. |
| **`ioports.gpu.draw([modo])`** | `GPU_Command` | Llamada a Función | Ejecuta un comando de dibujo de hardware: `"zoom"`, `"rotate"`, `"rotozoom"`, o el valor por defecto. |
| **`ioports.gpu.clear([color])`** | `GPU_ClearColor` + `GPU_Command` | Llamada a Función | Establece el color de borrado y limpia la pantalla. Admite cadenas de color preestablecidas (`"black"`, `"white"`, `"blue"`, `"red"`, `"green"`) o valores hexadecimales numéricos. |

#### Mando de Juego y Entrada (`ioports.inp.*`)

| Ruta Lua / Intrínseco | Puerto/Comando Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lectura / Escritura | Selecciona el índice del controlador activo (`0`-`3`) para el sondeo de entrada. |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Solo Lectura | Retorna un booleano de Lua: si el mando seleccionado está conectado. |
| **`ioports.inp.left/right/up/down`** | `INP_Gamepad*` | Solo Lectura | Estado direccional del D-Pad (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.A/B/X/Y/L/R/start`** | `INP_GamepadButton*` | Solo Lectura | Estado de botón de acción/gatillo (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.inputs`** | *Subrutina de Acción Personalizada* | Solo Lectura | **Intrínseco de recopilación:** sondea todos los botones/ejes del mando en una sola pasada, los combina en una única máscara de bits de 32 bits, y la convierte a un flotante de Lua. |

#### Utilidades del Sistema y de Ejecución

| Ruta Lua / Intrínseco | Instrucción Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Llamada a Función | Emite la instrucción de hardware `HLT`, terminando de inmediato la ejecución de la CPU o congelando el cuadro hasta el siguiente ciclo de interrupción/cuadro. |
| **`system.wait()`** | `WAIT` | Llamada a Función | Emite la instrucción de hardware `WAIT`, pausando la ejecución hasta el siguiente ciclo de interrupción/cuadro. |
| **`system.frames`** / **`system.cycles`** | `TIM_FrameCounter` / `TIM_CycleCounter` | Solo Lectura | Contadores continuos de cuadros/ciclos. |
| **`print(x, y, ...)`** | `__builtin_tostring` + `__builtin_print` | Llamada a Función | Convierte los argumentos a su representación en cadena y los envía a la terminal de depuración de la consola. Los primeros dos parámetros son la posición X, Y en pantalla, en píxeles. |

---

## Ensamblador en Línea (`__asm__` y `__rawasm__`)

Para bucles internos críticos en rendimiento o manipulación avanzada del
hardware de Vircon32, `v32lua` proporciona inyección directa de
ensamblador en línea.

### Ensamblador en Línea Estándar (`__asm__`)

La directiva `__asm__` permite incrustar cadenas de ensamblador crudo de
Vircon32 directamente dentro de funciones Lua. Fundamentalmente, admite
**interpolación de variables**, permitiendo un puente fluido entre los
símbolos de ámbito de Lua y los registros de ensamblador:

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )
```

* **Cómo funciona:** Cualquier identificador envuelto en llaves (por
  ejemplo, `{speed}`) es resuelto dinámicamente por
  `emit_interpolated_asm` en tiempo de compilación. Si `speed` es una
  variable local en el desplazamiento de pila 1, `{speed}` se reemplaza
  automáticamente por `[BP - 1]`. Si es una global, se resuelve a
  `[var_speed]`.

* Cada línea de ensamblador interpolado pasa a través del motor de
  formato del compilador, asegurando una indentación y alineación de
  comentarios consistentes en el archivo `.asm` de salida.

* Este ensamblador en línea estándar aplica algunas salvaguardas y
  protecciones leves, en la forma de respaldar cualquier registro
  existente en uso junto con la pila. Aunque no previene problemas, puede
  ayudar a mitigar algunos causados por accidente. Cualquier cambio de
  registro hecho aquí se pierde fuera de la "burbuja" en línea.

### Ensamblador en Bruto (`__rawasm__`)

La directiva `__rawasm__` produce la cadena literal directamente en el
flujo de ensamblador sin ninguna salvaguarda aplicada. Esto puede ser
bastante peligroso, y solo debería usarlo el usuario de ensamblador más
conocedor y experimentado. También es la base del propio arnés de
pruebas unitarias del compilador: un archivo de prueba es típicamente un
envoltorio `function main() ... end` alrededor de una secuencia de
bloques `__rawasm__` con etiquetas `__debugN:` para establecer puntos de
interrupción bajo `v32sim`.

---

## Mapa de Memoria de Referencia

| Dirección RAM | Designación | Uso |
| --- | --- | --- |
| `0` | `HEAP_POINTER` | Almacena la dirección de inicio dinámica para las asignaciones de tablas en tiempo de ejecución. |
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
[`v32opt`](https://github.com/wedge1020/v32opt). Está diseñada como un
optimizador de ensamblador de Vircon32 de propósito general, pensado para
usarse con el compilador de C y el compilador de Lua (junto con
ensamblador escrito a mano). Las pruebas tempranas han mostrado mejoras
leves en el rendimiento, y un ahorro potencial de espacio al eliminar
instrucciones redundantes.

Al momento de escribir esto, esta herramienta todavía está muy en
desarrollo, pero muestra promesa y probablemente funcionará para
escenarios estándar bajo los niveles de optimización `-O1`, `-O2`, e
incluso `-O3`. Está pensada para insertarse en la cadena de compilación
después de compilar y antes de ensamblar.

## Hoja de Ruta / Aún No Implementado

Lo siguiente son brechas conocidas y deliberadas, no errores — ya sea
diferidas para mantener avanzando el desarrollo inicial, o pendientes de
una decisión de diseño:

* `pcall`/`error`/`assert`
* `string.match`/`gmatch`, `setmetatable`
* trabajo adicional en las capas de API de PICO-8 y TIC-80
* `tonumber(s, base)` — la forma de dos argumentos, con base explícita
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
