# v32lua: Vircon32 Lua Compiler

[English version / Engelse versie](README.md) | [Spanish version / Spaanse versie](README.es.md)

**Doelarchitectuur:** Vircon32 Fantasy Console (32-bits)

**Implementatietaal:** C (Flex/Bison + Aangepaste Semantische Emitter)

---

## 1. Overzicht & Architectuur

`v32lua` is een optimaliserende compiler geschreven in C die dynamisch getypeerde Lua-broncode direct vertaalt naar statische Vircon32-assemblertaal (`.asm`) en automatisch de cartridge-configuratie XML (`.xml`) genereert voor de Vircon32-emulator en -hardware.

In tegenstelling tot traditionele Lua-implementaties die vertrouwen op bytecode-interpretatie en een zware runtime virtual machine, is `v32lua` een **echte ahead-of-time (AOT) compiler**. Het genereert slanke, native Vircon32-instructies door gebruik te maken van een aangepast **NaN-boxing** typesysteem, automatische stackframe-optimalisatie en zero-overhead **compiler-intrinsics** die Lua-tabeltoegang direct koppelen aan de in het geheugen in kaart gebrachte (memory-mapped) I/O-registers van de Vircon32.


```

+------------------+     +-------------------+     +------------------+
| Source (.lua)    | --> | Lexer & Parser    | --> | AST Construction |
+------------------+     | (Flex / Bison)    |     +------------------+
+-------------------+              |
v
+------------------+     +-------------------+     +------------------+
| Cartridge Config | <-- | Vircon32 Assembly | <-- | Semantic Emitter |
| (.xml & .vbin)   |     | Emitter (.asm)    |     | & Peephole Opt   |
+------------------+     +-------------------+     +------------------+

```

---

## 2. Compiler-pijplijn & CLI-gebruik

### Command-Line Interface

De compiler wordt aangeroepen vanaf de opdrachtregel en ondersteunt verschillende diagnostische en build-workflowflags:

```bash
v32lua [opties] <invoerbestand.lua>

```

| Flag | Beschrijving |
| --- | --- |
| `-o <bestand>` | Specificeert de naam van het uitvoerbestand voor de assembler (standaard `<invoer>.asm`). |
| `-v`, `--verbose` | Schakelt gedetailleerde build-logging in voor alle compilatiefasen en het genereren van assets. |
| `-g` | Schakelt debug-trackingmodus in en genereert interne broncode-naar-assembler regelmappingbestanden. |
| `--version` | Toont de versie van de compiler en auteursinformatie. |
| `--help`, `-h` | Toont de gebruiksinstructies voor de opdrachtregel. |

### Compilatiefasen

Wanneer `-v` is ingeschakeld, rapporteert `v32lua` zijn voortgang via vijf kernfasen van de pijplijn:

1. **Fase 1: Lexer** — Analyseert de Lua-broncode in tokens, verwijdert standaardcommentaar en verwerkt ontsnappingsreeksen (escape sequences) in strings (`\n`, `\t`, `\r`, `\\`, `\"`).
2. **Fase 2: Preprocessor** — Evalueert cartridge-aanwijzingen (hints) (`--#...`) en aangepaste commentaarsyntaxis.
3. **Fase 3: Parser** — Bouwt een volledige Abstract Syntax Tree (AST) met behulp van een LALR(1) Bison-grammatica met strikte operatorprioriteit (PEMDAS + logische kern).
4. **Fase 4: Semantische Analysator** — Voert een pre-pass op functies uit om globale functiesymbolen te registreren, de globale scope te initialiseren en type-annotaties op te lossen.
5. **Fase 5: Emitter** — Doorloopt de AST om Vircon32-assembler te genereren, waarbij registertoewijzing, scope-offsets en peephole-optimalisaties worden toegepast. Ten slotte genereert het de XML-cartridgeconfiguratie.

---

## 3. Build-instructies & Makefile-targets

De repository bevat een Makefile op hoofdniveau om de compilatie van het compiler-binaire bestand, geautomatiseerde tests, implementatie en code-onderhoud te beheren.

### Compilatie-instructies

