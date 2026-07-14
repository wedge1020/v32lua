# v32lua: Compilador de Lua para Vircon32

[English version / Versión en inglés](README.md)

**Arquitectura Objetivo:** Consola de Fantasía Vircon32 (32 bits)

**Lenguaje de Implementación:** C (Flex/Bison + Emisor Semántico Personalizado)

---

## 1. Descripción General y Arquitectura

`v32lua` es un compilador optimizador escrito en C que traduce código fuente de Lua de tipado dinámico directamente a lenguaje ensamblador estático de Vircon32 (`.asm`) y genera automáticamente la configuración XML del cartucho (`.xml`) para el emulador y el hardware de Vircon32.

A diferencia de las implementaciones tradicionales de Lua que dependen de la interpretación de bytecode y de una pesada máquina virtual en tiempo de ejecución, `v32lua` es un **verdadero compilador anticipado (AOT, Ahead-Of-Time)**. Emite instrucciones nativas y eficientes de Vircon32, aprovechando un sistema de tipos personalizado basado en **NaN-boxing**, optimización automática de marcos de pila (stack-frame) y **funciones intrínsecas del compilador** sin sobrecarga, las cuales mapean los accesos a tablas de Lua directamente a los registros de E/S mapeados en memoria de Vircon32.


```

+------------------+     +-----------------------+     +------------------+
| Fuente (.lua)    | --> | Analizador Léxico/Sin | --> | Construcción AST |
+------------------+     | (Flex / Bison)        |     +------------------+
+-----------------------+              |
v
+------------------+     +-----------------------+     +------------------+
| Config. Cartucho | <-- | Emisor de Ensamblador | <-- | Emisor Semántico |
| (.xml y .vbin)   |     | de Vircon32 (.asm)    |     | y Opt. Peephole  |
+------------------+     +-----------------------+     +------------------+

```

---

## 2. Flujo de Trabajo del Compilador y Uso de la CLI

### Interfaz de Línea de Comandos

El compilador se invoca desde la línea de comandos y admite varias opciones para diagnóstico y flujos de trabajo de compilación:

```bash
v32lua [opciones] <archivo_entrada.lua>

```

| Opción | Descripción |
| --- | --- |
| `-o <archivo>` | Especifica el nombre del archivo de ensamblador de salida (por defecto es `<entrada>.asm`). |
| `-v`, `--verbose` | Activa el registro detallado (verbose) de compilación a lo largo de las distintas etapas y generación de recursos. |
| `-g` | Activa el modo de seguimiento de depuración, generando archivos internos de mapeo de líneas de código fuente a ensamblador. |
| `--version` | Muestra la versión del compilador e información del autor. |
| `--help`, `-h` | Muestra las instrucciones de uso de la línea de comandos. |

### Etapas de Compilación

Cuando `-v` está activado, `v32lua` informa sobre su progreso a través de cinco etapas principales del flujo:

1. **Etapa 1: Analizador Léxico (Lexer)** — Convierte en tokens el código fuente de Lua, eliminando los comentarios estándar y procesando secuencias de escape de cadenas (`\n`, `\t`, `\r`, `\\`, `\"`).
2. **Etapa 2: Preprocesador** — Evalúa las directivas de cartucho (`--#...`) y las sintaxis de comentarios personalizados.
3. **Etapa 3: Analizador Sintáctico (Parser)** — Construye un Árbol de Sintaxis Abstracta (AST) completo mediante una gramática Bison LALR(1) con precedencia estricta de operadores (PEMDAS + núcleo lógico).
4. **Etapa 4: Analizador Semántico** — Realiza una pre-pasada de funciones para registrar símbolos de funciones globales, inicializar el ámbito global y resolver anotaciones de tipo.
5. **Etapa 5: Emisor** — Recorre el AST para generar ensamblador de Vircon32, aplicando asignación de registros, desplazamientos de ámbito (scope offsets) y optimizaciones de mirilla (peephole). Finalmente, exporta el archivo de configuración XML del cartucho.

---

## 3. Instrucciones de Construcción y Objetivos de Makefile

El repositorio incluye un archivo Makefile en la raíz para gestionar la compilación del binario del compilador, pruebas automatizadas, despliegue y mantenimiento del código.

