# v32lua: Compilador de Lua para Vircon32

[Versión en inglés / English version](README.md) | [Versión en holandés / Nederlandse versie](README.nl.md)

**Arquitectura de destino:** Consola de fantasía Vircon32 (32 bits)

**Lenguaje de implementación:** C (Flex/Bison + Emisor semántico personalizado)

**Repositorio:** [github.com/wedge1020/v32lua](https://www.google.com/search?q=https://github.com/wedge1020/v32lua)

`v32lua` es un compilador de Lua escrito en C diseñado para la consola de fantasía **Vircon32**. En lugar de integrar un pesado intérprete de bytecode, `v32lua` analiza el código fuente de Lua y lo compila directamente a código ensamblador nativo de Vircon32, generando también las definiciones XML del cartucho.

Aunque todavía no está terminado, uno de los objetivos del desarrollo es hacer de `v32lua` una alternativa (en ningún caso un reemplazo) al compilador de C de Vircon32 en el entorno de desarrollo de la consola. Básicamente, puedes elegir tu lenguaje preferido (C o Lua) y, una vez compilado, obtienes el código ensamblador para continuar con la compilación independientemente del lenguaje de implementación original. Por ello, se ha procurado imitar diversos comportamientos del compilador de C de Vircon32 para que la sustitución entre compiladores sea lo más transparente posible.

Diseñado desde cero teniendo en cuenta las limitaciones de una consola retro de fantasía, este compilador ofrece funciones intrínsecas de hardware de coste cero, un sistema personalizado de [NaN-boxing](doc/NaN_boxing.md), optimizaciones *peephole* algebraicas y un rico conjunto de herramientas de desarrollo diseñadas para facilitar la creación de tus juegos en Lua.

```
+------------------+     +-------------------+     +------------------+
| Fuente (.lua)    | --> | Léxico y Parser   | --> | Construcción AST |
+------------------+     | (Flex / Bison)    |     +------------------+
                         +-------------------+              |
                                                            v
+------------------+     +-------------------+     +------------------+
| Config Cartucho  | <-- | Emisor de Ensamb. | <-- | Emisor Semántico |
| (.xml)           |     | Vircon32 (.asm)   |     | y Opt. Peephole  |
+------------------+     +-------------------+     +------------------+

```

---

## Interacción con la IA

NOTA: Se ha hecho un uso y una interacción extensos con la IA a lo largo de este proyecto. Debe hacerse una distinción respecto al "*vibe coding*", pero ciertamente existe una línea difusa entre el ser humano y la IA. Al final, ambos se benefician y pueden compensar las deficiencias del otro.

En realidad, este proyecto no trataba principalmente sobre el desarrollo de un compilador; comenzó como un intento honesto de comprender la IA y su impacto: su papel y su detrimento en el pensamiento humano y la educación. El hecho de que tenga una temática de compilador fue simplemente para acentuar un punto de interés. Sin duda, ha sido una experiencia de aprendizaje. Si no se hubieran tenido los conocimientos previos y los conceptos suficientes sobre compiladores al empezar, el esfuerzo habría terminado con un menor éxito.

---

## 🚀 Características principales y nuevos desarrollos

### Modelos de ejecución flexibles: `main()` frente a `game_loop()`

Para adaptarse a diferentes estilos de arquitectura de juegos, el compilador admite dos paradigmas distintos para el punto de entrada:

* **El arnés de ejecución continua (`game_loop`)**: Si tu programa declara una función `game_loop()`, el compilador genera automáticamente un arnés de ejecución continua en tiempo de ejecución. La CPU llama a `game_loop()`, detiene la ejecución del fotograma actual utilizando la instrucción de hardware `WAIT` y entra en un bucle infinito. Esto es ideal para juegos arcade estándar y demos. Esto imita el comportamiento de varias otras consolas de fantasía.
* **Control manual (`main`)**: Si tu programa declara una función `main()`, el control se transfiere directamente a `__function_main`. Asumes el control total del ciclo de fotogramas y debes ejecutar manualmente código ensamblador en línea o esperas (*waits*) de hardware. El compilador supervisa si se emite una instrucción `WAIT` dentro de `main()`; si falta, `v32lua` emite una advertencia semántica en tiempo de compilación.
* **Gancho de inicialización (*Initialization Hook*)**: En ambos modelos, si existe una función `init()`, se garantiza que se ejecutará exactamente una vez después de las asignaciones de memoria RAM global de nivel superior y antes de que comience el bucle principal.

### NaN-Boxing mejorado: Elementos en RAM frente a ROM

`v32lua` utiliza una arquitectura de etiquetado (*tagging*) de 32 bits que empaqueta los metadatos de tipo y los punteros de carga útil (*payload*) en valores unificados. Las mejoras recientes separan estrictamente los **elementos ROM** inmutables de los **objetos del montículo RAM (*heap*)** dinámicos para garantizar la seguridad de la memoria y referencias a literales sin copias (*zero-copy*):

| Tipo de dato | Máscara Hex / Etiqueta | Descripción de la arquitectura |
| --- | --- | --- |
| **Nil** | `0xFFC00000` | Representación canónica para valores indefinidos/ausentes. |
| **Booleano Falso** | `0xFFC00001` | Valor falso (*falsy*) de evaluación de cortocircuito. |
| **Booleano Verdadero** | `0xFFC00002` | Valor verdadero (*truthy*) de evaluación de cortocircuito. |
| **Cadena en ROM** | `0x7FC00000` | Punteros a secciones de datos de cadenas de solo lectura (`__string_%d`) en ROM. |
| **Función / Clausura** | `0xFF800000` | Direcciones de memoria de función encapsuladas (*boxed*) (Bit 31=1, Bit 22=0). |
| **Número** | Flotante IEEE 754 | Valores de coma flotante nativos de Vircon32 sin encapsular para cálculos matemáticos directos. |

### Funciones intrínsecas de hardware ampliadas y mapeo de E/S

Los juegos de alto rendimiento en Vircon32 no pueden permitirse búsquedas en tablas de hash para la manipulación del hardware. `v32lua` intercepta expresiones específicas de acceso a miembros de tablas y las compila directamente en instrucciones de E/S de hardware nativas:

* **Acceso a hardware de coste cero**: El acceso a espacios de nombres como `ioports.gpu.*`, `ioports.spu.*`, `ioports.tim.*` o `system.*` (por ejemplo, `ioports.gpu.x = 100` o `system.frames`) omite por completo las rutinas de búsqueda en tablas. Se compilan directamente a operaciones de puerto de hardware (como `GPU_DrawingPointX` o `TIM_FrameCounter`).
* **Sondeo de mando consolidado y entradas tradicionales**: El sondeo de la entrada del mando se optimiza en una sola variable intrínseca (`ioports.inp.inputs`). El compilador sondea desde `INP_GamepadLeft` hasta `INP_GamepadButtonR`, recopila los estados activos de los botones en una máscara de enteros de 32 bits desplazados y la convierte a un flotante de Lua en un solo registro. Las entradas de mando independientes también están disponibles (`ioports.inp.left`, `ioports.inp.A`, etc.) como variables intrínsecas para su uso.
* **Rutas rápidas integradas (*Built-in Fast Paths*)**: Las operaciones estándar de Lua, como la concatenación de cadenas (`..`), la longitud (`#`) y el menos unario (`-`), se asignan directamente a subrutinas optimizadas en tiempo de ejecución (`__builtin_strcat`, `__builtin_len`, `__builtin_unm`).

### Tubería de compilación con optimización (`-O1`)

NOTA: las optimizaciones del compilador son un trabajo en progreso. Aunque se ha preparado la infraestructura, aún queda por realizar un trabajo exhaustivo de pruebas, y es muy probable que cause fallos (y graves). Solo la **optimización *peephole*** y la **omisión del puntero de marco (*frame pointer omission*)** han sido probadas de manera significativa, y ambas podrían estar fallando actualmente debido a otros cambios recientes en el compilador. Probablemente sea mejor no activar las optimizaciones en este momento si deseas obtener un resultado funcional.

Cuando la optimización se activa mediante las flags de línea de comandos (`o_optflag >= 1`), `v32lua` aplica transformaciones de código en múltiples etapas:

* **Optimización *Peephole***: Examina el código ensamblador emitido para eliminar transferencias redundantes a un mismo registro (`MOV R0, R0`) y recargas de memoria innecesarias (`MOV A, B` seguido inmediatamente por `MOV B, A`).
* **Simplificación algebraica**: Resuelve operaciones aritméticas neutras de coma flotante en tiempo de compilación. Expresiones como `x + 0.0`, `x * 1.0`, `x - 0.0` y `x / 1.0` se simplifican directamente a `x`. Las expresiones puras multiplicadas por cero (`x * 0.0`) se optimizan directamente a `0.000000` sin evaluar el operando izquierdo si no conlleva efectos secundarios.
* **Omisión del puntero de marco (Funciones hoja / *Leaf Functions*)**: Las funciones que no declaran variables locales, no aceptan parámetros ni empujan marcos de pila eliminan por completo el prólogo y epílogo estándar de `PUSH BP` / `MOV BP, SP`, ejecutándose como saltos simples.
* **Eliminación de saltos y de almacenamiento muerto (*Dead Store & Branch Elimination*)**: Integra la propagación de constantes y tablas de seguimiento DSE (`DeadStoreCandidate`, `ConstSymbol`) para eliminar ramas condicionales inalcanzables y escrituras de variables no utilizadas.

### Experiencia de desarrollo y herramientas de depuración

* **Informes visuales de errores en ASCII**: Los errores léxicos, sintácticos, semánticos e internos del compilador muestran fragmentos de código ASCII resaltados en varias líneas que señalan directamente a la línea que provoca el error en el archivo de origen (`yyin`).
* **Mapeo de código fuente a ensamblador (`-g`)**: Pasar la flag de depuración `-g` genera un archivo `.debug` complementario junto al código ensamblador de salida. Este archivo asigna las compensaciones (*offsets*) relativas de línea del ensamblador de Vircon32 a las líneas originales del código fuente de Lua y a los puntos de entrada funcionales, lo que permite la depuración paso a paso. Esto debería ser idéntico a la opción `-g` del compilador de C.
* **Burbujas de ensamblador en línea y puro**: Puedes escribir código ensamblador nativo directamente dentro de Lua utilizando `__asm__("tu ASM")` (que guarda y restaura de manera segura los punteros de pila y los registros de propósito general bloqueados `R0`-`R13`) o `__rawasm__("tu ASM")` para una ejecución sin protecciones. Ambos modos admiten la interpolación de cadenas de variables de Lua utilizando la misma sintaxis `{var_name}` presente en el compilador de C (el ensamblador en línea funciona, pero la interpolación aún necesita pruebas).

---

## 🛠️ Directivas de recursos para el cartucho

`v32lua` te permite incrustar metadatos del cartucho de Vircon32 directamente en tu código fuente de Lua utilizando comentarios de bloque especiales. El compilador analiza estas directivas (*hints*) para autogenerar la definición ROM `.xml` del proyecto y asignar ID de recursos de hardware secuenciales.

Las directivas admitidas incluyen:

* `--#version "X.Y"` influye en el campo de versión del cartucho en el XML
* `--#title "TITULO"` establece el título del CART
* `--#texture var "ruta/imagen.png"` configura una textura del juego
* `--#sound var "ruta/sonido.wav"` configura un sonido del juego (no implementado aún)

```lua
--#version "1.1"
--#title "Space Grinder: Tech Demo"

-- Registrar texturas (asocia automáticamente 'bg_space' al ID 0, y 'spr_ship' al ID 1)
--#texture bg_space "assets/background.png"
--#texture spr_ship "assets/player.png"

function init()
    -- ¡Las variables declaradas en las directivas están disponibles globalmente en Lua en tiempo de ejecución!
    ioports.gpu.texture = bg_space
end

```

Una vez compilado, `v32lua` genera tanto el código ensamblador `.asm` compilado como un archivo completo de definición de cartucho XML de Vircon32 que enlaza los activos `.vtex` y `.vsnd`. Con esto, y con el procesamiento adecuado de cualquier dato PNG y WAV, puedes proceder al paso `packrom`.

---

## 💻 Demostración técnica: Programa de ejemplo

Aquí tienes un ejemplo completo que demuestra las características de `v32lua`, incluidas las funciones intrínsecas de hardware y el bucle de juego de avance automático:

```lua
--#title "v32lua Tech Demo"
--#version "1.0"
--#texture tex_logo "logo.png"

x_pos = 160.0
y_pos = 120.0
speed = 2.5

function init()
    -- Establecer el color de limpieza de fondo usando mapeos de puerto de GPU de coste cero
    ioports.gpu.bgcolor = 0xFF003366
    ioports.gpu.texture = tex_logo -- establecer textura
    ioports.gpu.region  = 0 -- establecer región

    -- definir la región
    ioports.gpu.minX    = 0
    ioports.gpu.minY    = 0
    ioports.gpu.maxX    = 100
    ioports.gpu.maxY    = 50
    ioports.gpu.hotX    = 0
    ioports.gpu.hotY    = 0
end

function game_loop()

    -- Actualizar el estado utilizando matemáticas puras de coma flotante
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

---

## 📦 Tubería del compilador y uso

### Flujo de compilación

1. **Análisis léxico y sintáctico**: Flex/Bison analiza el código fuente de Lua y lo convierte en un Árbol de Sintaxis Abstracta (AST) tipado.
2. **Resolución de símbolos y alcances**: Resuelve las variables a través de los alcances léxicos, asignando las globales a direcciones RAM secuenciales a partir de `1` y las locales a posiciones del marco de pila `[BP - offset]`.
3. **Generación de código y optimización *Peephole***: Emite instrucciones de ensamblador de Vircon32 mientras aplica transformaciones `-O1` y sustituciones de funciones intrínsecas de hardware.
4. **Ensamblado del cartucho**: Emite el archivo `.asm` final, integra las bibliotecas de soporte en tiempo de ejecución, genera la sección de datos de cadenas de solo lectura y genera la definición XML del cartucho.

### Integración en línea de comandos

```bash
# Compilar con optimizaciones y generación de símbolos para depuración
$ v32lua -O1 -g -o program.asm program.lua

```

Opciones disponibles:

* `-O0`: Desactiva las optimizaciones del compilador (por defecto)
* `-O1`: Activa optimizaciones *peephole*, simplificación algebraica y omisión del puntero de marco
* `-g`: Genera el archivo de texto de asignación de líneas `program.asm.debug`
* `-o`: Especifica el nombre del archivo de salida del ensamblador (por defecto en stdout si se omite)
* `-v`: Salida más detallada (*verbose*)
* `-w`: Suprime cualquier advertencia del compilador
* `--version`: Muestra la información sobre el autor y la versión del compilador
* `--help`, `-h`: Muestra las instrucciones de uso en línea de comandos

### Etapas de compilación

Cuando se activa `-v`, `v32lua` informa de su progreso a través de cinco etapas principales de la tubería:

1. **Etapa 1: Analizador léxico (*Lexer*)** — Convierte el código fuente de Lua en tokens, eliminando los comentarios estándar y procesando las secuencias de escape de cadenas (`\n`, `\t`, `\r`, `\\`, `\"`).
2. **Etapa 2: Preprocesador** — Evalúa las directivas del cartucho (`--#...`) y las sintaxis de comentarios personalizadas.
3. **Etapa 3: Analizador sintáctico (*Parser*)** — Construye un Árbol de Sintaxis Abstracta (AST) completo utilizando una gramática LALR(1) de Bison con estricta precedencia de operadores (PEMDAS + núcleo lógico).
4. **Etapa 4: Analizador semántico** — Ejecuta una pasada previa de funciones para registrar símbolos de funciones globales, inicializar el alcance global y resolver anotaciones de tipo.
5. **Etapa 5: Emisor** — Recorre el AST para generar código ensamblador de Vircon32, aplicando la asignación de registros, los desplazamientos (*offsets*) de alcance y las optimizaciones *peephole*. Finalmente, genera el archivo XML de configuración del cartucho.

---

## Instrucciones de compilación y objetivos del Makefile

El repositorio incluye un Makefile en el nivel raíz para gestionar la compilación del binario del compilador, las pruebas automatizadas, el despliegue y el mantenimiento del código.

### Instrucciones de compilación

Para compilar el binario principal del compilador desde el código fuente, ejecuta el objetivo por defecto desde el directorio raíz:

```bash
make

```

### Tabla de referencia de los objetivos del Makefile

| Objetivo | Descripción | Acciones principales y dependencias |
| --- | --- | --- |
| **`all`** | **Objetivo por defecto.** Compila el ejecutable principal del compilador. | Invoca el proceso de compilación de forma nativa dentro del subdirectorio `src/`. |
| **`clean`** | Utilidad estándar de limpieza del espacio de trabajo. | Elimina de forma recursiva los artefactos de compilación intermedios de `src/` y borra los archivos generados en `testing/` y `demos/`. |
| **`install`** | Instala el binario del compilador en el sistema anfitrión. | Transfiere el objetivo a los scripts de instalación localizados del directorio `src/`. |
| **`tests`** | Ejecuta el conjunto de pruebas de compilación automatizadas. | Depende explícitamente de que se haya compilado primero el binario del compilador (`bin/v32lua`), y luego ejecuta las rutinas de prueba dentro de `testing/`. |
| **`demos`** | Compila la colección de demos disponibles. | Depende explícitamente de que se haya compilado primero el binario del compilador (`bin/v32lua`), y luego compila cada demo en `demos/`. |
| **`asmcheck`** | Valida la corrección del código ensamblador. | Requiere que `bin/v32lua` esté presente y luego procesa las validaciones de ensamblador mediante el conjunto `testing/`. |
| **`monofiles`** | Genera variantes de archivos monolíticos optimizados. | Ejecuta el flujo de trabajo de creación de `monofile` secuencialmente tanto en `src/` como en `testing/`. |

### Evaluación de cortocircuito de valores verdaderos y falsos (*Truthy & Falsy*)

En Lua, solo `nil` y `false` se evalúan como falsos en expresiones condicionales; cualquier otro valor (incluidos `0` y las cadenas vacías) es **verdadero (*truthy*)**. `v32lua` implementa esto mediante dos primitivas de emisión de ensamblador de alta velocidad:

* **`emit_falsy_jump(reg, label)`**: Comprueba si `reg` coincide con `0xFFC00000` (Nil) o `0xFFC00001` (False). Si coincide con alguno, la ejecución salta a la etiqueta de destino.
* **`emit_truthy_jump(reg, label)`**: Comprueba frente a Nil y False; si no coincide con ninguno, la ejecución realiza un cortocircuito hacia la etiqueta de destino.

Cuando se evalúan operadores lógicos (`and`, `or`), el resultado evaluado se deja intacto en el registro de destino, preservando el modismo de Lua de devolver el valor real del operando en lugar de un booleano estricto.

## Características compatibles del lenguaje Lua

`v32lua` implementa un subconjunto de Lua, adaptado específicamente para el desarrollo de videojuegos en hardware embebido.

### Variables y alcances

* **Variables globales:** Registradas automáticamente en la RAM (a partir de la dirección `1`, ya que la dirección `0` está reservada para el puntero del montículo) y accesibles mediante símbolos (`[var_name]`, `[func_name]`).
* **Variables locales:** Declaradas con la palabra clave `local`. Tienen un alcance léxico limitado al bloque que las engloba (`do ... end`, cuerpos de funciones, bucles o condicionales) y se asignan a desplazamientos en la pila (`[BP - offset]`).

En el argot de Lua, las funciones son "ciudadanos de primera clase" y actúan efectivamente como variables. Esto se refleja en `v32lua`, ya que ambas se procesan dentro del esquema de *NaN-boxing*.

### Asignación múltiple

El compilador admite de forma nativa la asignación múltiple y el intercambio de variables sin requerir variables temporales explícitas por parte del usuario:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Sintetiza cadenas de registros temporales para intercambiar valores de forma segura

```

### Programación orientada a objetos y tablas

`v32lua` proporciona una sintaxis simplificada (*syntactic sugar*) y fluida para modelos de POO basados en tablas:

* **Desazucarado (*Desugaring*) de la definición de métodos:** Definir una función en una tabla genera automáticamente una etiqueta modificada (*mangled*) y enlaza la propiedad del puntero de la función:

```lua
function Player.move(dx, dy) ... end
-- Se desazucara a: Player["move"] = __function_Player_move

```

* **Desazucarado de la llamada a métodos (operador `:`):** El uso del operador de dos puntos evalúa automáticamente la expresión de la tabla y la inyecta como un parámetro implícito `self`:

```lua
Player:move(5, -2)
-- Se desazucara a: Player.move(Player, 5, -2)

```

### Flujo de control

* **Bucles:** Se admiten sentencias `while <cond> do ... end` con alcance de bloque completo.
* **Control de bucles:** Las sentencias `break` saltan inmediatamente a la etiqueta final del bucle más interno actual (rastreado mediante una pila de bucles de compilación interna).
* **Condicionales:** Estructuras `if <cond> then ... elseif <cond> then ... else ... end` con ramificación de cortocircuito.

### Operadores y expresiones

* **Aritméticos:** `+`, `-`, `*`, `/` (asignados a las instrucciones de hardware de coma flotante de Vircon32 `FADD`, `FSUB`, `FMUL`, `FDIV`) y menos unario (`-` mediante `__builtin_unm`).
* **Relacionales:** `==`, `~=` (mediante `__builtin_eq` con desempaquetado NaN), `<`, `>`, `<=`, `>=` (mediante el hardware `FLT`, `FLE`, `FGT`, `FGE`).
* **Lógicos:** `and`, `or`, `not` (con evaluación de cortocircuito).
* **Concatenación de cadenas:** El operador `..` empuja automáticamente los operandos e invoca la subrutina en tiempo de ejecución `__builtin_strcat`.
* **Operador de longitud:** El operador `#` invoca `__builtin_len` para resolver la longitud de cadenas o tablas.

### Funciones y retornos de valores múltiples

Las funciones pueden devolver múltiples valores simultáneamente. La convención de llamada optimiza las primeras tres expresiones devueltas colocándolas directamente en los registros `R0`, `R2` y `R3`. Cualquier valor de retorno adicional (del cuarto en adelante) se vierte directamente en el marco de pila del llamador en `[BP + 2 + arg_count + offset]`.

### Agrupación de literales de cadena (*String Literal Pooling*)

Todos los literales de cadena declarados en el código fuente (por ejemplo, `"GAME OVER"`) se recopilan durante la compilación, se eliminan los duplicados y se emiten en una sección de datos dedicada al final de la ROM (`__string_0: string "GAME OVER"`), evitando así un consumo redundante de memoria ROM.

---

## E/S de hardware y funciones intrínsecas del compilador

Una de las características más potentes de `v32lua` es su **motor estático de intercepción de funciones intrínsecas**. Cuando el compilador encuentra accesos a tablas o llamadas a funciones que coinciden con rutas específicas del sistema (por ejemplo, `ioports.gpu.clear()`), **omite por completo las búsquedas dinámicas en tablas** y emite instrucciones directas de E/S de hardware de Vircon32 (`IN`, `OUT`).

### Conversión de tipos automática a través de los límites de E/S

Dado que las variables de Lua se almacenan como flotantes IEEE 754 con *NaN-boxing* mientras que los puertos de hardware de Vircon32 esperan enteros de 32 bits o booleanos, `v32lua` inyecta automáticamente instrucciones de conversión de hardware durante las lecturas y escrituras en los puertos:

* **`CFI` (*Cast Float to Integer* / Flotante a Entero):** Se emite automáticamente al escribir valores numéricos en los puertos de enteros de la GPU o de entrada.
* **`CFB` (*Cast Float to Boolean* / Flotante a Booleano):** Se emite al escribir banderas booleanas en los registros de hardware.
* **`CIF` (*Cast Integer to Float* / Entero a Flotante):** Se emite inmediatamente después de ejecutar una instrucción `IN` desde puertos de hardware de enteros, asegurando que el valor se pueda usar de inmediato como un número de Lua.

---

### Tabla de referencia completa de funciones intrínsecas

#### Control y dibujo de GPU (`ioports.gpu.*`)

| Ruta Lua / Intrínseca | Puerto Vircon32 / Comando | Acceso | Descripción y comportamiento |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lectura / Escritura | Establece o lee el ID de textura activo utilizado para las operaciones de dibujo. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lectura / Escritura | Selecciona la subregión de textura (fotograma del *sprite*) a renderizar. |
| **`ioports.gpu.x`** | `GPU_DrawingPointX` | Lectura / Escritura | Coordenada X de la pantalla para ubicar el dibujo. |
| **`ioports.gpu.y`** | `GPU_DrawingPointY` | Lectura / Escritura | Coordenada Y de la pantalla para ubicar el dibujo. |
| **`ioports.gpu.minX`** | `GPU_RegionMinX` | Lectura / Escritura | Define el límite de píxeles izquierdo de la región de textura activa. |
| **`ioports.gpu.minY`** | `GPU_RegionMinY` | Lectura / Escritura | Define el límite de píxeles superior de la región de textura activa. |
| **`ioports.gpu.maxX`** | `GPU_RegionMaxX` | Lectura / Escritura | Define el límite de píxeles derecho de la región de textura activa. |
| **`ioports.gpu.maxY`** | `GPU_RegionMaxY` | Lectura / Escritura | Define el límite de píxeles inferior de la región de textura activa. |
| **`ioports.gpu.hotX`** | `GPU_RegionHotSpotX` | Lectura / Escritura | Establece el origen X de dibujo (*hotspot*) relativo a la región del *sprite*. |
| **`ioports.gpu.hotY`** | `GPU_RegionHotSpotY` | Lectura / Escritura | Establece el origen Y de dibujo (*hotspot*) relativo a la región del *sprite*. |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Llamada a función | Ejecuta un comando de dibujo por hardware. Acepta un modo opcional en cadena: `"zoom"` (`GPUCommand_DrawRegionZoomed`), `"rotate"` (`GPUCommand_DrawRegionRotated`), `"rotozoom"` (`GPUCommand_DrawRegionRotozoomed`) o por defecto (`GPUCommand_DrawRegion`). |
| **`ioports.gpu.clear([color])`** | `GPU_ClearColor` + `GPU_Command` | Llamada a función | Establece el color de limpieza y borra la pantalla (`GPUCommand_ClearScreen`). Admite cadenas de colores predeterminados: `"black"` (`0x000000FF`), `"white"` (`0xFFFFFFFF`), `"blue"` (`0x0000FFFF`), `"red"` (`0xFF0000FF`), `"green"` (`0x00FF00FF`) o valores numéricos en formato hex. |

#### Mando y entrada (`ioports.inp.*`)

| Ruta Lua / Intrínseca | Puerto Vircon32 / Comando | Acceso | Descripción y comportamiento |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lectura / Escritura | Selecciona el índice del mando activo (`0` a `3`) para el sondeo de entrada. |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Solo lectura | Devuelve `1` si el mando seleccionado está conectado, `0` en caso contrario. |
| **`ioports.inp.left`** | `INP_GamepadLeft` | Solo lectura | Estado direccional izquierdo del D-Pad (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.right`** | `INP_GamepadRight` | Solo lectura | Estado direccional derecho del D-Pad (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.up`** | `INP_GamepadUp` | Solo lectura | Estado direccional superior del D-Pad (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.down`** | `INP_GamepadDown` | Solo lectura | Estado direccional inferior del D-Pad (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.start`** | `INP_GamepadButtonStart` | Solo lectura | Estado del botón Start (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.A`** | `INP_GamepadButtonA` | Solo lectura | Estado del botón de acción A (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.B`** | `INP_GamepadButtonB` | Solo lectura | Estado del botón de acción B (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.X`** | `INP_GamepadButtonX` | Solo lectura | Estado del botón de acción X (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.Y`** | `INP_GamepadButtonY` | Solo lectura | Estado del botón de acción Y (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.L`** | `INP_GamepadButtonL` | Solo lectura | Estado del gatillo superior izquierdo L (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.R`** | `INP_GamepadButtonR` | Solo lectura | Estado del gatillo superior derecho R (`> 0` presionado, `< 0` liberado). |
| **`ioports.inp.inputs`** | *Subrutina de acción personalizada* | Solo lectura | **Intrínseca de recopilación:** Ejecuta una secuencia rápida de sondeo multipuerto en los 11 botones y ejes del mando, desplazando y combinando sus estados booleanos en una única máscara de bits de entero de 32 bits antes de convertirla a flotante (`CIF`). ¡Altamente eficiente para capturar instantáneas del estado de los botones! |

#### Utilidades del sistema y tiempo de ejecución

| Ruta Lua / Intrínseca | Instrucción Vircon32 | Acceso | Descripción y comportamiento |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Llamada a función | Emite la instrucción de hardware `HLT`, terminando inmediatamente la ejecución de la CPU o congelando el fotograma hasta la siguiente interrupción/ciclo de fotograma. |
| **`system.wait()`** | `WAIT` | Llamada a función | Emite la instrucción de hardware `WAIT`, pausando la ejecución hasta la siguiente interrupción/ciclo de fotograma. |
| **`print(x, y, ...)`** | `__builtin_tostring` + `__builtin_print` | Llamada a función | Convierte los argumentos a una representación en cadena mediante subrutinas de conversión en tiempo de ejecución y los muestra en el terminal de depuración de la consola. Los dos primeros parámetros representan la posición X e Y en la pantalla, en píxeles. |

---

## Ensamblador en línea (`__asm__` y `__rawasm__`)

Para bucles internos críticos para el rendimiento o para manipulación avanzada del hardware de Vircon32, `v32lua` permite la inyección directa de código ensamblador en línea.

### Ensamblador en línea estándar (`__asm__`)

La directiva `__asm__` permite incrustar cadenas en bruto de código ensamblador de Vircon32 directamente dentro de funciones de Lua. Crucialmente, admite **interpolación de variables**, lo que permite una integración perfecta entre los símbolos del alcance de Lua y los registros del ensamblador:

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )

```

* **Cómo funciona:** Cualquier identificador envuelto en llaves (por ejemplo, `{speed}`) es resuelto dinámicamente por `emit_interpolated_asm` en tiempo de compilación. Si `speed` es una variable local en el desplazamiento de pila 1, `{speed}` se reemplaza automáticamente con `[BP - 1]`. Si es una global, se resuelve como `[var_speed]`.
* Cada línea de ensamblador interpolado pasa por el motor de formateo del compilador, asegurando una sangría coherente y una alineación de comentarios adecuada en el archivo `.asm` de salida.
* Este código ensamblador en línea estándar aplica algunas protecciones y barandillas de seguridad leves, como una copia de seguridad de cualquier registro utilizado existente, junto con la pila. Aunque no evita problemas, puede ayudar a mitigar algunos causados por accidente. Cabe destacar que cualquier cambio en los registros realizado aquí se perderá fuera de la "burbuja" de código en línea.

### Ensamblador puro (`__rawasm__`)

La directiva `__rawasm__` genera la cadena literal directamente en el flujo de código ensamblador sin aplicar ninguna medida de seguridad. Esto puede ser bastante peligroso y solo debería ser utilizado por los usuarios de código ensamblador más experimentados y con mayores conocimientos.

---

## 🧠 Referencia del mapa de memoria

| Rango de direcciones RAM | Designación | Uso |
| --- | --- | --- |
| `0` | `heap_pointer` | Almacena la dirección de inicio dinámica para las asignaciones de tablas en tiempo de ejecución. |
| `1` a `N` | RAM Global | Espacios asignados secuencialmente para variables globales de Lua e ID de recursos. |
| `N + 1`+ | Montículo dinámico (*Heap*) | Memoria en tiempo de ejecución gestionada por `__builtin_table_new` y los asignadores de cadenas. |
| Cima de la pila (`SP`) | Pila de llamadas | Registros de activación de funciones, variables locales y estados de registros guardados. |

---

## Peculiaridades y suposiciones del compilador

Aunque `v32lua` intenta ser un compilador funcional de Lua, de ninguna manera es una implementación del lenguaje completamente ajustada a las especificaciones. Para empezar, no hay una máquina virtual de bytecode ni un intérprete.

Además, existen algunas desviaciones explícitas respecto a una implementación estándar del lenguaje para adaptarse mejor al entorno independiente (*freestanding*) de Vircon32:

* `print()` requiere, como sus dos primeros parámetros, la posición `x` e `y` en la pantalla.
* Las sentencias `return` independientes no funcionan (generarán un error de sintaxis). Debes proporcionarles un valor (`nil`, `0`, etc.) para que se procesen correctamente.
* La ejecución del programa DEBE residir dentro de una función. Aunque puedes declarar funciones, debes utilizar uno de los puntos de inicio designados para comenzar la cadena de ejecución (en forma de `init()`, `game_loop()` o `main()`). No tener una función `main()` o `game_loop()` provocará un error. Además, `game_loop()` emitirá automáticamente una instrucción `WAIT` antes de volver a llamarse a sí misma, convirtiéndola en el lugar natural para tu bucle de juego. Esto está pensado para ser similar a otras consolas de fantasía (como la función `TIC()` en TIC-80, que se requiere de manera similar).

Claramente, este proyecto se centra en crear una herramienta para el desarrollo en Vircon32, y no en ser una implementación de Lua plenamente compatible. Se harán esfuerzos para acercarse lo máximo posible y factible, sin sacrificar un rendimiento significativo ni apartarse de ser la herramienta para la que ha sido concebida.