Om het hoofdbestand van de compiler uit de broncode te bouwen, voert u het standaardtarget uit vanaf de hoofdmap:

```bash
make

```

### Referentietabel van Makefile-targets

| Target | Beschrijving | Kernacties & Afhankelijkheden |
| --- | --- | --- |
| **`all`** | **Standaardtarget.** Bouwt het hoofduitvoerbare bestand van de compiler. | Roept het compilatieproces native aan binnen de `src/` submap. |
| **`clean`** | Standaard hulpprogramma voor het opschonen van de werkruimte. | Verwijdert recursief tussenliggende build-artefacten uit `src/` en verwijdert gegenereerde bestanden uit `testing/` en `demos/`. |
| **`install`** | Installeert het binaire compilerbestand op het hostsysteem. | Geeft het target door aan de gelokaliseerde installatieroutines van de `src/`-map. |
| **`tests`** | Voert de geautomatiseerde compilatitetstsuite uit. | Vereist dat het binaire compilerbestand (`bin/v32lua`) eerst is gebouwd, en activeert vervolgens de testroutines in `testing/`. |
| **`demos`** | Bouwt de verzameling beschikbare demo's. | Vereist dat het binaire compilerbestand (`bin/v32lua`) eerst is gebouwd, en bouwt vervolgens elke demo onder `demos/`. |
| **`asmcheck`** | Valideert de correctheid van de assembler. | Vereist de aanwezigheid van `bin/v32lua` en voert vervolgens assembler-validaties uit via de `testing/` suite. |
| **`monofiles`** | Bouwt gestroomlijnde monolithische bestandsvarianten. | Voert de workflow voor het maken van monolithische bestanden opeenvolgend uit binnen zowel `src/` als `testing/`. |

---

## 4. Cartridge Build-aanwijzingen (`--#`)

`v32lua` introduceert een gespecialiseerde commentaarsyntaxis (`--#`) die fungeert als een inline buildscript voor de Vircon32 ROM-builder. Tijdens de lexicale analyse worden deze instructies onderschept en gecompileerd naar een `<rom-definition>` XML-bestand (`.xml`) samen met de gegenereerde assembler.

### Ondersteunde cartridge-instructies

```lua
--#title "Super Space Shooter 32"
--#version 1.2
--#texture background "assets/bg_stars.png"
--#texture player_sprite "assets/ship.png"

```

* **`--#title <"string">`**: Stelt de cartridge-titelmetadata in de gegenereerde XML in.
* **`--#version <string>`**: Stelt het versie-attribuut in voor de ROM-definitie.
* **`--#texture <var_name> <"pad">`**: Registreert een textuurbron, kent hieraan een oplopend uniek integer-ID toe (beginnend bij `0`), en koppelt het ID aan een globale Lua-variabele (`background`, `player_sprite`, enz.), zodat deze direct kan worden doorgegeven aan GPU-intrinsics zonder handmatige ID-boekhouding.

---

## 5. Doelarchitectuur: Vircon32 & Assemblerontwerp

Voor ontwikkelaars die bekend zijn met C en computerarchitectuur overbrugt `v32lua` high-level scripting met directe hardwarecontrole door rekening te houden met de unieke beperkingen van de Vircon32 CPU.

### Registertoewijzingsschema

De Vircon32 CPU biedt 16 algemene 32-bits registers (`R0` tot en met `R15`). `v32lua` verdeelt deze in strikte functionele rollen:

| Register(s) | Rol & Toewijzingsregels |
| --- | --- |
| **`R0` – `R5**` | **Algemene kladregisters (Scratch) & Expressie-evaluatie:** Dynamisch toegewezen tijdens AST-doorloop voor rekenkunde, logica en functieretourwaarden (`R0`, `R2`, `R3`). |
| **`R6`** | **Voorwaarde-kladregister / Niet-destructieve guard:** Specifiek gereserveerd ter bescherming tegen de destructieve vergelijkingsinstructies van de Vircon32 tijdens vertakkingen (branching) en logische evaluaties. |
| **`R7` – `R10**` | **Algemeen gebruik:** Beschikbaar voor uitgebreide expressie-evaluatie en complexe expressiebomen. |
| **`R11` – `R13**` | **String- & Geheugenhelpers:** Gebruikt door hardware- en runtime-subroutines voor blokgeheugenbewerkingen (`MOVS`, `SETS`, `CMPS`). |
| **`R14` (`BP`)** | **Base Pointer:** Wijst naar de basis van het lokale stackframe van de huidige functie. |
| **`R15` (`SP`)** | **Stack Pointer:** Top van de executiestack. |