### Instrucciones de Compilación

Para construir el binario principal del compilador a partir del código fuente, ejecute el objetivo por defecto desde el directorio raíz:

```bash
make

```

### Tabla de Referencia de Objetivos de Makefile

| Objetivo (Target) | Descripción | Acciones Principales y Dependencias |
| --- | --- | --- |
| **`all`** | **Objetivo por defecto.** Construye el ejecutable principal del compilador. | Invoca el proceso de compilación de forma nativa dentro del subdirectorio `src/`. |
| **`clean`** | Utilidad estándar de limpieza del espacio de trabajo. | Elimina recursivamente los artefactos de construcción intermedios de `src/` y borra los archivos generados en `testing/` y `demos/`. |
| **`install`** | Instala el binario del compilador en el sistema anfitrión. | Delega el objetivo a los scripts de instalación localizados en el directorio `src/`. |
| **`tests`** | Ejecuta la suite de pruebas de compilación automatizadas. | Depende explícitamente de que el binario del compilador (`bin/v32lua`) se haya construido primero, luego activa las rutinas de prueba dentro de `testing/`. |
| **`demos`** | Construye la colección de demos disponibles. | Depende explícitamente de que el binario del compilador (`bin/v32lua`) se haya construido primero, luego compila cada demo en `demos/`. |
| **`asmcheck`** | Valida la corrección del ensamblador. | Requiere que `bin/v32lua` esté presente, luego procesa las validaciones de ensamblador a través de la suite en `testing/`. |
| **`monofiles`** | Construye variantes de archivos monolíticos optimizados. | Ejecuta secuencialmente el flujo de trabajo de creación de `monofile` dentro de `src/` y `testing/`. |

---

## 4. Directivas de Construcción de Cartuchos (`--#`)

`v32lua` introduce una sintaxis especial de comentarios (`--#`) que actúa como un script de construcción integrado para el generador de ROMs de Vircon32. Durante el análisis léxico, estas directivas se interceptan y compilan en un archivo XML de definición de ROM (`.xml`) junto con el ensamblador de salida.

### Directivas de Cartucho Admitidas

```lua
--#title "Super Space Shooter 32"
--#version 1.2
--#texture background "assets/bg_stars.png"
--#texture player_sprite "assets/ship.png"

```

* **`--#title <"cadena">`**: Establece los metadatos del título del cartucho en el XML generado.
* **`--#version <cadena>`**: Establece el atributo de versión para la definición de la ROM.
* **`--#texture <nombre_var> <"ruta">`**: Registra un recurso de textura, le asigna un ID entero incremental (comenzando en `0`) y asocia dicho ID a una variable global de Lua (`background`, `player_sprite`, etc.) para que se pueda pasar directamente a las funciones intrínsecas de la GPU sin necesidad de llevar un registro manual de los IDs.

---

## 5. Arquitectura Objetivo: Vircon32 y Diseño de Ensamblador

Para los desarrolladores familiarizados con C y la arquitectura de computadores, `v32lua` tiende un puente entre el scripting de alto nivel y el control de hardware directo al respetar las restricciones particulares de la CPU de Vircon32.

### Esquema de Asignación de Registros

La CPU de Vircon32 proporciona 16 registros de propósito general de 32 bits (`R0` a `R15`). `v32lua` los divide en roles funcionales estrictos:

| Registro(s) | Rol y Reglas de Asignación |
| --- | --- |
| **`R0` – `R5**` | **Uso temporal general y evaluación de expresiones:** Asignados dinámicamente durante el recorrido del AST para operaciones aritméticas, lógicas y valores de retorno de funciones (`R0`, `R2`, `R3`). |
| **`R6`** | **Temporal de condición / Guarda no destructiva:** Reservado específicamente para proteger contra las instrucciones de comparación destructiva de Vircon32 durante las evaluaciones lógicas y de ramificación. |
| **`R7` – `R10**` | **Propósito general:** Disponibles para evaluación extendida de expresiones y árboles de expresiones complejas. |
| **`R11` – `R13**` | **Auxiliares de memoria y cadenas:** Utilizados por el hardware y subrutinas en tiempo de ejecución para operaciones de memoria en bloque (`MOVS`, `SETS`, `CMPS`). |
| **`R14` (`BP`)** | **Puntero base (Base Pointer):** Apunta a la base del marco de pila local de la función actual. |
| **`R15` (`SP`)** | **Puntero de pila (Stack Pointer):** Apunta al tope de la pila de ejecución. |

