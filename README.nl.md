# v32lua: Vircon32 Lua-compiler

[Engelse versie / English version](README.md) | [Spaanse versie / Versión en español](README.es.md)

**Doelarchitectuur:** Vircon32 Fantasy Console (32-bit)

**Implementatietaal:** C (Flex/Bison + Aangepaste Semantische Emitter)

**Repository:** [github.com/wedge1020/v32lua](https://www.google.com/search?q=https://github.com/wedge1020/v32lua)

`v32lua` is een Lua-compiler geschreven in C die zich richt op de **Vircon32** fantasy console. In plaats van een zware bytecode-interpreter in te sluiten, ontleedt `v32lua` Lua-broncode en compileert deze direct naar native Vircon32-assembly, en produceert het tevens XML-cartridgedefinities.

Hoewel het nog niet compleet is, is een van de doelen van de ontwikkeling om van `v32lua` een alternatief (in geen geval een vervanging) te maken voor de Vircon32 C-compiler in de Vircon32-ontwikkelingsstack. U kiest in feite uw taal: C of Lua, waarna u na het compileren assembly heeft en door kunt gaan met de build, ongeacht de implementatietaal. Als gevolg hiervan is er moeite gedaan om verschillende gedragingen van de Vircon32 C-compiler na te bootsen om de vervanging van de compiler transparanter te maken.

Vanaf de grond af ontworpen met de beperkingen van retro fantasy consoles in gedachten, beschikt deze compiler over gratis hardware-intrinsics (zero-cost), aangepaste [NaN-boxing](doc/NaN_boxing.md), algebraïsche peephole-optimalisaties en uitgebreide ontwikkeltools die zijn ontworpen om uw Lua-gameontwikkelingsprojecten te faciliteren.

```
+------------------+     +-------------------+     +------------------+
| Broncode (.lua)  | --> | Lexer & Parser    | --> | AST-constructie  |
+------------------+     | (Flex / Bison)    |     +------------------+
                         +-------------------+              |
                                                            v
+------------------+     +-------------------+     +------------------+
| Cartridge-config | <-- | Vircon32 Assembly | <-- | Semantische      |
| (.xml)           |     | Emitter (.asm)    |     | Emitter & Opt.   |
+------------------+     +-------------------+     +------------------+

```



---

## AI-interactie

OPMERKING: Er was sprake van intensief AI-gebruik en -interactie gedurende dit hele traject. Er moet een onderscheid worden gemaakt met "vibe coding", maar er is absoluut een vage grens tussen mens en AI. Uiteindelijk profiteren beiden en zouden ze elkaars tekortkomingen kunnen compenseren.

Dit project ging eigenlijk niet in de eerste plaats over het ontwikkelen van een compiler; het begon als een oprechte poging om een gevoel te krijgen voor AI en de impact ervan: de rol en het nadeel ervan voor het menselijk denken en het onderwijs. Dat het een compilerthema heeft, was alleen maar om een interessant punt te benadrukken. Het is zeker een leerzame ervaring geweest. Als er voorafgaand aan dit traject onvoldoende compilerconcepten en achtergrondkennis bekend waren geweest, zou deze inspanning minder succesvol zijn geëindigd.

---

## 🚀 Belangrijkste kenmerken & nieuwe ontwikkelingen

### Flexibele uitvoeringsmodellen: `main()` vs. `game_loop()`

Om verschillende stijlen van game-architectuur mogelijk te maken, ondersteunt de compiler twee afzonderlijke ingangspunt-paradigma's:

* **Het automatisch tikkende harnas (`game_loop`)**: Als uw programma een `game_loop()`-functie declareert, genereert de compiler automatisch een continu runtime-harnas. De CPU roept `game_loop()` aan, pauzeert de uitvoering voor de huidige frame met behulp van de hardwarematige `WAIT`-instructie, en blijft dit oneindig herhalen. Dit is ideaal voor standaard arcadegames en demo's. Dit bootst het gedrag van verschillende andere fantasy consoles na.
* **Handmatige bediening (`main`)**: Als uw programma een `main()`-functie declareert, wordt de controle direct overgedragen aan `__function_main`. U neemt het volledige beheer over de framecyclus op u en moet handmatig inline-assembly of hardwarematige wachttijden uitvoeren. De compiler houdt bij of er een `WAIT`-instructie wordt uitgezonden binnen `main()`; als deze ontbreekt, geeft `v32lua` tijdens het compileren een semantische waarschuwing.
* **Initialisatie-hook**: In beide modellen is gegarandeerd dat, als er een `init()`-functie aanwezig is, deze precies één keer wordt uitgevoerd na de toewijzing van global RAM op het hoogste niveau en voordat de hoofdklasse (main loop) begint.

### Verbeterde NaN-boxing: RAM- vs. ROM-elementen

`v32lua` maakt gebruik van een 32-bit tagging-architectuur die type-metadata en payload-pointers verpakt in gecombineerde waarden. Recente verbeteringen scheiden onveranderlijke **ROM-elementen** strikt van dynamische **RAM-heapobjecten** om geheugenveiligheid en nul-kopie literale referenties (zero-copy literal referencing) te garanderen:

| Datatype | Hex Masker / Tag | Beschrijving van de architectuur |
| --- | --- | --- |
| **Nil** | `0xFFC00000` | Canonieke weergave voor ongedefinieerde/ontbrekende waarden. |
| **Boolean False** | `0xFFC00001` | Short-circuit 'falsy' waarde. |
| **Boolean True** | `0xFFC00002` | Short-circuit 'truthy' waarde. |
| **ROM String** | `0x7FC00000` | Pointers naar alleen-lezen stringdatasecties (`__string_%d`) in ROM. |
| **Functie / Closure** | `0xFF800000` | Verpakte (boxed) geheugenadressen van functies (Bit 31=1, Bit 22=0). |
| **Getal** | IEEE 754 Float | Onverpakte (unboxed) native Vircon32 floating-point waarden voor directe wiskunde. |

### Uitgebreide hardware-intrinsics & I/O-mapping

High-performance Vircon32-games kunnen zich geen hashtabel-lookups veroorloven voor hardwaremanipulatie. `v32lua` onderschept specifieke tabel-lidexpressies en compileert deze direct naar native hardware I/O-instructies:

* **Zero-cost hardwaretoegang**: Het benaderen van namespaces zoals `ioports.gpu.*`, `ioports.spu.*`, `ioports.tim.*`, of `system.*` (bijv. `ioports.gpu.x = 100` of `system.frames`) omzeilt de routines voor tabel-lookups volledig. Ze compileren direct naar hardwarepoortbewerkingen (zoals `GPU_DrawingPointX` of `TIM_FrameCounter`).
* **Geconsolideerde gamepad-polling en traditionele invoer**: Het pollen van controllerinvoer is geoptimaliseerd tot één enkele variabele-intrinsic (`ioports.inp.inputs`). De compiler pollt `INP_GamepadLeft` tot en met `INP_GamepadButtonR`, voegt de actieve knopstatussen samen in een bitshifted 32-bit integer-masker en cast dit naar een Lua float in één enkel register. De afzonderlijke gamepad-invoer is ook beschikbaar (`ioports.inp.left`, `ioports.inp.A`, enz.) als variabele-intrinsics voor gebruik.
* **Ingebouwde snelle paden**: Standaard Lua-bewerkingen zoals string-aaneenschakeling (`..`), lengte (`#`) en unaire min (`-`) worden direct gekoppeld aan geoptimaliseerde runtime-subroutines (`__builtin_strcat`, `__builtin_len`, `__builtin_unm`).

### Optimaliserende compiler-pijplijn (`-O1`)

OPMERKING: compileroptimalisaties zijn nog volop in ontwikkeling. Hoewel de infrastructuur is opgebouwd, moet er nog uitgebreid gestreefd en getest worden, en zullen er waarschijnlijk zaken (flink) stukgaan. Alleen de **peephole-optimalisatie** en **frame pointer omission** zijn al aanzienlijk getest, en beide kunnen momenteel niet goed werken door andere recente compilerwijzigingen. Het is waarschijnlijk het beste om optimalisaties op dit punt niet in te schakelen als u werkende uitvoer wilt.

Wanneer optimalisatie is ingeschakeld via opdrachtregel-vlaggen (`o_optflag >= 1`), past `v32lua` code-transformaties in meerdere stadia toe:

* **Peephole-optimalisatie**: Scant de uitgestoten assembly om redundante self-moves (`MOV R0, R0`) en onnodige geheugenherladingen (`MOV A, B` direct gevolgd door `MOV B, A`) te elimineren.
* **Algebraïsche vereenvoudiging**: Vouwt neutrale floating-point bewerkingen samen tijdens het compileren. Expressies zoals `x + 0.0`, `x * 1.0`, `x - 0.0` en `x / 1.0` worden direct vereenvoudigd tot `x`. Zuivere expressies vermenigvuldigd met nul (`x * 0.0`) optimaliseren direct naar `0.000000` zonder de linkeroperant te evalueren als deze geen neveneffecten heeft.
* **Frame Pointer Omission (Leaf-functies)**: Functies die geen lokale variabelen declareren, parameters accepteren of stackframes pushen, strippen de standaard `PUSH BP` / `MOV BP, SP`-proloog en -epiloog volledig, en worden uitgevoerd als kale sprongen (bare jumps).
* **Eliminatie van dode opslag & branches**: Integreert constante propagatie en DSE-trackingtabellen (`DeadStoreCandidate`, `ConstSymbol`) om onbereikbare conditionele branches en ongebruikte variabele-schrijvingen te verwijderen.

### Ontwikkelaarservaring & debug-tools

* **Visuele ASCII-foutrapportage**: Lexicale, syntactische, semantische en interne compilerfouten tonen gemarkeerde, meerregelige ASCII-codefragementen die direct wijzen naar de regel die de fout veroorzaakt in het bronbestand (`yyin`).
* **Bron-naar-assembly mapping (`-g`)**: Het doorgeven van de debug-vlag `-g` genereert een bijbehorend `.debug`-bestand naast de uitvoer-assembly. Dit bestand koppelt relatieve Vircon32-assembly regeloffsets aan originele Lua-bronregels en functionele ingangspunten, waardoor step-through debugging mogelijk wordt. Dit zou identiek moeten zijn aan de `-g` optie van de C-compiler.
* **Inline & ruwe assembly-bubbels**: U kunt native assembly direct in Lua schrijven met behulp van `__asm__("uw ASM")` (wat veilig snapshots maakt en stackpointers en vergrendelde General Purpose Registers `R0`-`R13` herstelt) of `__rawasm__("uw ASM")` voor onbeschermde uitvoering. Beide modi ondersteunen string-interpolatie van Lua-variabelen met dezelfde `{var_name}` syntaxis die aanwezig is in de C-compiler (inline assembly werkt, interpolatie moet nog getest worden).

---

## 🛠️ Cartridge-resource hints

Met `v32lua` kunt u Vircon32-cartridgemetadata direct in uw Lua-broncode insluiten met behulp van speciale blokopmerkingen. De compiler ontleedt deze hints om automatisch de `.xml` ROM-definitie van het project te genereren en sequentiële hardware-resource ID's toe te wijzen.

Ondersteunde hints zijn onder meer:

* `--#version "X.Y"` beïnvloedt het cartridgeversieveld in de XML.
* `--#title "TITLE"` stelt de CART-titel in.
* `--#texture var "path/image.png"` configureert in-game texture.
* `--#sound var "path/sound.wav"` configureert in-game geluid (nog niet voltooid).

```lua
--#version "1.1"
--#title "Space Grinder: Tech Demo"

-- Textures registreren (bindt 'bg_space' automatisch aan ID 0, 'spr_ship' aan ID 1)
--#texture bg_space "assets/background.png"
--#texture spr_ship "assets/player.png"

function init()
    -- Variabelen gedefinieerd uit hints zijn tijdens runtime globaal beschikbaar in Lua!
    ioports.gpu.texture = bg_space
end

```



Na compilatie voert `v32lua` zowel de gecompileerde `.asm`-assembly als een compleet Vircon32 XML-cartridgedefinitiebestand uit, waarbij `.vtex`- en `.vsnd`-assets worden gekoppeld. Met dit alles, en de juiste verwerking van eventuele PNG- en WAV-gegevens, kunt u doorgaan naar de `packrom`-stap.

---

## 💻 Technische demo: Voorbeeldprogramma

Hier is een compleet voorbeeld dat `v32lua`-functies demonstreert, inclusief hardware-intrinsics en de automatisch tikkende game loop:

```lua
--#title "v32lua Tech Demo"
--#version "1.0"
--#texture tex_logo "logo.png"

x_pos = 160.0
y_pos = 120.0
speed = 2.5

function init()
    -- Stel de achtergrond-wiskleur in met zero-cost GPU-poortkoppelingen
    ioports.gpu.bgcolor = 0xFF003366
    ioports.gpu.texture = tex_logo -- stel texture in
    ioports.gpu.region  = 0 -- stel regio in

    -- definieer de regio
    ioports.gpu.minX    = 0
    ioports.gpu.minY    = 0
    ioports.gpu.maxX    = 100
    ioports.gpu.maxY    = 50
    ioports.gpu.hotX    = 0
    ioports.gpu.hotY    = 0
end

function game_loop()

    -- Update de status met behulp van zuivere floating-point wiskunde
    if ioports.inp.left > 1 then
        x_pos = x_pos - speed
    else if ioports.inp.right > 1 then
        x_pos = x_pos + speed
    end

    -- Direct tekenen via de hardware
    ioports.gpu.x = x_pos
    ioports.gpu.y = y_pos
    ioports.gpu.draw()
    
    -- Tabeltoegang en ingebouwde string-aaneenschakeling
    local frame = system.frames
    if frame > 1000 then
        local msg = "Demo Running: Frame " .. frame
        print(msg)
    end
end

```



---

## 📦 Compiler-pijplijn & gebruik

### Compilatiestroom

1. **Lexicale & syntactische analyse**: Flex/Bison ontleedt de Lua-broncode naar een getypeerde Abstract Syntax Tree (AST).
2. **Symbool- & scope-resolutie**: Lost variabelen op via lexicale scopes, waarbij globals worden gekoppeld aan sequentiële RAM-adressen beginnend bij `1`, en locals aan `[BP - offset]` stackframe-posities.
3. **Codegeneratie & peephole-optimalisatie**: Exporteert Vircon32-assembly-instructies terwijl `-O1`-transformaties en hardware-intrinsic vervangingen worden toegepast.
4. **Cartridge-assemblage**: Exporteert het uiteindelijke `.asm`-bestand, sluit runtime ondersteuningsbibliotheken in, genereert de alleen-lezen stringdatasectie en produceert de `.xml` cartridgedefinitie.

### Command-line integratie

```bash
# Compileer met optimalisaties en symboolgeneratie voor debugging
$ v32lua -O1 -g -o program.asm program.lua

```



Beschikbare opties:

* `-O0`: Schakelt compileroptimalisaties uit (standaard).
* `-O1`: Schakelt peephole-optimalisaties, algebraïsche folding en frame pointer omission in.
* `-g`: Genereert het `program.asm.debug` regelmapping tekstbestand.
* `-o`: Specificeert de bestandsnaam voor de assembly-uitvoer (standaard stdout indien weggelaten).
* `-v`: Meer gedetailleerde (verbose) uitvoer.
* `-w`: Onderdruk alle compilerwaarschuwingen.
* `--version`: Toont compilerversie en informatie over de auteur.
* `--help`, `-h`: Toont gebruiksinstructies voor de opdrachtregel.

### Compilatiestadia

Wanneer `-v` is ingeschakeld, rapporteert `v32lua` zijn voortgang via vijf kernstadia van de pijplijn:

1. **Stadium 1: Lexer** — Tokeniseert de Lua-bron, verwijdert standaardopmerkingen en verwerkt string-escape-reeksen (`\n`, `\t`, `\r`, `\\`, `\"`).
2. **Stadium 2: Preprocessor** — Evalueert cartridge-hints (`--#...`) en aangepaste commentaarsyntaxis.
3. **Stadium 3: Parser** — Construeert een complete Abstract Syntax Tree (AST) met behulp van een LALR(1) Bison-grammatica met strikte operatorprioriteit (PEMDAS + logische kern).
4. **Stadium 4: Semantische Analyzer** — Voert een functie pre-pass uit om globale functiesymbolen te registreren, de globale scope te initialiseren en type-annotaties op te lossen.
5. **Stadium 5: Emitter** — Doorloopt de AST om Vircon32-assembly te genereren, en past registertoewijzing, scope-offsets en peephole-optimalisaties toe. Uiteindelijk wordt het cartridge XML-configuratiebestand uitgevoerd.

---

## Bouwinstructies & Makefile-targets

De repository bevat een Makefile op root-niveau voor het beheren van de compilatie van de compilerbinary, geautomatiseerd testen, deployment en codeonderhoud.

### Compilatie-instructies

Om de hoofdcompilerbinary vanaf de bron te bouwen, voert u het standaard target uit in de rootdirectory:

```bash
make

```



### Referentietabel van Makefile-targets

| Target | Beschrijving | Kernacties & afhankelijkheden |
| --- | --- | --- |
| **`all`** | **Standaard Target.** Bouwt het hoofd-compileraanroepbestand. | Roept het compilatieproces direct aan in de subdirectory `src/`. |
| **`clean`** | Standaard opruimprogramma voor de werkruimte. | Wist recursief intermediaire bouwartifacten uit `src/` en verwijdert gegenereerde bestanden uit `testing/` en `demos/`. |
| **`install`** | Installeert de compilerbinary op het hostsysteem. | Geeft de target door aan de lokale installatiescripts in de directory `src/`. |
| **`tests`** | Voert de geautomatiseerde compilatietestsuite uit. | Is expliciet afhankelijk van de compilerbinary (`bin/v32lua`) die eerst gebouwd moet zijn, en activeert dan de testroutines in `testing/`. |
| **`demos`** | Bouwt de verzameling beschikbare demo's. | Is expliciet afhankelijk van de compilerbinary (`bin/v32lua`) die eerst gebouwd moet zijn, en bouwt daarna elke demo onder `demos/`. |
| **`asmcheck`** | Valideert de correctheid van de assembly. | Vereist dat `bin/v32lua` aanwezig is, en verwerkt daarna de assemblyvalidaties via de `testing/`-suite. |
| **`monofiles`** | Bouwt gestroomlijnde monolitische bestandsvarianten. | Voert de `monofile`-creatie-workflow sequentieel uit in zowel `src/` als `testing/`. |

### Truthy & falsy short-circuit evaluatie

In Lua evalueren alleen `nil` en `false` als onwaar in conditionele expressies; elke andere waarde (inclusief `0` en lege strings) is **truthy**. `v32lua` implementeert dit via twee supersnelle assembly-emissieprimitieven:

* **`emit_falsy_jump(reg, label)`**: Test of `reg` overeenkomt met `0xFFC00000` (Nil) of `0xFFC00001` (False). Als een van beide overeenkomt, springt de uitvoering naar het doellabel.
* **`emit_truthy_jump(reg, label)`**: Test op Nil en False; als geen van beide overeenkomt, volgt de uitvoering een short-circuit naar het doellabel.

Wanneer logische operators (`and`, `or`) worden geëvalueerd, blijft het geëvalueerde resultaat intact achter in het bestemmingsregister, behoudens de Lua-traditie om de daadwerkelijke operantwaarde terug te geven in plaats van een strikte boolean.

## Ondersteunde Lua-taalfuncties

`v32lua` implementeert een subset van Lua, specifiek afgestemd op gameontwikkeling op embedded hardware.

### Variabelen & Scoping

* **Globale variabelen:** Worden automatisch geregistreerd in RAM (beginnend bij adres `1`, aangezien adres `0` gereserveerd is voor de heap-pointer) en benaderd via symbolen (`[var_name]`, `[func_name]`).
* **Lokale variabelen:** Gedeclareerd met het trefwoord `local`. Lexicaal afgebakend tot het omringende blok (`do ... end`, functielichamen, loops of conditionaliteiten) en gekoppeld aan stack-offsets (`[BP - offset]`).

In Lua-termen zijn functies "first-class citizens", en zijn ze in feite variabelen. Dat blijkt in `v32lua` doordat ze beide binnen het NaN-boxingschema worden verwerkt.

### Meervoudige toekenning (Multiple Assignment)

De compiler ondersteunt van nature meervoudige toekenning en het verwisselen van variabelen zonder dat er expliciete tijdelijke variabelen (temporaries) door de gebruiker vereist zijn:

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Synthetiseert tijdelijke registerreeksen om waarden veilig te verwisselen

```



### Objectgeoriënteerd programmeren & tabellen

`v32lua` biedt naadloze syntactische suiker voor tabelgebaseerde OOP-modellen:

* **Methodedefinitie-desugaring:** Het definiëren van een functie op een tabel genereert automatisch een gemangled label en koppelt de functiepointer-eigenschap:

```lua
function Player.move(dx, dy) ... end
-- Desugart naar: Player["move"] = __function_Player_move

```



* **Methodeaanroepen desugaring (`:` operator):** Het gebruik van de dubbele-punt-operator evalueert automatisch de tabelexpressie en injecteert deze als een impliciete `self`-parameter:

```lua
Player:move(5, -2)
-- Desugart naar: Player.move(Player, 5, -2)

```



### Controlestroom (Control Flow)

* **Loops:** `while <cond> do ... end`-statements worden ondersteund met volledige blokscoping.
* **Loop-controle:** `break`-statements springen direct naar het eindlabel van de huidige binnenste loop (bijgehouden via een interne compilatie-loopstack).
* **Conditionaliteiten:** `if <cond> then ... elseif <cond> then ... else ... end`-structuren met short-circuit branching.

### Operatoren & Expressies

* **Rekenkundig:** `+`, `-`, `*`, `/` (gekoppeld aan de hardwarematige floating-point instructies `FADD`, `FSUB`, `FMUL`, `FDIV` van Vircon32), en unaire min (`-` via `__builtin_unm`).
* **Relationeel:** `==`, `~=` (via `__builtin_eq` met NaN unboxing), `<`, `>`, `<=`, `>=` (via de hardwarematige `FLT`, `FLE`, `FGT`, `FGE`).
* **Logisch:** `and`, `or`, `not` (met short-circuit evaluatie).
* **String-aaneenschakeling:** De `..`-operator pusht automatisch operanden en roept de runtime-subroutine `__builtin_strcat` aan.
* **Lengte-operator:** De `#`-operator roept `__builtin_len` aan om string- of tabellengtes te bepalen.

### Functies & meerdere retourwaarden

Functies kunnen meerdere waarden tegelijkertijd retourneren. De aanroepconventie optimaliseert de eerste drie geretourneerde expressies door ze direct in de registers `R0`, `R2` en `R3` te plaatsen. Eventuele extra retourwaarden (4e en verder) worden direct naar de stackframe van de aanroeper geschreven op `[BP + 2 + arg_count + offset]`.

### String Literal Pooling

Alle stringliterals die in de broncode worden gedeclareerd (bijv. `"GAME OVER"`), worden tijdens het compileren verzameld, ontdubbeld en uitgezonden naar een specifieke datasectie aan het einde van de ROM (`__string_0: string "GAME OVER"`), wat onnodig ROM-verbruik voorkomt.

---

## Hardware I/O & Compiler-intrinsics

Een van de krachtigste functies van `v32lua` is de **statische intrinsic interceptie-engine**. Wanneer de compiler tabeltoegangen of functieaanroepen tegenkomt die overeenkomen met specifieke systeempaden (bijv. `ioports.gpu.clear()`), **omzeilt het dynamische tabel-lookups volledig** en geeft het directe Vircon32 hardware I/O-instructies (`IN`, `OUT`) af.

### Automatische typecasting via I/O-grenzen

Omdat Lua-variabelen worden opgeslagen als NaN-boxed IEEE 754 floats terwijl Vircon32-hardwarepoorten 32-bit integers of booleans verwachten, injecteert `v32lua` automatisch hardware-conversie-instructies tijdens het lezen en schrijven van poorten:

* **`CFI` (Cast Float to Integer):** Wordt automatisch uitgezonden wanneer numerieke waarden naar integer GPU-/Invoerpoorten worden geschreven.
* **`CFB` (Cast Float to Boolean):** Wordt uitgezonden wanneer boolean-vlaggen naar hardwareregisters worden geschreven.
* **`CIF` (Cast Integer to Float):** Wordt direct uitgezonden na het uitvoeren van een `IN`-instructie vanaf integer hardwarepoorten, om ervoor te zorgen dat de waarde meteen bruikbaar is als een Lua-getal.

---

### Uitgebreide referentietabel voor intrinsics

#### GPU-bediening & tekenen (`ioports.gpu.*`)

| Lua-pad / Intrinsic | Vircon32 Poort / Commando | Toegang | Beschrijving & gedrag |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lezen / Schrijven | Stelt het actieve texture-ID in of leest dit uit voor tekenbewerkingen. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lezen / Schrijven | Selecteert de subregio van de texture (spriteframe) om te renderen. |
| **`ioports.gpu.x`** | `GPU_DrawingPointX` | Lezen / Schrijven | X-schermcoördinaat voor de plaatsing van het tekenen. |
| **`ioports.gpu.y`** | `GPU_DrawingPointY` | Lezen / Schrijven | Y-schermcoördinaat voor de plaatsing van het tekenen. |
| **`ioports.gpu.minX`** | `GPU_RegionMinX` | Lezen / Schrijven | Bepaalt de linker pixelgrens van het actieve texture-gebied. |
| **`ioports.gpu.minY`** | `GPU_RegionMinY` | Lezen / Schrijven | Bepaalt de bovenste pixelgrens van het actieve texture-gebied. |
| **`ioports.gpu.maxX`** | `GPU_RegionMaxX` | Lezen / Schrijven | Bepaalt de rechter pixelgrens van het actieve texture-gebied. |
| **`ioports.gpu.maxY`** | `GPU_RegionMaxY` | Lezen / Schrijven | Bepaalt de onderste pixelgrens van het actieve texture-gebied. |
| **`ioports.gpu.hotX`** | `GPU_RegionHotSpotX` | Lezen / Schrijven | Stelt de X-oorsprong van het tekenen (hotspot) in ten opzichte van het spritegebied. |
| **`ioports.gpu.hotY`** | `GPU_RegionHotSpotY` | Lezen / Schrijven | Stelt de Y-oorsprong van het tekenen (hotspot) in ten opzichte van het spritegebied. |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Functieaanroep | Voert een hardwarematig tekencommando uit. Accepteert een optionele string-modus: `"zoom"` (`GPUCommand_DrawRegionZoomed`), `"rotate"` (`GPUCommand_DrawRegionRotated`), `"rotozoom"` (`GPUCommand_DrawRegionRotozoomed`), of standaard (`GPUCommand_DrawRegion`). |
| **`ioports.gpu.clear([color])`** | `GPU_ClearColor` + `GPU_Command` | Functieaanroep | Stelt de wiskleur in en wist het scherm (`GPUCommand_ClearScreen`). Ondersteunt vooraf ingestelde kleurstrings: `"black"` (`0x000000FF`), `"white"` (`0xFFFFFFFF`), `"blue"` (`0x0000FFFF`), `"red"` (`0xFF0000FF`), `"green"` (`0x00FF00FF`), of numerieke hex-waarden. |

#### Gamepad & Invoer (`ioports.inp.*`)

| Lua-pad / Intrinsic | Vircon32 Poort / Commando | Toegang | Beschrijving & gedrag |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lezen / Schrijven | Selecteert de actieve controllerindex (`0` tot `3`) voor het pollen van invoer. |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Alleen Lezen | Retourneert `1` als de geselecteerde gamepad is aangesloten, anders `0`. |
| **`ioports.inp.left`** | `INP_GamepadLeft` | Alleen Lezen | D-Pad Links richtingstatus (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.right`** | `INP_GamepadRight` | Alleen Lezen | D-Pad Rechts richtingstatus (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.up`** | `INP_GamepadUp` | Alleen Lezen | D-Pad Omhoog richtingstatus (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.down`** | `INP_GamepadDown` | Alleen Lezen | D-Pad Omlaag richtingstatus (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.start`** | `INP_GamepadButtonStart` | Alleen Lezen | Startknop status (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.A`** | `INP_GamepadButtonA` | Alleen Lezen | Actieknop A status (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.B`** | `INP_GamepadButtonB` | Alleen Lezen | Actieknop B status (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.X`** | `INP_GamepadButtonX` | Alleen Lezen | Actieknop X status (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.Y`** | `INP_GamepadButtonY` | Alleen Lezen | Actieknop Y status (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.L`** | `INP_GamepadButtonL` | Alleen Lezen | Linker Shoulder Bumper status (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.R`** | `INP_GamepadButtonR` | Alleen Lezen | Rechter Shoulder Bumper status (`> 0` ingedrukt, `< 0` losgelaten). |
| **`ioports.inp.inputs`** | *Aangepaste actie-subroutine* | Alleen Lezen | **Samenvoegende intrinsic:** Voert een snelle multi-poort pollingreeks uit langs alle 11 gamepadknoppen/assen, verschuift en combineert hun boolean-statussen in één enkel 32-bit integer bitmasker alvorens te casten naar een float (`CIF`). Uiterst efficiënt voor snapshots van knopstatussen! |

#### Systeem- & runtime-hulpprogramma's

| Lua-pad / Intrinsic | Vircon32 Instructie | Toegang | Beschrijving & gedrag |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Functieaanroep | Geeft de hardwarematige `HLT`-instructie af, waarmee de CPU-uitvoering onmiddellijk wordt beëindigd of de frame wordt bevroren tot de volgende interrupt/framecyclus. |
| **`system.wait()`** | `WAIT` | Functieaanroep | Geeft de hardwarematige `WAIT`-instructie af, waarmee de uitvoering wordt gepauzeerd tot de volgende interrupt/framecyclus. |
| **`print(x, y, ...)`** | `__builtin_tostring` + `__builtin_print` | Functieaanroep | Dwingt argumenten in string-representatie via runtime-conversiesubroutines en voert ze uit naar de debug-consoleterminal. De eerste twee parameters zijn de X, Y-positie op het scherm, in pixels. |

---

## Inline Assembly (`__asm__` & `__rawasm__`)

Voor prestatiekritische binnenste loops of geavanceerde Vircon32-hardwaremanipulatie biedt `v32lua` directe inline assembly-injectie.

### Standaard Inline Assembly (`__asm__`)

De `__asm__`-richtlijn maakt het mogelijk om onbewerkte Vircon32-assemblystrings direct in Lua-functies in te sluiten. Cruciaal is dat het **variabele-interpolatie** ondersteunt, wat naadloze overbrugging tussen Lua-scopesymbolen en assemblyregisters mogelijk maakt:

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )

```



* **Hoe het werkt:** Elke identificator omhuld door accolades (bijv. `{speed}`) wordt tijdens het compileren dynamisch opgelost door `emit_interpolated_asm`. Als `speed` een lokale variabele is op stack-offset 1, wordt `{speed}` automatisch vervangen door `[BP - 1]`. Als het een global is, wordt het opgelost naar `[var_speed]`.
* Elke regel van de geïnterpoleerde assembly wordt door de indelings-engine van de compiler geleid, wat zorgt voor een consistente inspringing en uitlijning van commentaar in het uitvoer `.asm`-bestand.
* Deze standaard inline assembly past enkele lichte vangrails en beschermingen toe in de vorm van het back-uppen van reeds gebruikte registers en de stack. Hoewel het problemen niet volledig voorkomt, kan het helpen om sommige problemen die door ongelukjes ontstaan te beperken. Let op: eventuele registerwijzigingen die hier worden gemaakt, gaan verloren buiten de inline "bubbel".

### Ruwe Assembly (`__rawasm__`)

De `__rawasm__`-richtlijn voert de letterlijke string direct uit naar de assembly-stroom zonder dat er veiligheidsmaatregelen worden toegepast. Dit kan erg gevaarlijk zijn en moet alleen worden gebruikt door de meest deskundige en ervaren assembly-gebruikers.

---

## 🧠 Referentietabel geheugenkaart

| RAM-adresbereik | Aanduiding | Gebruik |
| --- | --- | --- |
| `0` | `heap_pointer` | Slaat het dynamische startadres op voor runtime-tabeltoewijzingen. |
| `1` tot `N` | Global RAM | Sequentieel toegewezen slots voor globale Lua-variabelen en resource-ID's. |
| `N + 1`+ | Dynamische Heap | Runtime-geheugen beheerd door `__builtin_table_new` en string-allocators. |
| Top van Stack (`SP`) | Call Stack | Activatierecords van functies, lokale variabelen en opgeslagen registerstatussen. |

---

## Compiler-eigenaardigheden en aannames

Hoewel `v32lua` probeert een functionele Lua-compiler te zijn, is het in geen geval een implementatie die volledig aan alle specificaties van de taal voldoet. Zo is er bijvoorbeeld geen bytecode virtuele machine of interpreter.

Bovendien zijn er enkele expliciete afwijkingen van een standaardtaalimplementatie om beter aan te sluiten op de vrijstaande (freestanding) omgeving van Vircon32:

* `print()` vereist de `x`- en `y`-positie op het scherm als de eerste twee parameters.
* Alleenstaande `return`-statements werken niet (dit zal een syntaxfout opleveren). Geef het iets (`nil`, 0, enz.) mee om het tevreden te stellen.
* Programma-uitvoering MOET binnen een functie plaatsvinden. Hoewel u functies kunt declareren, moet u een van de aangewezen startpunten gebruiken om de uitvoeringsketen te starten (in de vorm van `init()`, `game_loop()`, of `main()`). Het ontbreken van een `main()`- of `game_loop()`-functie zal leiden tot een fout. Bovendien zal `game_loop()` automatisch een `WAIT` afgeven alvorens zichzelf weer aan te roepen, waardoor dit uw natuurlijke locatie voor de game loop is. Dit is bedoeld om te lijken op andere fantasy consoles (zoals de `TIC()`-functie in TIC-80, wat een vergelijkbare vereiste is).

Het is duidelijk dat dit project gericht is op het maken van een tool voor ontwikkeling op de Vircon32, en niet om een volledig conforme Lua-implementatie te zijn. Er zal moeite worden gedaan om zo dichtbij als mogelijk en haalbaar te komen, zonder dat er aanzienlijke prestaties worden opgeofferd of wordt afgeweken van de tool die het bedoeld is te zijn.