### Omgaan met destructieve vergelijkingen

Een kritieke architectonische eigenaardigheid van Vircon32 is dat **vergelijkingsinstructies destructief zijn voor het doelregister**. Bijvoorbeeld, bij het uitvoeren van een integer-gelijkheidscontrole:

```assembly
IEQ R0, R1   ; Evalueert (R0 == R1), slaat het booleaanse resultaat (0 of 1) direct weer op in R0!

```

Als `R0` een variabele bevatte die later opnieuw moest worden gebruikt, zou de vergelijking deze vernietigen. Om dit op te lossen zonder handmatige variabele-duplicatie in Lua, gebruikt `v32lua` **`R6` als een toegewijd voorwaarde-kladregister (condition scratch register)** tijdens voorwaardelijke vertakkingen (`if`, `while`, logische short-circuiting):

```assembly
MOV R6, R0          ; Kopieer operand naar kladregister R6
IEQ R6, 0xFFC00000  ; Voer destructieve test uit tegen de canonieke Nil
JT  R6, __target    ; Spring naar doel als waar (zonder R0 te wijzigen)

```

### Stackframes & Leaf-functie-optimalisatie

Functies die lokale variabelen declareren of complexe geneste aanroepen uitvoeren, genereren een standaard stackframe in C-stijl:

```assembly
__function_my_func:
    PUSH BP
    MOV  BP, SP
    ; ... body ...
    MOV  SP, BP
    POP  BP
    RET

```

* **Lokale variabelen:** Geadresseerd op negatieve offsets ten opzichte van de base pointer: `[BP - 1]`, `[BP - 2]`, enz.
* **Functieparameters:** Op de stack geplaatst (pushed) door de aanroeper voorafgaand aan de aanroep en geadresseerd op positieve offsets: `[BP + 2]`, `[BP + 3]`, enz.

**Optimalisatie:** Voordat prologue-instructies worden gegenereerd, voert `v32lua` een AST-analyse-pass uit (`check_needs_stack`). Als een functie een **Leaf-functie** is (deze roept geen andere functies aan, declareert geen lokale variabelen die naar de stack worden verplaatst, of voert geen complexe tabeltoewijzingen uit), wordt de instelling van de frame pointer (`PUSH BP; MOV BP, SP`) volledig weggelaten. Dit bespaart 4 klokcycli en 2 stack-slots per aanroep.

---

## 6. Het NaN-Boxing Typesysteem

Om Lua's dynamische typering op een 32-bits hardware-architectuur te ondersteunen zonder de overhead van op de heap toegewezen type-wrappers of multi-word getagde unions, implementeert `v32lua` een IEEE 754 **NaN-Boxing** type-representatie.

In IEEE 754 single-precision floating-point vertegenwoordigt elk 32-bits woord waarvan alle 8 exponentbits op 1 staan (`0xFF`) en de mantisse niet nul is, een Not-a-Number (NaN). Dit laat 23 bits aan payloadruimte over binnen de NaN-ruimte om typetags, pointers en speciale constanten te coderen.

### Bit-niveau representatiekaart

```
  31                                  0
  [s | e e e e e e e e | m m m m m ... ]

```

| Type / Waarde | Hexadecimaal Masker | Coderingsdetails |
| --- | --- | --- |
| **Float (Getal)** | `0x00000000` tot `0xFF7FFFFF` | Standaard IEEE 754 single-precision floating-point getallen. |
| **Nil** | `0xFFC00000` | Canonieke Quiet NaN met nul payload. |
| **Boolean False** | `0xFFC00001` | Quiet NaN + Payload Bit 0 ingesteld. |
| **Boolean True** | `0xFFC00002` | Quiet NaN + Payload Bit 1 ingesteld. |
| **String Pointer** | `0x7FC00000` | `adres` |
| **Function Pointer** | `0xFF800000` | `adres` |