### Manejo de Comparaciones Destructivas

Una peculiaridad arquitectónica crítica de Vircon32 es que **las instrucciones de comparación son destructivas para el registro de destino**. Por ejemplo, al ejecutar una verificación de igualdad de enteros:

```assembly
IEQ R0, R1   ; ¡Evalúa (R0 == R1), almacena el resultado booleano (0 o 1) directamente en R0!

```

Si `R0` contenía una variable que debía reutilizarse más tarde, la comparación la destruiría. Para resolver esto sin duplicar variables manualmente en Lua, `v32lua` utiliza el registro **`R6` como un registro temporal dedicado a condiciones** durante las bifurcaciones condicionales (`if`, `while`, cortocircuito lógico):

```assembly
MOV R6, R0          ; Copia el operando al registro temporal R6
IEQ R6, 0xFFC00000  ; Realiza la prueba destructiva contra el valor Nil canónico
JT  R6, __target    ; Salta si es verdadero (sin alterar R0)

```

### Marcos de Pila (Stack Frames) y Optimización de Funciones Hoja (Leaf Functions)

Las funciones que declaran variables locales o realizan llamadas complejas anidadas generan un marco de pila estándar al estilo de C:

```assembly
__function_my_func:
    PUSH BP
    MOV  BP, SP
    ; ... cuerpo ...
    MOV  SP, BP
    POP  BP
    RET

```

* **Variables locales:** Se direccionan mediante desplazamientos negativos con respecto al puntero base: `[BP - 1]`, `[BP - 2]`, etc.
* **Parámetros de función:** El emisor de la llamada los coloca en la pila antes de la invocación y se direccionan con desplazamientos positivos: `[BP + 2]`, `[BP + 3]`, etc.

**Optimización:** Antes de emitir las instrucciones del prólogo, `v32lua` realiza un pase de análisis del AST (`check_needs_stack`). Si una función es una **Función Hoja** (no llama a otras funciones, no declara variables locales que requieran almacenamiento en la pila, ni realiza asignaciones complejas de tablas), se omite por completo la configuración del puntero de marco (`PUSH BP; MOV BP, SP`), ahorrando 4 ciclos de reloj y 2 ranuras de pila por llamada.

---

## 6. El Sistema de Tipos NaN-Boxing

Para dar soporte al tipado dinámico de Lua en una arquitectura de hardware de 32 bits sin la sobrecarga de envoltorios de tipo asignados en memoria dinámica (heap) o uniones etiquetadas de varias palabras, `v32lua` implementa una representación de tipos mediante **NaN-Boxing** bajo el estándar IEEE 754.

En la precisión simple de punto flotante de IEEE 754, cualquier palabra de 32 bits con los 8 bits del exponente establecidos en 1 (`0xFF`) y una mantisa distinta de cero representa un valor No es un Número (NaN). Esto deja 23 bits de espacio de carga útil (payload) dentro del espacio NaN para codificar etiquetas de tipo, punteros y constantes especiales.

### Mapa de Representación a Nivel de Bits

```
  31                                  0
  [s | e e e e e e e e | m m m m m ... ]

```

| Tipo / Valor | Máscara Hexadecimal | Detalles de Codificación |
| --- | --- | --- |
| **Punto flotante (Número)** | de `0x00000000` a `0xFF7FFFFF` | Números de punto flotante de precisión simple estándar IEEE 754. |
| **Nil** | `0xFFC00000` | Valor Quiet NaN canónico con carga útil cero. |
| **Booleano Falso (False)** | `0xFFC00001` | Quiet NaN + Bit 0 de la carga útil activo. |
| **Booleano Verdadero (True)** | `0xFFC00002` | Quiet NaN + Bit 1 de la carga útil activo. |
| **Puntero de Cadena (String)** | `0x7FC00000` | `dirección` |
| **Puntero de Función** | `0xFF800000` | `dirección` |

### Evaluación de Cortocircuito Verdadero/Falso (Truthy/Falsy)