### Truthy & Falsy Short-Circuit Evaluatie

In Lua evalueren alleen `nil` en `false` tot onwaar (false) in voorwaardelijke expressies; elke andere waarde (inclusief `0` en lege strings) is **waar (truthy)**. `v32lua` implementeert dit via twee snelle assembler-generatieprimitives:

* **`emit_falsy_jump(reg, label)`**: Test of `reg` overeenkomt met `0xFFC00000` (Nil) of `0xFFC00001` (False). Als een van beide overeenkomt, springt de uitvoering naar het doellabel.
* **`emit_truthy_jump(reg, label)`**: Test tegen Nil en False; als geen van beide overeenkomt, springt de uitvoering (short-circuits) direct naar het doellabel.

Wanneer logische operatoren (`and`, `or`) worden geëvalueerd, blijft het geëvalueerde resultaat intact in het doelregister, waardoor Lua's idioom van het retourneren van de werkelijke operandwaarde in plaats van een strikte booleaanse waarde behouden blijft.

---

## 7. Ondersteunde Lua-taalfuncties

`v32lua` implementeert een robuuste subset van Lua 5.1+, speciaal op maat gemaakt voor game-ontwikkeling op embedded hardware.

### Variabelen & Bereik (Scoping)

* **Globale variabelen:** Automatisch geregistreerd in het RAM (beginnend bij adres `1`, aangezien adres `0` is gereserveerd voor de heap-pointer) en benaderd via symbolen (`[var_name]`, `[func_name]`).
* **Lokale variabelen:** Gedeclareerd met het sleutelwoord `local`. Lexicaal beperkt tot het omsluitende blok (`do ... end`, functielichamen, lussen of voorwaarden) en gekoppeld aan stack-offsets (`[BP - offset]`). Het overschaduwen (shadowing) van buitenste variabelen wordt volledig ondersteund.

### Meervoudige Toewijzing

De compiler ondersteunt native meervoudige toewijzing en het omwisselen van variabelen zonder dat expliciete tijdelijke variabelen van de gebruiker nodig zijn:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Synthetiseert tijdelijke registerketens om waarden veilig om te wisselen

```

### Objectgeoriënteerd Programmeren & Tabellen

`v32lua` biedt naadloze syntactische suiker voor op tabellen gebaseerde OOP-modellen:

* **Syntactische suiker voor functiedefinities:** Het definiëren van een functie op een tabel genereert automatisch een aangepast (mangled) label en koppelt de functiepointer-eigenschap:

```lua
function Player.move(dx, dy) ... end
-- Wordt vertaald naar: Player["move"] = __function_Player_move

```

* **Methode-aanroep via de `:`-operator:** Het gebruik van de dubbele punt-operator evalueert automatisch de tabelexpressie en voegt deze in als een impliciete `self`-parameter:

```lua
Player:move(5, -2)
-- Wordt vertaald naar: Player.move(Player, 5, -2)

```

### Besturingsstroom

* **Lussen:** `while <cond> do ... end` statements ondersteund met volledige blok-scoping.
* **Luscontrole:** `break` statements springen onmiddellijk naar het eindlabel van de huidige binnenste lus (bijgehouden via een interne compilatie-lusstack).
* **Voorwaarden:** `if <cond> then ... elseif <cond> then ... else ... end` structuren met short-circuit vertakkingen.

### Operatoren & Expressies

* **Rekenkundig:** `+`, `-`, `*`, `/` (gekoppeld aan Vircon32 floating-point hardware-instructies `FADD`, `FSUB`, `FMUL`, `FDIV`), en de unaire min (`-` via `__builtin_unm`).
* **Relationeel:** `==`, `~=` (via `__builtin_eq` met NaN-unboxing), `<`, `>`, `<=`, `>=` (via hardware-instructies `FLT`, `FLE`, `FGT`, `FGE`).
* **Logisch:** `and`, `or`, `not` (met short-circuit evaluatie).
* **String-samenvoeging:** De `..` operator plaatst automatisch operanden op de stack en roept de runtime-subroutine `__builtin_strcat` aan.
* **Lengte-operator:** De `#` operator roept `__builtin_len` aan om string- of tabellengtes op te lossen.

### Functies & Meervoudige Retourwaarden

Functies kunnen meerdere waarden tegelijk retourneren. De aanroepconventie optimaliseert de eerste drie geretourneerde expressies door ze direct in de registers `R0`, `R2` en `R3` te plaatsen. Eventuele extra retourwaarden (vanaf de 4e) worden direct op het stackframe van de aanroeper geplaatst op `[BP + 2 + arg_count + offset]`.

### Stringliteral-pooling

Alle stringliterals die in de broncode worden gedeclareerd (bijv. `"GAME OVER"`) worden tijdens de compilatie verzameld, ontdubbeld en geëmitteerd in een speciaal datasegment aan het einde van het ROM (`__string_0: string "GAME OVER"`), wat overbodig ROM-gebruik voorkomt.

---

## 8. Hardware I/O & Compiler-intrinsics

Een van de krachtigste eigenschappen van `v32lua` is de **statische intrinsic-onderscheppingsengine**. Wanneer de compiler tabeltoegangen of functie-aanroepen tegenkomt die overeenkomen met specifieke systeempaden (bijv. `ioports.gpu.clear()`), **omzeilt deze dynamische tabelzoekacties volledig** en genereert deze directe Vircon32 hardware-I/O-instructies (`IN`, `OUT`).

### Automatische Type-casting over I/O-grenzen

Omdat Lua-variabelen worden opgeslagen als NaN-boxed IEEE 754 floats terwijl Vircon32-hardwarepoorten 32-bits integers of booleans verwachten, voegt `v32lua` automatisch hardwareconversie-instructies in tijdens het lezen en schrijven van poorten:

* **`CFI` (Cast Float to Integer):** Automatisch gegenereerd bij het schrijven van numerieke waarden naar integer GPU-/invoerpoorten.
* **`CFB` (Cast Float to Boolean):** Gegenereerd bij het schrijven van booleaanse vlaggen naar hardware-registers.
* **`CIF` (Cast Integer to Float):** Onmiddellijk uitgevoerd na een `IN`-instructie van integer hardwarepoorten, zodat de waarde direct bruikbaar is als een Lua-getal.

---

### Uitgebreide Intrinsics Referentietabel

#### 1. GPU-besturing & Tekenen (`ioports.gpu.*`)

| Lua-pad / Intrinsic | Vircon32 Poort / Commando | Toegang | Beschrijving & Gedrag |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lezen / Schrijven | Stelt het actieve textuur-ID in of leest dit, dat wordt gebruikt voor tekenbewerkingen. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lezen / Schrijven | Selecteert de subregio van de textuur (sprite-frame) om te renderen. |
| **`ioports.gpu.x`** | `GPU_DrawingPointX` | Lezen / Schrijven | X-schermcoördinaat voor tekenpositie. |
| **`ioports.gpu.y`** | `GPU_DrawingPointY` | Lezen / Schrijven | Y-schermcoördinaat voor tekenpositie. |
| **`ioports.gpu.minX`** | `GPU_RegionMinX` | Lezen / Schrijven | Definieert de linker pixelgrens van de actieve textuurregio. |
| **`ioports.gpu.minY`** | `GPU_RegionMinY` | Lezen / Schrijven | Definieert de bovenste pixelgrens van de actieve textuurregio. |
| **`ioports.gpu.maxX`** | `GPU_RegionMaxX` | Lezen / Schrijven | Definieert de rechter pixelgrens van de actieve textuurregio. |
| **`ioports.gpu.maxY`** | `GPU_RegionMaxY` | Lezen / Schrijven | Definieert de onderste pixelgrens van de actieve textuurregio. |
| **`ioports.gpu.hotX`** | `GPU_RegionHotSpotX` | Lezen / Schrijven | Stelt de X-tekenoorsprong (hotspot) in ten opzichte van de sprite-regio. |
| **`ioports.gpu.hotY`** | `GPU_RegionHotSpotY` | Lezen / Schrijven | Stelt de Y-tekenoorsprong (hotspot) in ten opzichte van de sprite-regio. |
| **`ioports.gpu.draw([modus])`** | `GPU_Command` | Functie-aanroep | Voert een hardware-tekencommando uit. Accepteert een optionele stringmodus: `"zoom"` (`GPUCommand_DrawRegionZoomed`), `"rotate"` (`GPUCommand_DrawRegionRotated`), `"rotozoom"` (`GPUCommand_DrawRegionRotozoomed`), of standaard (`GPUCommand_DrawRegion`). |
| **`ioports.gpu.clear([kleur])`** | `GPU_ClearColor` + `GPU_Command` | Functie-aanroep | Stelt de wiskleur in en veegt het scherm schoon (`GPUCommand_ClearScreen`). Ondersteunt vooraf ingestelde kleurstrings: `"black"` (`0x000000FF`), `"white"` (`0xFFFFFFFF`), `"blue"` (`0x0000FFFF`), `"red"` (`0xFF0000FF`), `"green"` (`0x00FF00FF`), of numerieke hex-waarden. |