En Lua, solo `nil` y `false` se evalúan como falsos en expresiones condicionales; cualquier otro valor (incluyendo el `0` y las cadenas vacías) es considerado **verdadero (truthy)**. `v32lua` implementa esto mediante dos primitivas de emisión de ensamblador de alta velocidad:

* **`emit_falsy_jump(reg, label)`**: Comprueba si `reg` coincide con `0xFFC00000` (Nil) o `0xFFC00001` (Falso). Si coincide alguno de los dos, la ejecución salta a la etiqueta de destino.
* **`emit_truthy_jump(reg, label)`**: Comprueba si no coincide con Nil ni Falso; si no coincide con ninguno, la ejecución realiza un cortocircuito hacia la etiqueta de destino.

Cuando se evalúan los operadores lógicos (`and`, `or`), el resultado evaluado se deja intacto en el registro de destino, preservando el modismo de Lua de devolver el valor real del operando en lugar de un booleano estricto.

---

## 7. Características Soportadas del Lenguaje Lua

`v32lua` implementa un subconjunto robusto de Lua 5.1+, diseñado específicamente para el desarrollo de videojuegos en hardware embebido.

### Variables y Ámbito (Scope)

* **Variables globales:** Se registran automáticamente en RAM (comenzando en la dirección `1`, ya que la dirección `0` está reservada para el puntero del montón/heap) y se accede a ellas mediante símbolos (`[nombre_var]`, `[nombre_func]`).
* **Variables locales:** Se declaran con la palabra clave `local`. Tienen un ámbito léxico delimitado por el bloque que las contiene (`do ... end`, cuerpos de funciones, bucles o condicionales) y se mapean a desplazamientos de la pila (`[BP - desplazamiento]`). El enmascaramiento (shadowing) de variables externas está completamente soportado.

### Asignación Múltiple

El compilador admite de forma nativa la asignación múltiple y el intercambio de variables sin requerir variables temporales explícitas por parte del usuario:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Sintetiza cadenas de registros temporales para intercambiar valores de forma segura

```

### Programación Orientada a Objetos y Tablas

`v32lua` ofrece azúcar sintáctico fluido para modelos de POO basados en tablas:

* **Simplificación de la definición de métodos (Desugaring):** Definir una función en una tabla genera automáticamente una etiqueta decorada (mangled) y vincula la propiedad del puntero de función:

```lua
function Player.move(dx, dy) ... end
-- Se traduce como: Player["move"] = __function_Player_move

```

* **Simplificación de la llamada a métodos (operador `:`):** El uso del operador de dos puntos evalúa automáticamente la expresión de la tabla y la inyecta como un parámetro implícito `self`:

```lua
Player:move(5, -2)
-- Se traduce como: Player.move(Player, 5, -2)

```

### Flujo de Control

* **Bucles:** Estructuras `while <cond> do ... end` soportadas con ámbito de bloque completo.
* **Control de bucles:** Las sentencias `break` saltan inmediatamente a la etiqueta final del bucle interno actual (gestionado mediante una pila interna de bucles durante la compilación).
* **Condicionales:** Estructuras `if <cond> then ... elseif <cond> then ... else ... end` con ramificación por cortocircuito.

### Operadores y Expresiones

* **Aritmética:** `+`, `-`, `*`, `/` (mapeados a instrucciones de hardware de punto flotante de Vircon32: `FADD`, `FSUB`, `FMUL`, `FDIV`) y el menos unario (`-` mediante `__builtin_unm`).
* **Relacionales:** `==`, `~=` (mediante `__builtin_eq` con desempaquetado de NaN), `<`, `>`, `<=`, `>=` (mediante hardware `FLT`, `FLE`, `FGT`, `FGE`).
* **Lógicos:** `and`, `or`, `not` (con evaluación de cortocircuito).
* **Concatenación de cadenas:** El operador `..` coloca automáticamente los operandos en la pila e invoca la subrutina de ejecución `__builtin_strcat`.
* **Operador de longitud:** El operador `#` invoca `__builtin_len` para resolver la longitud de cadenas o tablas.

### Funciones y Retornos de Valores Múltiples

Las funciones pueden retornar múltiples valores simultáneamente. La convención de llamada optimiza las tres primeras expresiones devueltas colocándolas directamente en los registros `R0`, `R2` y `R3`. Cualquier valor de retorno adicional (el cuarto en adelante) se coloca directamente en el marco de pila del invocador en `[BP + 2 + num_argumentos + desplazamiento]`.

### Agrupación de Cadenas Literales (String Literal Pooling)

Todas las cadenas literales declaradas en el código fuente (por ejemplo, `"GAME OVER"`) se recopilan durante la compilación, se deduplican y se emiten en una sección de datos dedicada al final de la ROM (`__string_0: string "GAME OVER"`), evitando así el consumo redundante de memoria ROM.

---

## 8. E/S de Hardware y Funciones Intrínsecas del Compilador

Una de las características más potentes de `v32lua` es su **motor de intercepción estática de intrínsecas**. Cuando el compilador encuentra accesos a tablas o llamadas a funciones que coinciden con rutas específicas del sistema (por ejemplo, `ioports.gpu.clear()`), **omite por completo las búsquedas dinámicas en tablas** y emite instrucciones de E/S de hardware directas de Vircon32 (`IN`, `OUT`).

### Conversión Automática de Tipos en Límites de E/S

Dado que las variables de Lua se almacenan como floats IEEE 754 mediante NaN-boxing, mientras que los puertos de hardware de Vircon32 esperan enteros de 32 bits o booleanos, `v32lua` inyecta automáticamente instrucciones de conversión de hardware durante las lecturas y escrituras en puertos:

* **`CFI` (Cast Float to Integer):** Se emite automáticamente al escribir valores numéricos en puertos enteros de GPU/Entrada.
* **`CFB` (Cast Float to Boolean):** Se emite al escribir indicadores booleanos en registros de hardware.
* **`CIF` (Cast Integer to Float):** Se emite inmediatamente después de ejecutar una instrucción `IN` desde puertos de hardware de tipo entero, garantizando que el valor sea utilizable de inmediato como un número de Lua.

---

### Tabla de Referencia Completa de Intrínsecas

#### 1. Control y Dibujo de GPU (`ioports.gpu.*`)

| Ruta en Lua / Intrínseca | Puerto / Comando de Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lectura / Escritura | Establece o lee el ID de textura activa utilizado para las operaciones de dibujo. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lectura / Escritura | Selecciona la subregión de textura (cuadro de sprite) a renderizar. |
| **`ioports.gpu.x`** | `GPU_DrawingPointX` | Lectura / Escritura | Coordenada X de la pantalla para la colocación del dibujo. |
| **`ioports.gpu.y`** | `GPU_DrawingPointY` | Lectura / Escritura | Coordenada Y de la pantalla para la colocación del dibujo. |
| **`ioports.gpu.minX`** | `GPU_RegionMinX` | Lectura / Escritura | Define el límite izquierdo de píxeles de la región de textura activa. |
| **`ioports.gpu.minY`** | `GPU_RegionMinY` | Lectura / Escritura | Define el límite superior de píxeles de la región de textura activa. |
| **`ioports.gpu.maxX`** | `GPU_RegionMaxX` | Lectura / Escritura | Define el límite derecho de píxeles de la región de textura activa. |
| **`ioports.gpu.maxY`** | `GPU_RegionMaxY` | Lectura / Escritura | Define el límite inferior de píxeles de la región de textura activa. |
| **`ioports.gpu.hotX`** | `GPU_RegionHotSpotX` | Lectura / Escritura | Establece el origen de dibujo X (punto caliente / hotspot) relativo a la región del sprite. |
| **`ioports.gpu.hotY`** | `GPU_RegionHotSpotY` | Lectura / Escritura | Establece el origen de dibujo Y (punto caliente / hotspot) relativo a la región del sprite. |
| **`ioports.gpu.draw([modo])`** | `GPU_Command` | Llamada a Función | Ejecuta un comando de dibujo por hardware. Acepta un modo opcional como cadena: `"zoom"` (`GPUCommand_DrawRegionZoomed`), `"rotate"` (`GPUCommand_DrawRegionRotated`), `"rotozoom"` (`GPUCommand_DrawRegionRotozoomed`) o por defecto (`GPUCommand_DrawRegion`). |
| **`ioports.gpu.clear([color])`** | `GPU_ClearColor` + `GPU_Command` | Llamada a Función | Establece el color de limpieza y borra la pantalla (`GPUCommand_ClearScreen`). Admite cadenas de colores predefinidas: `"black"` (`0x000000FF`), `"white"` (`0xFFFFFFFF`), `"blue"` (`0x0000FFFF`), `"red"` (`0xFF0000FF`), `"green"` (`0x00FF00FF`) o valores numéricos hexadecimales. |