#### 2. Gamepad & Invoer (`ioports.inp.*`)

| Lua-pad / Intrinsic | Vircon32 Poort / Commando | Toegang | Beschrijving & Gedrag |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lezen / Schrijven | Selecteert de actieve controllerindex (`0` tot `3`) voor invoer-polling. |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Alleen lezen | Retourneert `1` als de geselecteerde gamepad is verbonden, anders `0`. |
| **`ioports.inp.left`** | `INP_GamepadLeft` | Alleen lezen | D-Pad Links status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.right`** | `INP_GamepadRight` | Alleen lezen | D-Pad Rechts status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.up`** | `INP_GamepadUp` | Alleen lezen | D-Pad Omhoog status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.down`** | `INP_GamepadDown` | Alleen lezen | D-Pad Omlaag status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.start`** | `INP_GamepadButtonStart` | Alleen lezen | Start-knop status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.A`** | `INP_GamepadButtonA` | Alleen lezen | Actieknop A status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.B`** | `INP_GamepadButtonB` | Alleen lezen | Actieknop B status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.X`** | `INP_GamepadButtonX` | Alleen lezen | Actieknop X status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.Y`** | `INP_GamepadButtonY` | Alleen lezen | Actieknop Y status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.L`** | `INP_GamepadButtonL` | Alleen lezen | Linker schouderknop (bumper) status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.R`** | `INP_GamepadButtonR` | Alleen lezen | Rechter schouderknop (bumper) status (`1` ingedrukt, `0` losgelaten). |
| **`ioports.inp.inputs`** | *Aangepaste actie-subroutine* | Alleen lezen | **Samenvoegings-intrinsic (Collation Intrinsic):** Voert een snelle pollingreeks uit over alle 11 gamepadknoppen/-assen, verschuift en combineert hun booleaanse staten in een enkele 32-bits integer-bitmasker alvorens te casten naar float (`CIF`). Zeer efficiënt voor momentopnamen van knoptoestanden! |

#### 3. Systeem & Runtime Hulpprogramma's

| Lua-pad / Intrinsic | Vircon32 Instructie | Toegang | Beschrijving & Gedrag |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Functie-aanroep | Genereert de hardware-instructie `HLT`, die de CPU-uitvoering onmiddellijk beëindigt of het frame bevriest tot de volgende interrupt/framecyclus. |
| **`print(...)`** | `__builtin_tostring` + `__builtin_print` | Functie-aanroep | Converteert argumenten naar stringrepresentatie via runtime-conversiesubroutines en voert deze uit naar de debug-consoleterminal. |

---

## 9. Inline Assembler (`__asm__` & `__rawasm__`)

Voor prestatiekritieke binnenste lussen of geavanceerde manipulatie van de Vircon32-hardware (zoals het programmeren van de kanalen van de aangepaste geluidschip of DMA-overdrachten), biedt `v32lua` directe inline assembler-injectie.

### Standaard Inline Assembler (`__asm__`)

De `__asm__` instructie maakt het mogelijk om ruwe Vircon32-assemblerstrings direct in Lua-functies in te bedden. Cruciaal is dat het **variabele-interpolatie** ondersteunt, wat een naadloze brug slaat tussen Lua-scopesymbolen en assembler-registers:

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )

```

* **Hoe het werkt:** Elke identificatie tussen accolades (bijv. `{speed}`) wordt tijdens de compilatie dynamisch opgelost door `emit_interpolated_asm`. Als `speed` is gedeclareerd als een lokale variabele op stack-offset 1, wordt `{speed}` automatisch vervangen door `[BP - 1]`. Als het een globale variabele is, wordt het opgelost tot `[var_speed]`.
* Elke regel van de geïnterpoleerde assembler wordt door de formuleringsengine van de compiler gehaald, wat zorgt voor consistente inspringing en uitlijning van commentaar in het geproduceerde `.asm` bestand.

### Ruwe Assembler (`__rawasm__`)

De `__rawasm__` instructie stuurt de letterlijke string direct naar de assembler-stroom zonder variabele-interpolatie of opmaakwijzigingen. Dit is ideaal voor het definiëren van grote datablokken, aangepaste labels of ruwe binaire payloads.

---

## 10. Codevoorbeeld: Alles Samenbrengen

Het volgende complete voorbeeld toont cartridge-aanwijzingen, tabel-OOP, GPU-tekenintrinsics en inline assembler die samenwerken:

```lua
--#title "Vircon32 Tech Demo"
--#version 1.0
--#texture logo "assets/vircon_logo.png"

-- Definieer een Player-object met Tabel-OOP
Player = {}
function Player:init(x, y)
    self.x = x
    self.y = y
    self.speed = 2.5
end

function Player:render()
    -- Selecteer textuur met automatisch gegenereerd ID uit cartridge-aanwijzing
    ioports.gpu.texture = logo
    ioports.gpu.region = 0
    
    -- Stel tekencoördinaten direct in op hardware-registers
    ioports.gpu.x = self.x
    ioports.gpu.y = self.y
    
    -- Teken met hardware-rotozoom-commando
    ioports.gpu.draw("rotozoom")
end

-- Hoofdspellus
Player:init(160, 120)

while true do
    -- Wis scherm naar donkerblauw
    ioports.gpu.clear("blue")
    
    -- Lees samengevoegde gamepad-bitmasker in een enkele intrinsic-bewerking
    local pad = ioports.inp.inputs
    
    -- Controleer D-Pad Rechts
    if ioports.inp.right == 1 then
        Player.x = Player.x + Player.speed
    end
    
    Player:render()
    
    -- Pauzeer uitvoering tot de volgende frame-interrupt
    system.halt()
end

```

---

## 11. Vreemde eigenschappen en aannames van de compiler

Hoewel `v32lua` probeert een functionele Lua-compiler te zijn, is het geenszins een volledige specificatie-implementatie van de taal. Ten eerste is er geen bytecode virtual machine of interpreter.

Bovendien zijn er enkele expliciete afwijkingen van een standaardimplementatie van de taal om beter aan te sluiten bij de 'freestanding' (vrijstaande) omgeving van Vircon32:

* `print()` vereist, als eerste twee parameters, de `x` en `y` positie op het scherm.
* Standalone `return` statements werken niet (dit zal een syntaxfout genereren). Geef het iets mee (`nil`, 0, enz.) om de compiler tevreden te stellen.
* Programma-uitvoering begint in een verplichte `main()` functie. Het ontbreken van een `main()` leidt tot een fout. Bovendien zal `main()` automatisch een `WAIT` uitvoeren voordat het zichzelf opnieuw aanroept, waardoor dit de natuurlijke locatie voor uw gameloop is. Dit is bedoeld om vergelijkbaar te zijn met andere fantasieconsoles (zoals de `TIC()` functie in de TIC-80, die ook verplicht is).

Het is duidelijk dat deze inspanning is gericht op het maken van een hulpmiddel voor ontwikkeling op Vircon32, en niet om een volledig conforme Lua-implementatie te zijn. Er zullen inspanningen worden geleverd om zo dicht mogelijk en zo haalbaar mogelijk te naderen, zonder significante prestaties op te offeren of af te wijken van het doel waarvoor het is bedoeld.