#### 2. Mando y Entrada (`ioports.inp.*`)

| Ruta en Lua / Intrínseca | Puerto / Comando de Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lectura / Escritura | Selecciona el índice del mando activo (de `0` a `3`) para el sondeo de entradas. |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Solo Lectura | Devuelve `1` si el mando seleccionado está conectado, y `0` en caso contrario. |
| **`ioports.inp.left`** | `INP_GamepadLeft` | Solo Lectura | Estado direccional izquierdo de la cruceta (D-Pad) (`1` presionado, `0` liberado). |
| **`ioports.inp.right`** | `INP_GamepadRight` | Solo Lectura | Estado direccional derecho de la cruceta (D-Pad) (`1` presionado, `0` liberado). |
| **`ioports.inp.up`** | `INP_GamepadUp` | Solo Lectura | Estado direccional arriba de la cruceta (D-Pad) (`1` presionado, `0` liberado). |
| **`ioports.inp.down`** | `INP_GamepadDown` | Solo Lectura | Estado direccional abajo de la cruceta (D-Pad) (`1` presionado, `0` liberado). |
| **`ioports.inp.start`** | `INP_GamepadButtonStart` | Solo Lectura | Estado del botón Start (`1` presionado, `0` liberado). |
| **`ioports.inp.A`** | `INP_GamepadButtonA` | Solo Lectura | Estado del botón de acción A (`1` presionado, `0` liberado). |
| **`ioports.inp.B`** | `INP_GamepadButtonB` | Solo Lectura | Estado del botón de acción B (`1` presionado, `0` liberado). |
| **`ioports.inp.X`** | `INP_GamepadButtonX` | Solo Lectura | Estado del botón de acción X (`1` presionado, `0` liberado). |
| **`ioports.inp.Y`** | `INP_GamepadButtonY` | Solo Lectura | Estado del botón de acción Y (`1` presionado, `0` liberado). |
| **`ioports.inp.L`** | `INP_GamepadButtonL` | Solo Lectura | Estado del botón lateral (Shoulder) izquierdo L (`1` presionado, `0` liberado). |
| **`ioports.inp.R`** | `INP_GamepadButtonR` | Solo Lectura | Estado del botón lateral (Shoulder) derecho R (`1` presionado, `0` liberado). |
| **`ioports.inp.inputs`** | *Subrutina de acción personalizada* | Solo Lectura | **Intrínseca de recopilación:** Ejecuta una secuencia rápida de sondeo multipuerto a través de los 11 botones/ejes del mando, desplazando y combinando sus estados booleanos en una única máscara de bits entera de 32 bits antes de convertirla a float (`CIF`). ¡Altamente eficiente para capturas instantáneas de estado de botones! |

#### 3. Utilidades del Sistema y del Tiempo de Ejecución

| Ruta en Lua / Intrínseca | Instrucción de Vircon32 | Acceso | Descripción y Comportamiento |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Llamada a Función | Emite la instrucción de hardware `HLT`, terminando inmediatamente la ejecución de la CPU o deteniendo el fotograma hasta el próximo ciclo de interrupción/fotograma. |
| **`print(...)`** | `__builtin_tostring` + `__builtin_print` | Llamada a Función | Convierte los argumentos a su representación de cadena mediante subrutinas de conversión en tiempo de ejecución y los envía a la terminal de depuración de la consola. |

---

## 9. Ensamblador Integrado (`__asm__` y `__rawasm__`)

Para bucles internos críticos en rendimiento o manipulación avanzada del hardware de Vircon32 (como la programación de canales del chip de sonido personalizado o transferencias DMA), `v32lua` proporciona inyección directa de ensamblador integrado.

### Ensamblador Integrado Estándar (`__asm__`)

La directiva `__asm__` permite incrustar cadenas de ensamblador de Vircon32 sin procesar directamente dentro de las funciones de Lua. Crucialmente, soporta **interpolación de variables**, lo que permite un puente fluido entre los símbolos del ámbito de Lua y los registros de ensamblador:

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )

```

* **Cómo funciona:** Cualquier identificador envuelto entre llaves (por ejemplo, `{speed}`) es resuelto dinámicamente por `emit_interpolated_asm` en tiempo de compilación. Si `speed` es una variable local en el desplazamiento de pila 1, `{speed}` se reemplaza automáticamente por `[BP - 1]`. Si es una variable global, se resuelve como `[var_speed]`.
* Cada línea de ensamblador interpolado pasa a través del motor de formateo del compilador, garantizando una sangría y alineación de comentarios consistentes en el archivo `.asm` de salida.

### Ensamblador Puro (`__rawasm__`)

La directiva `__rawasm__` escribe la cadena literal directamente en el flujo de ensamblador sin interpolación de variables ni modificaciones de formato, ideal para definir bloques de datos masivos, etiquetas personalizadas o cargas útiles binarias puras.

---

## 10. Ejemplo de Código: Poniendo Todo Junto

El siguiente ejemplo completo demuestra el uso conjunto de directivas de cartucho, POO con tablas, funciones intrínsecas de dibujo de GPU y ensamblador integrado:

```lua
--#title "Vircon32 Tech Demo"
--#version 1.0
--#texture logo "assets/vircon_logo.png"

-- Definir un objeto Player usando POO basada en Tablas
Player = {}
function Player:init(x, y)
    self.x = x
    self.y = y
    self.speed = 2.5
end

function Player:render()
    -- Seleccionar textura usando el ID autogenerado desde la directiva de cartucho
    ioports.gpu.texture = logo
    ioports.gpu.region = 0
    
    -- Establecer coordenadas de dibujo directamente en los registros de hardware
    ioports.gpu.x = self.x
    ioports.gpu.y = self.y
    
    -- Dibujar usando el comando de hardware rotozoom
    ioports.gpu.draw("rotozoom")
end

-- Bucle Principal del Juego
Player:init(160, 120)

while true do
    -- Limpiar la pantalla con un color azul oscuro
    ioports.gpu.clear("blue")
    
    -- Leer la máscara de bits combinada del mando en una sola operación intrínseca
    local pad = ioports.inp.inputs
    
    -- Comprobar la dirección derecha en la cruceta (D-Pad Right)
    if ioports.inp.right == 1 then
        Player.x = Player.x + Player.speed
    end
    
    Player:render()
    
    -- Detener la ejecución hasta la siguiente interrupción de fotograma
    system.halt()
end

```

---

## 11. Particularidades y Asunciones del Compilador

Aunque `v32lua` intenta ser un compilador de Lua funcional, de ninguna manera es una implementación que cumpla plenamente con las especificaciones del lenguaje. En primer lugar, no dispone de una máquina virtual de bytecode ni de un intérprete.

Además, existen algunas desviaciones explícitas respecto a la implementación estándar del lenguaje para adaptarse mejor al entorno de ejecución directo (freestanding) de Vircon32:

* `print()` requiere, como sus dos primeros parámetros, las posiciones `x` e `y` en la pantalla.
* Las sentencias `return` independientes no funcionan (generarán un error de sintaxis). Se le debe proporcionar algún valor (`nil`, `0`, etc.) para que el compilador lo acepte.
* La ejecución del programa comienza obligatoriamente en una función llamada `main()`. No disponer de una función `main()` provocará un error. Además, `main()` emitirá automáticamente una instrucción `WAIT` antes de llamarse a sí misma de nuevo, convirtiéndola en la ubicación natural de tu bucle de juego. Esto está pensado para ser similar a otras consolas de fantasía (como la función `TIC()` en TIC-80 que se requiere de forma parecida).

Evidentemente, este esfuerzo está enfocado en crear una herramienta de desarrollo para Vircon32, y no en ser una implementación de Lua completamente conforme a los estándares. Se realizarán esfuerzos para accesarse lo máximo posible y viable, sin sacrificar significativamente el rendimiento ni desviarse de su propósito como herramienta.
