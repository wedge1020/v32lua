# API native de la console de fantaisie Vircon32

Ce document couvre UNIQUEMENT l'API native de Vircon32 — la surface active
lorsque ni le mode de compatibilité `--#api pico8` ni `--#api tic80` n'est
sélectionné. Sous ces modes, `spr()`/`btn()`/etc. sont à la place la propre
API de cette console (voir la documentation de compatibilité PICO-8 /
TIC-80), et les appels ci-dessous ne sont pas disponibles.

L'[Aide-mémoire](#quick-reference) ci-dessous liste sur une seule page
toutes les intrinsèques et tous les ports `ioports.*` ; les sections
suivantes détaillent chaque partie.

L'ordre d'écriture des ports SPU compte pour le son ; voir
[Son : music.\* / sfx.\*](#son--music--sfx).

---

## Table des Matières

- [Aide-mémoire](#quick-reference)
  - [Fonctions intrinsèques](#intrinsic-functions)
  - [ioports.\* — tous les ports matériels](#ioports--every-hardware-port)
  - [Bibliothèque standard](#standard-library)
- [Son : music.\* / sfx.\*](#son--music--sfx)
- [ioports.spu.cmd() — l'échappatoire brute](#ioportsspucmd--léchappatoire-brute)
- [Ports d'E/S booléens](#ports-des-booléens)
- [Système : system.\*](#système--system)
- [Graphismes : spr()](#graphismes--spr)
- [Graphismes : rect() / rectfill()](#graphismes--rect--rectfill)
- [Entrées : btn() / btnp()](#entrées--btn--btnp)
- [Clavier : key() / keyp() / kbd.\*](#clavier--key--keyp--kbd)
- [Tilemap : tilemap.\*](#tilemap--tilemap)
- [Carte mémoire : memcard.\*](#carte-mémoire--memcard)
- [Autres ports d'E/S bruts](#autres-ports-des-bruts)

---

<a id="quick-reference"></a>
## Aide-mémoire

Une **intrinsèque** est un nom que le compilateur reconnaît et transforme
en instructions en ligne ou en appel d'une routine du runtime : il n'y a
ni table ni fonction Lua derrière. Une fonction à vous portant le même
nom (`spr`, `rgba`, `color`, …) remplace l'intrinsèque.

<a id="intrinsic-functions"></a>
### Fonctions intrinsèques

*Graphismes*

| Appel | Renvoie | Ce qu'il fait |
|---|---|---|
| `spr(region, x, y [, sx [, sy [, angle [, color [, blend]]]]])` | nil | Dessine une région de texture ; choisit le dessin simple, zoomé, pivoté ou les deux selon les arguments. [Détails](#graphismes--spr) |
| `rect(x1, y1, x2, y2 [, color])` | nil | Contour de rectangle de 1 pixel entre deux coins inclus. Couleur : mot empaqueté, blanc par défaut. [Détails](#graphismes--rect--rectfill) |
| `rectfill(x1, y1, x2, y2 [, color])` | nil | Rectangle plein, un seul dessin GPU. |
| `print(x, y, value)` | nil | Dessine `value` (convertie par `tostring`) au pixel `x, y` avec la police du BIOS. |
| `ioports.gpu.clear([color])` / `clear(r, g, b [, a])` | nil | Fixe la couleur d'effacement (facultatif) et efface l'écran. [Détails](#gpu-clear) |
| `ioports.gpu.draw([mode])` | nil | Dessine la région sélectionnée en `gpu.x, gpu.y`. `mode` : `"draw"` (par défaut), `"zoom"`, `"rotate"`, `"rotozoom"`, ou `0`–`3`. |
| `ioports.gpu.blending(mode)` | nil | Fixe le mode de mélange : `"alpha"`/`"default"`, `"add"`, `"subtract"` (littéral chaîne). |
| `ioports.gpu.sync()` | nil | Attend l'image suivante (`WAIT`) ; identique à `system.wait()`. |
| `rgba(r, g, b [, a])` | mot assemblé | Assemble une couleur dans le mot `0xAABBGGRR` du GPU. Composantes bornées à 0–255, alpha 255 par défaut. [Détails](#colors-rgba) |
| `color(n)` | mot assemblé | Transforme un nombre contenant une couleur assemblée en mot (couleurs calculées ou chargées). [Détails](#colors-color) |
| `hex("0x…")` | mot assemblé | Un littéral chaîne de chiffres hexadécimaux, sous forme du mot 32 bits exact. |

*Entrées*

| Appel | Renvoie | Ce qu'il fait |
|---|---|---|
| `btn(id [, pad])` | booléen | Le bouton `id` (0–10, ordre matériel) est enfoncé. [Détails](#entrées--btn--btnp) |
| `btnp(id [, pad])` | booléen | Le bouton `id` a été pressé à cette image. |

*Clavier* (périphérique v32kbd) — [détails](#clavier--key--keyp--kbd)

| Appel | Renvoie | Ce qu'il fait |
|---|---|---|
| `key([k])` | booléen | La touche `k` (code ou nom littéral : `"a"`, `"enter"`, `"shift"`) est enfoncée ; sans `k` : n'importe quelle touche. |
| `keyp([k [, hold, period]])` | booléen | La touche `k` s'est enfoncée à cette image (répétition avec `hold`/`period`, comme TIC-80). |
| `kbd.read()` | nombre / nil | Appui suivant sous forme du caractère tapé (Maj et Verr Maj appliqués). |
| `kbd.event()` | nombre / nil | Événement suivant : `+code` enfoncée, `-code` relâchée. |
| `kbd.port([n])` | nombre | Port de manette du clavier (1 par défaut) ; le changer repart de zéro. |
| `kbd.capslock()`, `kbd.connected()` | booléen | État de Verr Maj ; périphérique branché. |
| `kbd.clear()` | nil | Oublie les événements non lus. |

*Son* — [détails](#son--music--sfx)

| Appel | Renvoie | Ce qu'il fait |
|---|---|---|
| `music.play(snd [, ch [, loop [, vol [, start]]]])` | canal | Joue un son, sur le canal 0 par défaut. |
| `music.pause([ch])`, `music.resume([ch])`, `music.stop([ch])` | nil | Contrôle du canal. |
| `music.playing([ch])` | booléen | Le canal joue-t-il. |
| `music.volume(vol [, ch])` | nil | Volume du canal. |
| `sfx.play(snd [, ch [, vol [, speed]]])` | canal | Joue un effet sur le prochain des canaux 1–15. |
| `sfx.stop([ch])`, `sfx.volume(vol [, ch])` | nil | Arrête les effets (canaux 1–15), règle le volume. |
| `ioports.spu.cmd(mode)` (ou `.command`) | nil | Commande SPU brute sur le canal sélectionné. [Détails](#ioportsspucmd--léchappatoire-brute) |

*Tilemaps, carte mémoire, système*

| Appel | Renvoie | Ce qu'il fait |
|---|---|---|
| `tilemap.get(MAP, x, y)` | nombre / nil | Tuile en `x, y` d'un `--#tilemap`. [Détails](#tilemap--tilemap) |
| `tilemap.set(MAP, x, y, v)` | v | Change une tuile (la carte est copiée en RAM à la première écriture). |
| `tilemap.render(MAP, sx, sy, w, h, x, y, tw, th [, skip])` | nil | Dessine un bloc de tuiles. |
| `memcard.save(v [, pos])`, `memcard.load([pos])` | v | Lit/écrit un mot sur la carte mémoire. [Détails](#carte-mémoire--memcard) |
| `memcard.load_table(pos)` | table / nil | Charge une table enregistrée avec `memcard.save(t)`. |
| `memcard.title(str)` | nil | Fixe le titre de sauvegarde de la carte. |
| `memcard[pos]`, `memcard[pos] = v` | | Identiques à `load` / `save`. |
| `system.wait()` / `system.halt()` | nil | `WAIT` jusqu'à l'image suivante / `HLT`. [Détails](#système--system) |
| `system.date()` / `system.time()` | chaîne, 3 nombres | `"YYYY-MM-DD", a, m, j` / `"HH:MM:SS", h, m, s`. |
| `system.frames()` / `system.cycles()` | nombre | Images depuis la mise sous tension / cycles CPU de l'image en cours (aussi sans `()`). |

*Langage et assembleur en ligne*

| Appel | Ce qu'il fait |
|---|---|
| `tostring(v)`, `tonumber(s [, base])`, `type(v)` | Comme en Lua. |
| `pairs(t)`, `ipairs(t)` | Itérateurs pour `for k, v in …`. |
| `setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawlen`, `rawequal` | Métatables : `__index`, `__newindex`, `__call`, `__tostring`, `__len`, `__metatable`. |
| `__asm__("…")` | Assembleur en ligne avec substitution `{var}` ; registres et pile sont sauvegardés autour. |
| `__rawasm__("…")` | Assembleur recopié tel quel dans la sortie. |

`print` et `ioports.*` sont des noms du mode natif ; sous `--#api pico8`
ou `--#api tic80`, `print`, `spr`, `btn`, etc. sont les fonctions de
cette console (voir [PICO8.md](PICO8.md) et [TIC80.md](TIC80.md)).
Non disponibles : `printf`, `pcall`/`error`/`assert`, `select`, `next`,
`string.match`/`gmatch`, `os.*`, `io.*`, `coroutine.*`.

<a id="ioports--every-hardware-port"></a>
### ioports.\* — tous les ports matériels

Chaque propriété lit ou écrit directement un port d'E/S de Vircon32
(`IN`/`OUT`), sans consultation de table. Types :

* **int** — un nombre entier. La lecture donne un nombre Lua ; l'écriture
  d'un nombre le tronque vers zéro (`CFI`). Un littéral numérique est
  écrit sous forme du mot 32 bits exact, si bien que
  `ioports.gpu.bgcolor = 0xFF003366` et `ioports.gpu.x = -5` stockent
  tous deux ce que vous avez écrit (voir
  [Ports entiers et littéraux](#integer-ports-and-literals)).
* **float** — un nombre Lua, stocké tel quel.
* **bool** — un booléen Lua : la lecture donne `true`/`false`, l'écriture
  teste la véracité Lua. Voir [Ports d'E/S booléens](#ports-des-booléens).
* **color** — un port int qui contient un mot `0xAABBGGRR` assemblé.
  Écrivez un littéral, `rgba()`, `color()` ou `hex()` ; un nombre calculé
  à l'exécution est converti en entier, ce qui ne donne pas les mêmes
  bits.

L = lecture, É = écriture.

**ioports.gpu.\* — graphismes**

| Propriété | Port | Accès | Type | Signification |
|---|---|---|---|---|
| `ioports.gpu.texture` | `GPU_SelectedTexture` | L/É | int | Texture utilisée par les réglages de région et les dessins (noms `--#texture`, ou -1 pour la texture du BIOS). |
| `ioports.gpu.region` | `GPU_SelectedRegion` | L/É | int | Région (0–4095) de la texture sélectionnée à définir ou dessiner. |
| `ioports.gpu.minX`, `minY` | `GPU_RegionMinX/Y` | L/É | int | Coin supérieur gauche de la région, en pixels de texture. En écrire un fixe aussi `hotX`/`hotY` à la même valeur. |
| `ioports.gpu.maxX`, `maxY` | `GPU_RegionMaxX/Y` | L/É | int | Coin inférieur droit de la région (inclus). |
| `ioports.gpu.hotX`, `hotY` | `GPU_RegionHotSpotX/Y` | L/É | int | Point chaud de la région : le point placé en `gpu.x, gpu.y`. À fixer après `minX/minY`. |
| `ioports.gpu.x`, `y` | `GPU_DrawingPointX/Y` | L/É | int | Position à l'écran du prochain dessin. |
| `ioports.gpu.scaleX`, `scaleY` | `GPU_DrawingScaleX/Y` | L/É | float | Échelle des dessins zoomés. |
| `ioports.gpu.angle` | `GPU_DrawingAngle` | L/É | float | Angle des dessins pivotés, en radians. |
| `ioports.gpu.bgcolor` | `GPU_ClearColor` | L/É | color | Couleur utilisée par `clear()`. |
| `ioports.gpu.multiply` | `GPU_MultiplyColor` | L/É | color | Couleur par laquelle chaque dessin est multiplié (`0xFFFFFFFF` = inchangé). |
| `ioports.gpu.blending` | `GPU_ActiveBlending` | L/É | int | Numéro du mode de mélange (alpha `0x20`, add `0x21`, subtract `0x22`) ; ou appelez `ioports.gpu.blending("add")`. |
| `ioports.gpu.pixels` | `GPU_RemainingPixels` | L | int | Pixels que le GPU peut encore dessiner à cette image. |

Méthodes : `ioports.gpu.clear()`, `ioports.gpu.draw()`,
`ioports.gpu.blending()`, `ioports.gpu.sync()` (voir le tableau
ci-dessus).

**ioports.inp.\* — manettes**

| Propriété | Port | Accès | Type | Signification |
|---|---|---|---|---|
| `ioports.inp.gamepad` | `INP_SelectedGamepad` | L/É | int | Manette (0–3) lue par les autres propriétés. Sa lecture renvoie la dernière valeur affectée (les émulateurs ne savent pas relire ce port ; voir [Le port de manette](#clavier--key--keyp--kbd)). |
| `ioports.inp.status` | `INP_GamepadConnected` | L | bool | La manette sélectionnée est-elle connectée. |
| `ioports.inp.left`, `right`, `up`, `down` | `INP_GamepadLeft/…` | L | int | Croix : images depuis l'appui (> 0) ou depuis le relâchement (< 0). |
| `ioports.inp.A`, `B`, `X`, `Y`, `L`, `R`, `START` | `INP_GamepadButton*` | L | int | Boutons, même codage. |
| `ioports.inp.inputs` | (tous les précédents) | L | int | Tous les boutons de la manette sélectionnée en un masque de bits, enfoncé = 1 : bit 10 gauche, 9 droite, 8 haut, 7 bas, 6 START, 5 A, 4 B, 3 X, 2 Y, 1 L, 0 R. |

**ioports.spu.\* — son**

| Propriété | Port | Accès | Type | Signification |
|---|---|---|---|---|
| `ioports.spu.volume` | `SPU_GlobalVolume` | L/É | float | Volume général. |
| `ioports.spu.channel` | `SPU_SelectedChannel` | L/É | int | Canal (0–15) sur lequel agissent les propriétés `chan*` et `cmd()`. |
| `ioports.spu.sound` | `SPU_SelectedSound` | L/É | int | Son (nom `--#sound`) sur lequel agissent les propriétés de son. |
| `ioports.spu.length` | `SPU_SoundLength` | L | int | Longueur du son sélectionné, en échantillons. |
| `ioports.spu.soundloop` | `SPU_SoundPlayWithLoop` | L/É | bool | Le son sélectionné boucle par défaut. |
| `ioports.spu.loopstart`, `loopend` | `SPU_SoundLoopStart/End` | L/É | int | Points de boucle du son sélectionné, en échantillons. |
| `ioports.spu.state` | `SPU_ChannelState` | L | int | Canal sélectionné : 0x40 arrêté, 0x41 en pause, 0x42 en lecture. |
| `ioports.spu.chansound` | `SPU_ChannelAssignedSound` | L/É | int | Son attribué au canal sélectionné. |
| `ioports.spu.chanvolume` | `SPU_ChannelVolume` | L/É | float | Volume du canal. |
| `ioports.spu.chanspeed` | `SPU_ChannelSpeed` | L/É | float | Vitesse de lecture du canal (1.0 = normale). |
| `ioports.spu.chanloop` | `SPU_ChannelLoopEnabled` | L/É | bool | Le canal boucle. À fixer **après** `cmd("play")`. |
| `ioports.spu.chanpos` | `SPU_ChannelPosition` | L/É | int | Position de lecture du canal, en échantillons. |

Méthode : `ioports.spu.cmd(mode)` / `ioports.spu.command(mode)` —
`"play"`, `"pause"`, `"stop"`, `"resume"`, `"pauseall"`, `"stopall"`,
`"resumeall"`.

**ioports.tim.\*, rng, car, mem — minuterie, nombres aléatoires, cartouche, carte mémoire**

| Propriété | Port | Accès | Type | Signification |
|---|---|---|---|---|
| `ioports.tim.date` | `TIM_CurrentDate` | L | int | Année × 65536 + jour de l'année (`system.date()` le décode). |
| `ioports.tim.time` | `TIM_CurrentTime` | L | int | Secondes depuis minuit (`system.time()` le décode). |
| `ioports.tim.frames` | `TIM_FrameCounter` | L | int | Images depuis la mise sous tension (= `system.frames`). |
| `ioports.tim.cycles` | `TIM_CycleCounter` | L | int | Cycles CPU de l'image en cours (= `system.cycles`). |
| `ioports.rng.value` | `RNG_CurrentValue` | L | int | Nombre aléatoire matériel suivant. |
| `ioports.rng.seed` | `RNG_CurrentValue` | É | int | Initialise le générateur matériel. |
| `ioports.car.connected` | `CAR_Connected` | L | bool | Une cartouche est insérée. |
| `ioports.car.romsize` | `CAR_ProgramROMSize` | L | int | Taille de la ROM programme, en mots. |
| `ioports.car.numvtex`, `numvsnd` | `CAR_NumberOfTextures/Sounds` | L | int | Textures / sons de la cartouche. |
| `ioports.mem.connected` | `MEM_Connected` | L | bool | Une carte mémoire est insérée. |

Écrire un port en lecture seule, lire un port en écriture seule, ou un nom
inconnu (`ioports.gpu.colour`) est une erreur de compilation qui liste les
noms valides.

<a id="standard-library"></a>
### Bibliothèque standard

| Bibliothèque | Fonctions |
|---|---|
| `math` | `abs acos asin atan atan2 ceil cos cosh deg exp floor fmod frexp ldexp log log10 max min modf pow rad random randomseed sin sinh sqrt tan tanh`, constantes `pi huge e` |
| `string` | `byte char find format gsub len lower rep reverse sub upper` (aussi en méthodes : `s:sub(1, 3)`) |
| `table` | `concat insert move pack remove sort unpack` |
| opérateurs | `+ - * / % ^ //`, `..`, `#`, `== ~= < > <= >=`, `and or not`, `& | ~ << >>` (voir le README) |

Les nombres sont des float32 (24 bits significatifs) ; les chaînes qui
ressemblent à des nombres sont converties dans les calculs (`"5" + 1`
vaut 6), comme en Lua.

---

## Son : music.\* / sfx.\*

```
music.play(SOUND [, CHANNEL [, LOOP [, VOL [, START]]]])  -> canal utilisé
music.pause  ([CHANNEL])
music.resume ([CHANNEL])
music.stop   ([CHANNEL])
music.playing([CHANNEL])                                  -> booléen
music.volume (VOL [, CHANNEL])

sfx.play(SOUND [, CHANNEL [, VOL [, SPEED]]])             -> canal utilisé
sfx.stop([CHANNEL])
sfx.volume(VOL [, CHANNEL])

ioports.spu.cmd(MODE)   -- échappatoire brute, voir ci-dessous
```

`music` utilise par défaut le canal 0. `sfx.play()` sans canal tourne en
rotation (round-robin) sur les canaux 1–15 via un mot de RAM réservé par
le compilateur (`VIRCON32_SFX_CURSOR`), de sorte qu'un effet ne coupe
jamais la musique. `sfx` ne boucle jamais : tout ce qui doit être soutenu
passe par `music.play(..., true)` sur son propre canal.

`sfx.stop()` sans canal arrête uniquement les canaux 1–15, délibérément
PAS `StopAllChannels`, qui couperait aussi la musique. C'est
`__builtin_vircon32_sfx_stop_all`.

Le curseur avance de manière inconditionnelle plutôt que de rechercher un
canal inactif : chercher coûterait jusqu'à 15 `IN` + comparaisons sur le
chemin critique (`sfx.play()` s'exécute à chaque saut et chaque pas) pour
se prémunir contre un cas qui ne survient que lorsque 15 effets se
chevauchent, où le plus ancien est de toute façon le bon candidat à
perdre.

**SPU de Vircon32 : l'ordre d'écriture des ports**

*La règle*

```asm
OUT SPU_SelectedChannel, ch
OUT SPU_Command, SPUCommand_StopSelectedChannel   ; 1
OUT SPU_ChannelAssignedSound, snd
OUT SPU_ChannelVolume, R                          ; port flottant
OUT SPU_Command, SPUCommand_PlaySelectedChannel
OUT SPU_ChannelLoopEnabled, 0|1                   ; 2 - APRÈS la commande
OUT SPU_ChannelPosition, samples                  ; 3 - APRÈS la commande
```

Trois comportements de la console imposent cela. Les trois échouent **en
silence** — pas d'erreur, pas d'écriture de port rejetée, juste le mauvais
son.

**1. Un son ne s'assigne qu'à un canal ARRÊTÉ.**
**2 et 3. La commande de lecture écrase à la fois la boucle ET la
position.**

Un drapeau de boucle ou une recherche (seek) écrits *avant* la commande
sont ignorés. Notez que le drapeau de boucle est remplacé par le
`PlayWithLoop` du SON, qui est faux à moins que quelque chose n'ait défini
`SPU_SoundPlayWithLoop` sur ce son — donc le bouclage au niveau du canal
ne fonctionne que s'il est écrit après la commande. Écrivez-le même quand
il vaut 0, puisque la commande vient juste de le remplacer par le drapeau
du son.

Pour un canal **En Pause (Paused)**, `PlayChannel()` ne prend aucune des
deux branches — elle se contente de définir `State = Playing`. C'est ce
qui fait de Play la reprise correcte par canal, et pourquoi resume ne
perturbe jamais la position ni la boucle.

*États des canaux et ce que signifie réellement resume*

`channel_stopped 0x40`, `channel_paused 0x41`, `channel_playing 0x42`.
`SPU_ChannelState` est **en lecture seule** (`WriteSPUChannelState`
renvoie faux).

Il n'existe pas de commande `ResumeSelectedChannel`. `ResumeAllChannels`
est littéralement une boucle qui appelle `PlayChannel()` sur chaque canal
en pause, donc `resume(ch)` = `PlaySelectedChannel` est le bon équivalent
par canal.

**Un « resume » qui redémarre depuis le début signifie que le canal était
ARRÊTÉ, pas en pause.** C'est la signature diagnostique d'un drapeau de
boucle perdu : le son est arrivé à sa fin, le canal est passé à Arrêté, et
Play l'a rembobiné.

`PauseChannel()` définit `State = Paused` de manière inconditionnelle —
elle ne vérifie *pas* si le canal est déjà arrêté, malgré le fait que la
documentation de l'API C indique que pause n'a « aucun effet si déjà
arrêté ». Ainsi, mettre en pause un canal terminé le laisse En Pause à la
position 0, et une reprise ultérieure lit depuis le début. Protégez-vous
avec une vérification `SPU_ChannelState == 0x42` si cela importe.

*Types de ports*

`SPU_ChannelPosition` est un port **ENTIER** — un index d'échantillon,
borné par la console à `0 .. SoundLength-1`. `audio.h` déclare
`set_channel_position( int )`, et `WriteSPUChannelPosition()` lit
`Value.AsInteger`. La table IOPortMap avait `ioports.spu.chanpos` déclaré
en `IOPORT_TYPE_FLOAT`, ce qui y écrivait des motifs de bits flottants
bruts ; corrigé en `IOPORT_TYPE_INTEGER`.

Ports véritablement flottants : `SPU_ChannelVolume` (borné 0–8),
`SPU_ChannelSpeed` (0–128, change la hauteur du son), `SPU_GlobalVolume`
(borné 0–2). Les écritures NaN/inf sur l'un de ces ports sont ignorées
plutôt que rejetées.

**music.volume(VOL [, CHANNEL]) / sfx.volume(VOL [, CHANNEL])**

Définit le volume de lecture. `VOL` est obligatoire. `CHANNEL` a **trois**
significations distinctes selon ce qu'écrit le site d'appel :

| Appel | Signification |
|---|---|
| `music.volume(VOL)` | applique `VOL` à chaque canal que **cet espace de noms possède actuellement** (voir le suivi de possession de canal, ci-dessous) |
| `music.volume(VOL, -1)` | le véritable volume **global** matériel (`SPU_GlobalVolume`, borné 0–2) — tous les canaux, inconditionnellement |
| `music.volume(VOL, N)` | le volume de ce canal précis (`SPU_ChannelVolume`, borné 0–8), `N` dans 0–15 |

`sfx.volume` se comporte de manière identique, sur les propres canaux
suivis de `sfx`.

```lua
music.play(MUSIC, 0, true)   -- réclame le canal 0 pour la musique
sfx.play(BLIP)                -- réclame un canal 1-15 pour le sfx

sfx.volume(0.3)               -- baisse UNIQUEMENT le(s) canal/canaux sfx ci-dessus ;
                               -- le canal 0 (musique) n'est pas touché
music.volume(0.5)             -- baisse la musique ; le sfx n'est pas touché
music.volume(1.0, 0)          -- canal 0 spécifiquement, volume maximal
sfx.volume(0.0, -1)           -- véritable coupure globale du son, les deux espaces de noms
```

Les numéros de canal explicites (`N` ou `-1`) ne changent jamais la
possession — seul `.play()` le fait. Un canal en pause ou arrêté est
toujours trouvé par le mode « canaux suivis » sans argument ; seule la
lecture d'un canal *différent* sous l'autre espace de noms le libère.

*Suivi de possession de canal*

Deux mots de RAM réservés par le compilateur, `VIRCON32_MUSIC_CHANNEL_MASK`
et `VIRCON32_SFX_CHANNEL_MASK`, chacun un masque de bits sur les canaux
0–15 : le bit *N* activé signifie que le canal *N* s'est vu assigner en
dernier un son par le `.play()` de cet espace de noms. La possession est
exclusive par construction — chaque `music.play(S, ch)` réclame `ch` pour
la musique et l'efface du masque sfx, et chaque `sfx.play(S, ch)` fait
l'inverse — puisqu'un canal n'appartient en réalité à aucun des deux
espaces de noms au niveau matériel, seulement par convention selon la
manière dont les appels `.play()` du jeu l'ont utilisé. Les deux masques
commencent à 0 (rien de réclamé) ; `music.volume(VOL)`/`sfx.volume(VOL)`
sans canal est un no-op tant que rien n'a réellement été lu sur cet
espace de noms.

Seul `.play()` touche les masques. `.pause()`, `.resume()`, `.stop()`, et
`.volume()` lui-même ne le font jamais — donc un canal actuellement en
pause ou arrêté reste « possédé » par celui qui y a lu en dernier, et
reste capté par le mode volume sans argument.

*Génération de code*

Un appel entièrement littéral (`music.volume(0.5, 0)`, `sfx.volume(0.0, -1)`)
se replie en une séquence linéaire de `OUT` à la compilation, comme le
reste de cette surface. `music.volume(VOL)`/`sfx.volume(VOL)` sans
argument de canal est **toujours** un `CALL` — quels canaux sont
actuellement possédés n'est connu qu'à l'exécution — vers
`__builtin_vircon32_volume_mask`, qui boucle sur les bits 0–15 du masque
de l'espace de noms et écrit `SPU_ChannelVolume` pour chacun activé. Tout
autre appel à valeur dynamique va vers `__builtin_vircon32_volume`, qui
compare la valeur du canal à `-1` (global) à l'exécution et borne dans le
cas contraire.

**Pourquoi les noms nus ont disparu**

`play` / `pause` / `resume` / `stop` étaient les quatre identifiants les
plus sujets aux collisions qu'un jeu pouvait vouloir pour lui-même, ce que
l'ancienne garde de contournement `resolve_symbol()` dans le répartiteur
compensait. Ils ont disparu ; les espaces de noms les remplacent, et le
mécanisme d'alias les restaure par choix plutôt que par défaut.

**Alias à la compilation**

`play = music.play` enregistre un alias et n'émet rien. Les appels
ultérieurs à `play(...)` compilent vers la séquence `OUT` en ligne
identique — aucune valeur à l'exécution, aucun CALL, aucune RAM. La
surface pouvant recevoir un alias est `music.play`, `music.pause`,
`music.resume`, `music.stop`, `music.playing`, `music.volume`,
`sfx.play`, `sfx.stop`, et `sfx.volume`.

- `register_intrinsic_aliases_prepass()` s'exécute avant la génération de
  code, donc un alias déclaré en bas d'un fichier régit un appel situé en
  haut.
- La résolution se produit dans `try_emit_call_intrinsic()` immédiatement
  après `resolve_static_path()`, donc un appel aliasé est indiscernable
  du chemin réel partout en aval.
- `node_multiple_assignment()` n'émet rien pour une déclaration d'alias ;
  `node_identifier()` produit une erreur si l'un d'eux est lu comme une
  valeur.

Limites, toutes délibérées :

- Un alias est un NOM, pas une VALEUR. `{ hit = sfx.play }` ou le passer à
  une fonction est une erreur de compilation nommant la limitation, pas
  une mauvaise compilation.
- Les alias sont valables pour tout le programme. `local p = music.play`
  compile mais avertit — le `local` ne le limite pas dans sa portée.
- L'aliasing d'espace de noms (`m = music` puis `m.play()`) n'est pas pris
  en charge.
- Les cibles d'alias consomment quand même un mot de RAM global, puisque
  `register_all_globals_prepass` les considère comme des cibles
  d'affectation. Un mot chacune ; cela ne vaut pas la peine de
  déstabiliser la table des symboles pour cela.

Si des valeurs de fonction sonore de première classe sont un jour
souhaitées, le précédent est `__mathfn_sin` / `__mathfn_log` dans
runtime.s — de véritables étiquettes encapsulées avec `BOXED_FUNCTION`,
résolues dans `try_emit_table_get_intrinsic()` où `math.sin` en tant que
valeur existe déjà. Ce serait additif ; la table d'alias reste le chemin à
coût nul.

**music.playing() et pourquoi un drapeau Lua est le mauvais interrupteur**

`SPU_ChannelState` est un port entier en lecture seule qui renvoie
`channel_stopped` 0x40, `channel_paused` 0x41, `channel_playing` 0x42.
`music.playing(ch)` sélectionne le canal, le lit, et renvoie un véritable
booléen Lua.

Un interrupteur pause/resume construit sur un drapeau Lua se dérègle dès
qu'un son se termine de lui-même : le programme croit toujours qu'il est
en lecture, donc l'appui suivant met en pause un canal déjà arrêté au
lieu de le reprendre. Interroger le matériel ne peut pas se dérégler.

**Génération de code : repliement hybride**

Tous les arguments connus à la compilation → séquence linéaire de `OUT`,
pas de CALL. Tout ce qui est dynamique → empile et fait un CALL vers la
routine d'exécution, qui gère la valeur par défaut pour nil, le décodage
de la véracité (truthiness) Lua, et le bornage de canal. Tout ou rien : un
seul argument dynamique envoie tout l'appel sur le chemin d'exécution.

`sfx.play()` nécessite en plus un canal *littéral explicite* pour pouvoir
se replier, puisque le chemin automatique doit lire et avancer le
curseur. `sfx.play(BLIP)` — la forme courante — est donc toujours un
CALL, qui est aussi l'émission la plus petite.

Les noms `--#sound` comptent comme connus à la compilation :
`node_cart_hint()` attribue déjà à `MUSIC` son identifiant de ressource,
donc `music.play(MUSIC, 0)` émet `OUT SPU_ChannelAssignedSound, 0` plutôt
que de lire la globale en RAM. Le repliement est supprimé lorsque
`spu_name_is_rebound()` trouve que le nom a été réaffecté, utilisé comme
variable de boucle, déclaré comme paramètre, ou mentionné dans de
l'assembleur en ligne n'importe où dans l'AST.

---

## ioports.spu.cmd() — l'échappatoire brute

Émet une commande SPU brute contre ce que `SPU_SelectedChannel` nomme
actuellement. Aucune sélection de canal, aucune assignation de son,
aucune valeur par défaut — associez-la aux propriétés `ioports.spu.*` pour
les séquences que les intrinsèques ne couvrent pas (fondus enchaînés,
recherche précise à l'échantillon près, points de boucle personnalisés).

Elle porte les mêmes contraintes d'ordre de ports que tout le reste :
définissez `chanloop` **après** `cmd("play")`, jamais avant.

Modes : `"play"` 0, `"pause"` 1, `"stop"` 2, `"pauseall"` 3, `"resume"` 4,
`"allstop"` 5, plus les alias `"resumeall"` et `"stopall"`. Omis ou nil →
`"play"`.

---

## Ports d'E/S booléens

Un booléen Lua n'est pas un flottant. `true`/`false`/`nil` sont des motifs
de bits encapsulés en NaN ; les ports matériels échangent en entiers 0 et
1. Les écritures décodent la véracité (truthiness) Lua (seuls `nil` et
`false` sont faux), avec des littéraux se repliant en un immédiat 0/1 brut.
Les lectures se branchent vers `BOXED_TRUE`/`BOXED_FALSE`.

Affecte `ioports.spu.chanloop`, `ioports.spu.soundloop`,
`ioports.inp.status`, `ioports.car.connected`, `ioports.mem.connected`.

Les ports booléens renvoient `true`/`false`, pas `1.0`/`0.0`.
L'arithmétique sur l'un d'eux doit être réécrite sous la forme
`if p then 1 else 0`.

---

## Système : system.\*

```
system.wait()   -> nil   (WAIT jusqu'au prochain signal de nouveau cycle)
system.halt()   -> nil   (HLT -- arrête le CPU)
system.date()   -> chaîne, année, mois, jour
system.time()   -> chaîne, heure, minute, seconde
```

**system.wait() / system.halt()**

`system.wait()` se compile directement en `WAIT` — la même instruction
qu'utilise `ioports.gpu.sync()`, et interchangeable avec elle ; toutes
deux attendent simplement le prochain signal de nouveau cycle de la
minuterie. `system.halt()` se compile en `HLT`, arrêtant le CPU purement
et simplement — pour un programme qui a terminé son travail et n'a plus
rien à afficher.

**system.date() / system.time()**

Les deux décodent l'horloge temps réel de la puce de minuterie (voir la
Spécification Système Vircon32, Partie 7, section 1.2 — c'est une
véritable horloge murale/RTC, pas un compteur monotone depuis le
démarrage) et renvoient **quatre** valeurs : une chaîne formatée, puis les
trois composantes numériques.

```lua
local date_str, year, month, day     = system.date()   -- "2026-09-06", 2026, 9, 6
local time_str, hour, minute, second = system.time()    -- "03:00:04", 3, 0, 4
```

La chaîne de `system.date()` est `"AAAA-MM-JJ"` ; celle de `system.time()`
est `"HH:MM:SS"`. Les deux sont toujours complétées par des zéros à une
largeur fixe (le `%0*d` de `printf`, pas un plafond strict) — `year` est
complétée à 4 chiffres mais jamais tronquée, donc une année au-delà de
9999 (jusqu'au maximum matériel de `CurrentYear`, 65535) s'affiche quand
même en entier, simplement plus large que 4 caractères ; mois/jour/
heure/minute/seconde font toujours exactement 2 chiffres. Les années
bissextiles suivent la règle grégorienne standard (divisible par 4, sauf
les siècles à moins d'être divisibles par 400) — la spécification
confirme que la plage du nombre de jours s'étend à 365 lors d'une année
bissextile mais ne définit pas la règle elle-même, donc c'est la seule
lecture saine et universelle de celle-ci. Il n'y a pas de chaîne de
format ni de construction de table à la `os.time()`/`os.date()` — c'est
un décodage à forme fixe du registre matériel, pas une bibliothèque de
dates générale.

**system.frames / system.cycles**

```lua
local f = system.frames()   -- TIM_FrameCounter -- images depuis la mise sous tension
local c = system.cycles()   -- TIM_CycleCounter -- cycles CPU depuis le début de l'image
```

Les deux sont des compteurs matériels en lecture seule, et aucun n'est
une heure réelle. `system.frames()` compte les images depuis la mise sous
tension ; `system.cycles()` compte les cycles CPU depuis le début de
l'image en cours et repart de 0 à chaque image, si bien que le lire juste
avant `system.wait()` indique quelle part du budget CPU de l'image a été
utilisée. `system.frames()` est
naturellement adapté au minutage du type « toutes les N images, fais X »
(c'est exactement ce que la démo de défilement de tilemap utilise pour
cadencer sa vitesse de défilement) puisqu'il tourne librement quoi que
fasse le programme, contrairement à une variable de comptage artisanale
qu'il faut se rappeler d'incrémenter à chaque image. Les deux sont
également accessibles en tant que ports bruts (`ioports.tim.frames`,
`ioports.tim.cycles`) — voir [Autres ports d'E/S bruts](#autres-ports-des-bruts)
— les noms `system.*` sont identiques, simplement sous l'espace de noms
le plus facile à découvrir.

---

## Graphismes : spr()

```
spr(region_id, x, y [, scale_x [, scale_y [, angle_deg [, color_mult [, blend_mode]]]]])
```

Dessine la région de texture `region_id` de la GPU (telle que déclarée par
un indice `--#texture`, ou un index de région brut) à la position de
pixel `(x, y)`.

| Argument | Par défaut | Notes |
|---|---|---|
| `region_id` | obligatoire | index de région GPU (`GPU_SelectedRegion`) |
| `x`, `y` | obligatoires | position de dessin en haut à gauche, `GPU_DrawingPointX/Y` |
| `scale_x`, `scale_y` | `1.0` | facteurs d'échelle X/Y indépendants |
| `angle_deg` | `0` | rotation, en **degrés**, sens antihoraire ; convertie en radians en interne (le `GPU_DrawingAngle` de la console est en radians) |
| `color_mult` | `0xFFFFFFFF` | couleur de multiplication RGBA compressée — `0xFFFFFFFF` signifie « aucun changement » |
| `blend_mode` | `"alpha"` (`0x20`) | une chaîne nommant le mode ou sa valeur numérique — voir les modes de fondu ci-dessous |

Un argument peut être **omis** (simplement arrêter de fournir les
arguments suivants) ou passé comme un **`nil` explicite** pour le sauter
et atteindre un argument ultérieur — `spr(id, x, y, nil, nil, 45)` pour
faire pivoter sans toucher à l'échelle — les deux signifient « utiliser la
valeur par défaut ».

Modes de fondu — passez soit la chaîne du nom, soit le nombre :

| Chaîne | Nombre | Effet |
|---|---|---|
| `"alpha"` ou `"default"` | `0x20` | fondu alpha normal (par défaut) |
| `"add"` | `0x21` | additif — éclaircit ce qui est dessous |
| `"subtract"` | `0x22` | soustractif — assombrit ce qui est dessous |

```lua
spr(7, 100, 80, nil, nil, nil, nil, "add")       -- effet de lueur / lumière
spr(7, 100, 80, nil, nil, nil, nil, 0x21)        -- la même chose, en numérique
spr(7, 100, 80, nil, nil, nil, 0x80FFFFFF, "alpha")
```

La chaîne du mode doit être une **chaîne littérale** ; elle est résolue en
son nombre à la compilation, et toute autre chaîne (`"multiply"`, une
faute de frappe) est une erreur de compilation. Une chaîne stockée dans
une variable n'est pas reconnue (il n'y a pas de dispatch de chaînes à
l'exécution — elle atteindrait le GPU comme un pointeur, pas comme un
mode) ; gardez plutôt le mode dans une variable sous forme de nombre
(`local mode = 0x21`). Les nombres sont transmis tels quels, comme avant.

`spr()` ne renvoie rien (`nil` Lua), ce qui correspond au fait que la
console n'a aucune valeur significative à renvoyer d'un appel de dessin.
Plus de 8 arguments déclenche un avertissement à la compilation ; les
arguments en trop sont ignorés.

**Répartition à l'exécution, pas de repliement à la compilation**

Contrairement à l'API son, `spr()` appelle toujours
`__builtin_vircon32_spr` — il n'existe aucun chemin rapide en `OUT`
linéaire pour un appel entièrement littéral. La routine lit les valeurs
réelles à l'exécution de `scale_x`/`scale_y`/`angle_deg` à *chaque*
appel et choisit la moins coûteuse des quatre commandes de dessin GPU à
chaque fois :

| Condition | Commande |
|---|---|
| échelle = 1,1 et angle = 0 | `GPUCommand_DrawRegion` |
| échelle ≠ 1 et angle = 0 | `GPUCommand_DrawRegionZoomed` |
| échelle = 1,1 et angle ≠ 0 | `GPUCommand_DrawRegionRotated` |
| échelle ≠ 1 et angle ≠ 0 | `GPUCommand_DrawRegionRotozoomed` |

`color_mult` et `blend_mode` sont écrits inconditionnellement à chaque
appel, avant cette répartition — `GPU_MultiplyColor` et
`GPU_ActiveBlending` sont un état GPU persistant que chaque variante de
dessin consulte, contrairement à `GPU_DrawingScaleX/Y`/`GPU_DrawingAngle`,
qui ne sont écrits que dans les branches qui les utilisent réellement
(sans danger de les laisser périmés, puisque par exemple
`DrawRegionRotated` est défini pour ignorer entièrement l'échelle).

`color_mult` est un mot compressé `0xAABBGGRR`, écrit tel quel dans
`GPU_MultiplyColor`, sans conversion flottant → entier (le même modèle que
`ioports.gpu.clear(couleur)`). Un littéral numérique (`0xFFFFFFFF`,
`0x80FFFFFF`, `-1`) est converti en ce mot à la compilation. Toute autre
expression doit déjà contenir le mot compressé : `rgba(r, g, b [, a])`
(voir [Couleurs : rgba()](#colors-rgba)), `hex("0xFF8080FF")`, ou une
variable affectée depuis l'un d'eux. Un nombre calculé à l'exécution n'est
*pas* converti — un float32 ne peut pas représenter exactement une couleur
32 bits. Pour une couleur qui change à l'exécution (un fondu), gardez les
composantes sous forme de nombres et assemblez-les au moment du dessin :

```lua
spr(REGION_SOLID, x, y, w, h, 0, rgba(0, 0, 0, frame * 8))   -- fondu au noir
```

Un `nil` explicitement passé pour un argument optionnel (par exemple
`spr(id, x, y, nil, nil, 45)`) est traité de façon identique à cet
argument étant totalement omis — les deux retombent sur la valeur par
défaut. Un appel situé dans un contexte d'expression
(`local unused = spr(1, 10, 10)`) se voit correctement assigner `nil`,
comme tout autre intrinsèque de ce document.

<a id="gpu-clear"></a>
**ioports.gpu.clear([couleur]) / ioports.gpu.clear(r, g, b [, a])**

Efface l'écran : écrit `GPU_ClearColor` (si une couleur est donnée) puis
émet `GPUCommand_ClearScreen`. Omettez les arguments pour effacer avec ce
que `GPU_ClearColor` contient actuellement. La couleur peut être donnée de
quatre façons :

| Forme | Exemple | Notes |
|---|---|---|
| nom prédéfini | `clear("black")` | `"black"`, `"white"`, `"blue"`, `"red"`, `"green"` — chaîne littérale, résolue à la compilation ; tout autre nom est une erreur de compilation |
| littéral compressé | `clear(0xFF202020)` | `0xAABBGGRR` ; replié à la compilation en mot brut de 32 bits |
| mot compressé | `clear(rgba(32, 32, 32))`, `clear(hex("0xFF202020"))`, `clear(c)` | une valeur non littérale est écrite telle quelle sur le port, elle doit donc déjà contenir le mot brut — c'est-à-dire provenir de `rgba()` ou de `hex()` |
| composantes | `clear(32, 32, 32)`, `clear(r, g, b, 128)` | rouge, vert, bleu, alpha, chacune de `0` à `255` ; alpha est facultatif et vaut `255` (opaque) par défaut |

```lua
ioports.gpu.clear("black")
ioports.gpu.clear(0xFF202020)       -- 0xAABBGGRR compressé, gris foncé
ioports.gpu.clear(32, 32, 32)       -- le même gris foncé, en composantes
ioports.gpu.clear(r, g, b)          -- fonctionne aussi avec des variables ; alpha = 255
ioports.gpu.clear(0, 0, 64, 128)    -- bleu foncé semi-transparent
ioports.gpu.clear()                 -- réutilise le dernier ClearColor défini
```

Notez que l'ordre des octets du GPU est `0xAABBGGRR` — le rouge est
l'octet de *poids faible* — c'est la raison principale de la forme en
composantes : `clear(r, g, b)` les range dans le bon ordre pour vous.

La forme en composantes accepte 3 ou 4 arguments (2, ou plus de 4, est une
erreur de compilation). Quand toutes les composantes sont littérales, elle
est repliée en une seule constante à la compilation — les littéraux hors
plage sont bornés à `0`–`255` avec un avertissement. Sinon chaque
composante est évaluée comme une expression ordinaire, bornée à
`0`–`255`, tronquée en entier et assemblée à l'exécution. Un `nil`
explicite pour `a` signifie opaque, comme l'omettre, de même qu'un alpha
valant `nil` à l'exécution ; il n'y a pas de vérification de nil à
l'exécution sur le rouge, le vert et le bleu, donc une variable valant
`nil` à cet endroit donne une couleur indéfinie.

*Pourquoi une variable compressée a besoin de `hex()` :* les nombres de
v32lua sont des float32, donc un nombre comme `0xFF202020` stocké dans une
variable contient un flottant, pas les bits de la couleur, et `clear()` ne
peut pas les distinguer à l'exécution. Les littéraux écrits directement
dans l'appel fonctionnent, car ils sont repliés à la compilation. `rgba()`
(ci-dessous) produit aussi le mot brut.

<a id="colors-rgba"></a>
**Couleurs : rgba(r, g, b [, a])**

Renvoie le mot compressé `0xAABBGGRR` du GPU pour une couleur — le mot brut
de 32 bits, *pas* un nombre Lua — pour tout ce qui en attend un : le
`color_mult` de `spr()`, `ioports.gpu.clear(couleur)`,
`ioports.gpu.multiply`, `ioports.gpu.bgcolor`.

```lua
spr(id, x, y, 1, 1, 0, rgba(255, 255, 255, alpha))   -- fondu
ioports.gpu.multiply = rgba(r, g, b)                 -- sans conversion flottante
ioports.gpu.clear(rgba(16, 16, 48))
```

* 3 ou 4 arguments (tout autre nombre est une erreur de compilation).
  L'alpha vaut 255 par défaut ; un alpha `nil` (littéral ou à l'exécution)
  vaut aussi 255.
* Chaque composante est bornée à `0`–`255` et tronquée (`127.9` → 127),
  exactement comme `clear(r, g, b [, a])`, dont elle partage le code.
* Des arguments tous littéraux sont repliés à la compilation en une seule
  constante (`rgba(1, 2, 3, 4)` vaut `0x04030201`) ; les littéraux hors
  plage sont bornés avec un avertissement. Sinon l'assemblage se fait à
  l'exécution ; des composantes qui appellent des fonctions sont sûres.
* Mode Vircon32 natif uniquement. Une fonction à vous nommée `rgba` a la
  priorité.

**Attention — gardez les composantes, pas le mot.** Un mot brut dont les
bits de poids fort correspondent à l'une des étiquettes de valeur du
langage *est* cette valeur pour le reste du programme : `rgba(0, 0, 192,
255)` vaut `0xFFC00000`, c'est-à-dire `nil`, et `0xFF8xxxxx` se lit comme
une table. Le passer directement à un appel ou à un port est toujours sûr
(il est seulement copié). Le ranger dans une table (une valeur `nil`
supprime la clé), le tester (`if c then`) ou le comparer à `nil` ne l'est
pas. `hex()` a le même problème. L'usage sûr est de garder les
composantes sous forme de nombres et d'appeler `rgba()` là où la couleur
est utilisée, comme dans les exemples ci-dessus.

<a id="colors-color"></a>
**Couleurs : color(n)**

Transforme un nombre qui contient une couleur assemblée `0xAABBGGRR` en
mot brut, pour les couleurs que vous avez sous forme de nombre plutôt que
de composantes : calculée par arithmétique, lue dans une table de
couleurs ou chargée depuis la carte mémoire.

```lua
local palette = { 0xFF1D2B53, 0xFF7E2553, 0xFF008751 }
ioports.gpu.multiply = color(palette[i])
spr(id, x, y, 1, 1, 0, color(base + fade * 0x01000000))
```

* Un argument (tout autre nombre d'arguments est une erreur de
  compilation ; un littéral chaîne, `nil` ou booléen aussi).
* Le nombre est arrondi à l'entier inférieur puis ramené sur 32 bits, si
  bien qu'un nombre négatif donne son mot en complément à deux
  (`color(-1)` vaut `0xFFFFFFFF`). Les valeurs hors de `[-2^31, 2^32)`
  sont saturées.
* Un littéral est replié à la compilation et reste exact :
  `color(0x802040FF)` vaut `0x802040FF`.
* À l'exécution, le nombre est un float32, qui ne garde que 24 bits
  significatifs : une couleur dont les bits s'étendent sur plus de 24 est
  arrondie avant que `color()` ne la voie. Une variable contenant
  `0x802040FF` donne `0x80204100`. Les couleurs d'alpha `0xFF` et beaucoup
  d'autres valeurs courantes sont exactes (`0xFF003366`, `0x80FFFFFF`),
  mais quand les bits exacts comptent, gardez les composantes et utilisez
  `rgba()`.
* Même mise en garde que pour `rgba()` sur les mots qui ressemblent à
  `nil` ou à une table.
* Mode Vircon32 natif uniquement. Une fonction à vous nommée `color` a la
  priorité (le `color()` de PICO-8 est la fonction de PICO-8).

<a id="integer-ports-and-literals"></a>
**Ports entiers et littéraux**

Un nombre écrit dans un port entier (`ioports.gpu.x`, `bgcolor`,
`multiply`, …) est converti par `CFI`, tronqué vers zéro. Un **littéral
numérique** est au contraire écrit tel quel sous forme de mot 32 bits
exact, calculé à la compilation : `ioports.gpu.bgcolor = 0xFF003366`
stocke `0xFF003366` (une conversion de float le saturerait),
`ioports.gpu.x = -5` stocke `-5` et `ioports.gpu.y = 12.7` stocke `12`.
Les littéraux hors de `[-2^31, 2^32)` sont saturés avec un avertissement.

**Définir des régions de texture**

Le `region_id` de `spr()` ne fait référence à rien tant qu'une région n'a
pas réellement été découpée dans une texture chargée. Il n'existe aucune
création de région côté compilateur — ce sont six écritures de ports
brutes, normalement faites une fois dans `init()` (ou une fois par
texture au début de `main()` s'il n'y a pas de `init()` séparé), une
région à la fois :

```lua
ioports.gpu.texture = SPRITES   -- sélectionne dans quelle texture chargée cette région est découpée
ioports.gpu.region  = 1         -- sélectionne l'EMPLACEMENT de région 1 à définir (c'est l'id que spr() utilisera)
ioports.gpu.minX = 6            -- coin supérieur gauche de la région, en pixels de texture
ioports.gpu.minY = 156
ioports.gpu.maxX = 58           -- coin inférieur droit, inclus
ioports.gpu.maxY = 208
ioports.gpu.hotX = 6            -- voir ci-dessous -- PAS 0
ioports.gpu.hotY = 156          -- voir ci-dessous -- PAS 0
```

*Points chauds des régions : ce qu'il faut savoir et ce que fait le compilateur*

Le point chaud (hotspot) d'une région permet de la dessiner par rapport à
un point de référence, mais l'oublier peut poser problème : un point
chaud non défini peut valoir 0, 0 par défaut. Si ce point est assez loin
des coins de la région, celle-ci risque de ne pas se dessiner là où vous
le voulez, voire pas du tout à l'écran.

C'est pourquoi `v32lua` fixe automatiquement `ioports.gpu.hotX` et
`ioports.gpu.hotY`, afin qu'une région dont le point chaud a été oublié
reste visible :

quand on écrit le X et le Y minimaux d'une région, le X et le Y du point
chaud prennent exactement les mêmes valeurs. Le point chaud est donc par
défaut le coin supérieur gauche de la région.

Pour placer le point chaud ailleurs qu'au coin supérieur gauche, il
suffit de le fixer APRÈS avoir écrit les X et Y minimaux.

`GPU_RegionMinX/MinY/MaxX/MaxY/HotSpotX/HotSpotY` sont les ports bruts
derrière `ioports.gpu.minX` etc. — voir la table complète des ports dans
[Autres ports d'E/S bruts](#autres-ports-des-bruts) pour tout le reste
qu'expose `ioports.gpu.*` (point de dessin, échelle, angle, couleur de
multiplication, mélange, et le compteur en lecture seule GPU-occupée
`ioports.gpu.pixels`).

---

## Graphismes : rect() / rectfill()

```
rect(x1, y1, x2, y2 [, color])       -- contour de 1 pixel
rectfill(x1, y1, x2, y2 [, color])   -- plein
```

`(x1, y1)` et `(x2, y2)` sont deux coins opposés, tous deux **inclus**, dans
n'importe quel ordre : `rectfill(10, 20, 19, 24)` couvre 10 × 5 pixels,
colonnes 10–19 et lignes 20–24, et `rectfill(19, 24, 10, 20)` est le même
rectangle. Les coordonnées sont arrondies à l'entier inférieur
(`rectfill(9.8, ...)` commence à la colonne 9) ; `nil` ou une valeur qui
n'est pas un nombre compte pour 0. Deux coins identiques dessinent un pixel.

`color` est un mot empaqueté `0xAABBGGRR`, exactement comme le `color_mult`
de `spr()` : un littéral (`0xFF0000FF`), `rgba()`, `color()`, `hex()`, ou
une variable qui en contient un. Absent ou `nil` : blanc opaque. Une
couleur d'alpha inférieur à 255 se mélange selon le mode de mélange courant
(`ioports.gpu.blending`), que `rect()` laisse tel quel.

```lua
rectfill(0, 0, 639, 359, rgba(0, 0, 64))      -- tout l'écran, bleu foncé
rect(100, 50, 199, 99, 0xFF00FFFF)           -- cadre jaune de 100 x 50
rectfill(px, py, px + 15, py + 15, rgba(255, 0, 0, 128))   -- rouge translucide
```

**Comment il dessine**

Les deux dessinent avec la texture du BIOS (`-1`), région 256 : un pixel
blanc défini par le BIOS, en (469, 29), avec son point d'ancrage dessus.
Rien n'est ajouté à la cartouche. `rectfill()` est **un** seul dessin
agrandi de cette région à l'échelle (largeur, hauteur), teinté par la
couleur de multiplication — exact au pixel pour toute taille (la
correction d'agrandissement du GPU garde l'échantillonnage dans ce seul
pixel). `rect()` fait jusqu'à 4 dessins qui ne se
chevauchent pas (bords haut et bas sur toute la largeur, les côtés entre
eux), si bien qu'un contour translucide n'est pas plus sombre aux coins.

L'état du GPU utilisé par l'appel est rétabli ensuite : texture et région
sélectionnées, couleur de multiplication, échelle de dessin. Un `rect()`
peut se glisser au milieu de code de dessin `ioports.gpu.*` sans le
perturber.

Chaque dessin coûte des pixels GPU comme n'importe quel autre
(`ioports.gpu.pixels`), plus la pénalité d'agrandissement du GPU ; un
`rectfill()` plein écran coûte un écran de pixels.

Une fonction à vous nommée `rect` ou `rectfill` remplace l'intrinsèque,
comme pour tous les intrinsèques. Avec `--#api pico8`, ces deux noms sont
les versions PICO-8 à couleurs de palette (voir [PICO8.md](PICO8.md)) ;
avec `--#api tic80`, `rect(x, y, w, h, color)` / `rectb(...)` sont celles
de TIC-80 (voir [TIC80.md](TIC80.md)).

---

## Entrées : btn() / btnp()

```
btn(id [, player])   -> booléen, actuellement maintenu enfoncé
btnp(id [, player])  -> booléen, vrai uniquement sur l'image où il a été pressé pour la première fois
```

`player` sélectionne une manette 0–3 (`INP_SelectedGamepad`) ; omis ou
`nil` utilise la manette déjà sélectionnée sans écrire le port.

**Identifiants de boutons**

Ordre matériel de Vircon32, pas celui de PICO-8 ni de TIC-80 :

| id | Bouton | IOPort |
|---|---|---|
| 0 | Gauche | `INP_GamepadLeft` |
| 1 | Droite | `INP_GamepadRight` |
| 2 | Haut | `INP_GamepadUp` |
| 3 | Bas | `INP_GamepadDown` |
| 4 | Start | `INP_GamepadButtonStart` |
| 5 | A | `INP_GamepadButtonA` |
| 6 | B | `INP_GamepadButtonB` |
| 7 | X | `INP_GamepadButtonX` |
| 8 | Y | `INP_GamepadButtonY` |
| 9 | L (gâchette gauche) | `INP_GamepadButtonL` |
| 10 | R (gâchette droite) | `INP_GamepadButtonR` |

Un `id` en dehors de 0–10, ou une combinaison non mappée, renvoie `false`
plutôt que de produire une erreur — il n'existe aucun chemin d'erreur au
niveau système d'exploitation disponible sur cette cible (voir
`pcall`/`error`/`assert` dans la liste des fonctionnalités différées du
compilateur).

**btn() : sondage direct**

`__builtin_vircon32_btn` lit le port `INP_Gamepad*` mappé pour la manette
sélectionnée et renvoie `true` lorsque le matériel signale qu'il est
enfoncé (`>= 1`).

**btnp() : détection de front**

`btnp()` a besoin d'un état que le matériel ne suit pas de lui-même : « ce
bouton n'était-il pas enfoncé à l'image précédente, et l'est-il
maintenant ». Cet état vit dans `VIRCON32_BTN_PREV_STATE`, une plage RAM
fixe de 44 mots réservée par le compilateur — un mot par paire (joueur,
bouton), `player * 11 + button_id` — mise à jour à chaque appel de
`btnp()` quel que soit le résultat. Seule une véritable transition
non-enfoncé → enfoncé renvoie `true` ; un bouton maintenu sur plusieurs
images renvoie `true` une fois, puis `false` à chaque image suivante
jusqu'à ce qu'il soit relâché puis pressé à nouveau.

Un `player` hors limites (une valeur explicite en dehors de 0–3) est
borné à 0–3 avant d'être utilisé comme index dans cette table de 44 mots,
plutôt que de laisser calculer une adresse en dehors de celle-ci.

**ioports.inp.inputs — masque d'un mot**

```lua
local mask = ioports.inp.inputs   -- manette actuelle, les 11 boutons en une seule lecture
```

Lit chaque port `INP_Gamepad*` pour la manette actuellement sélectionnée
(`ioports.inp.gamepad`) et les rassemble en un seul nombre de 11 bits en
une fois, au lieu de onze appels séparés à `btn()`. Disposition des bits,
du MSB au LSB :

| Bit | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Bouton | Gauche | Droite | Haut | Bas | Start | A | B | X | Y | L | R |

Chaque bit vaut `1` si ce bouton se lit actuellement comme enfoncé
(`> 0`), la même sémantique de « actuellement maintenu » que `btn()` —
c'est un instantané d'état maintenu, pas déclenché par front ; il n'existe
pas d'équivalent en masque de bits de `btnp()`. Utile pour transmettre
l'entrée d'une image entière en une seule valeur (par exemple dans un
journal de replay/entrée) plutôt que pour la logique de jeu courante
bouton par bouton, où `btn()`/`btnp()` se lisent plus clairement.

**Ce qui n'est délibérément PAS ici**

- Aucune forme de champ de bits/« n'importe quel bouton » (`btn()` sans
  argument) à la manière de PICO-8 — chaque appel nomme un bouton
  spécifique.
- Aucun rapport de stick analogique ou de pression de gâchette ; le
  modèle de manette de Vircon32 est numérique selon la liste d'IOPort
  ci-dessus.
- Il n'existe aucun port de sortie de vibration/rumble sur la console à
  exposer.

Cela correspond au matériel Vircon32 sous-jacent plutôt qu'aux
conventions de PICO-8/TIC-80 ; cette émulation vit entièrement dans les
couches de compatibilité `--#api pico8`/`--#api tic80`, pas ici.

---

## Clavier : key() / keyp() / kbd.\*

```
key([k])                      -> booléen, k enfoncée (sans k : n'importe quelle touche)
keyp([k [, hold, period]])    -> booléen, k enfoncée à cette image (+ répétition)
kbd.read()                    -> caractère tapé suivant (un nombre), ou nil
kbd.event()                   -> événement suivant : +code enfoncée, -code relâchée, ou nil
kbd.port([n])                 -> port de manette du clavier (et le change)
kbd.capslock()                -> booléen, Verr Maj actif
kbd.connected()               -> booléen, quelque chose est branché sur ce port
kbd.clear()                   -- oublie les événements non lus
```

Ces fonctions lisent un clavier complet à travers un périphérique
**v32kbd** : un adaptateur USB de clavier que la console voit comme une
manette ordinaire, dont les 11 commandes transportent des événements de
touches au lieu de boutons (voir le projet v32kbd). Il se branche sur un
port de manette — **le port 1 (le deuxième) par défaut**, ce qui laisse le
port 0 à une manette ordinaire. On le change avec `--keyboard N` sur la
ligne de commande, une indication `--#keyboard N` dans le source, ou
`kbd.port(n)` à l'exécution.

`key()`/`keyp()` suivent ceux de TIC-80 : mêmes noms, mêmes règles, avec
les codes de touche v32kbd. Avec `--#api tic80`, ces deux appels prennent
les codes de TIC-80 (voir [TIC80.md](TIC80.md#input)) ; `kbd.*` fonctionne
avec toutes les API. Une globale à vous nommée `kbd` (une table que vous
affectez) remplace les fonctions `kbd.*` intégrées.

**Codes de touche**

Un code désigne une **touche**, pas un caractère : les touches qui tapent
un caractère utilisent ce caractère sans majuscule, disposition US —
`'a'`–`'z'` (97–122), `'0'`–`'9'` (48–57), espace (32) et
`` ` - = [ ] \ ; ' , . / `` — et les autres :

| Code | Touche | Code | Touche |
|---|---|---|---|
| 1 | Haut | 11 | Ctrl droit |
| 2 | Bas | 12 | Alt gauche (Option) |
| 3 | Gauche | 13 | Entrée |
| 4 | Droite | 14–25 | F1–F12 |
| 5 | Verr Maj | 26 | Alt droit (Option) |
| 6 | Maj gauche | 27 | Échap |
| 7 | Maj droite | 28 | GUI gauche (Commande, Windows) |
| 8 | Retour arrière | 29 | GUI droite |
| 9 | Tab | 127 | Suppr |
| 10 | Ctrl gauche | | |

Les touches du pavé numérique donnent les mêmes codes que leurs
équivalents du clavier principal.

`k` peut aussi être un **littéral de chaîne**, converti en code à la
compilation : un caractère (`"a"`, `"/"`, `" "` ; un caractère majuscule
ou shifté désigne sa touche, donc `"A"` est la touche a et `"!"` la
touche 1), ou un nom — `up` `down` `left` `right` `enter` (`return`) `tab`
`space` `backspace` `delete` (`del`) `escape` (`esc`) `capslock` `lshift`
`rshift` `lctrl` `rctrl` `lalt` `ralt` `lgui` `rgui` `f1`–`f12`, sans
distinction de casse. Quatre noms valent pour les deux côtés : `shift`,
`ctrl`, `alt`, `gui` (`key("shift")` est vrai tant que l'une des deux
touches Maj est enfoncée). Un nom inconnu est une erreur de compilation.
Seuls les littéraux sont convertis : une chaîne rangée dans une variable
n'est pas une touche (`false`).

```lua
function game_loop()
    if key("left")  then x = x - 2 end
    if key("right") then x = x + 2 end
    if keyp("space") then fire() end
    if key("ctrl") and keyp("s") then save() end
    if keyp("down", 20, 4) then menu_next() end   -- se répète tant qu'elle reste enfoncée
end
```

**key([k]), keyp([k [, hold, period]])**

`key(k)` est vrai tant que la touche est enfoncée. `keyp(k)` est vrai à
l'image où elle s'enfonce ; avec `hold` et `period` donnés et ≥ 0, aussi
tant que la touche reste enfoncée, à partir de `hold` images, toutes les
`period` images (`period` 0 : à chaque image) — en comptant les images
après la première, comme `keyp` et `btnp` de TIC-80. Pas de répétition par
défaut. Sans `k`, `key()` signifie « une touche est enfoncée » et `keyp()`
« une touche s'est enfoncée à cette image ». Un code sans touche
correspondante vaut `false`.

**Texte tapé : kbd.read()**

```lua
local text = ""
function game_loop()
    local c = kbd.read()
    while c do
        if c == 8 then                          -- Retour arrière
            text = string.sub(text, 1, -2)
        elseif c >= 32 and c < 127 then
            text = text .. string.char(c)
        end
        c = kbd.read()
    end
    print(0, 0, text .. "_")
end
```

`kbd.read()` renvoie l'**appui** suivant sous la forme du caractère tapé,
avec Maj et Verr Maj appliqués tels qu'ils étaient au moment de l'appui
(`"A"`, `"!"`, `"{"` ... en nombres, selon la police du BIOS), et les
touches sans caractère sous forme de leur code (Entrée 13, Retour arrière 8,
flèches 1–4...). Les relâchements sont ignorés. `nil` quand il n'y a plus
rien.

`kbd.event()` renvoie au contraire tous les événements, appuis et
relâchements, sous forme du code de touche sans Maj : positif pour un
appui, négatif pour un relâchement (`-97` : la touche a a été relâchée).
Les deux lisent la même file : utilisez l'une ou l'autre. La file contient
64 événements ; au-delà, les nouveaux sont perdus jusqu'à ce qu'elle soit
lue (`kbd.clear()` la vide ; les touches enfoncées que voit `key()` ne
changent pas).

**kbd.port([n]), kbd.capslock(), kbd.connected()**

`kbd.port(n)` déplace le clavier sur le port de manette `n` (0–3, borné)
et repart de zéro : touches enfoncées, événements en file et Verr Maj sont
oubliés, et l'état actuel du périphérique sert de point de départ. Il
renvoie le port ; `kbd.port()` ne fait que le renvoyer. `kbd.capslock()`
est l'état de Verr Maj, tenu en comptant ses appuis (désactivé au départ).
`kbd.connected()` est vrai quand quelque chose est branché sur le port du
clavier.

**Lire à chaque image**

Le périphérique signale au plus un événement de touche par image et le
garde jusqu'au suivant : il faut donc le lire **à chaque image**, sinon des
événements se perdent. Le compilateur s'en charge quand le programme
utilise le clavier :

- chaque appel à `key`/`keyp`/`kbd.*` lit le périphérique (une fois par
  image) ;
- les boucles de `game_loop()` et de `TIC()` (TIC-80) le lisent avant
  chaque image ;
- `system.wait()` et `ioports.gpu.sync()` le lisent avant leur `WAIT` (ce
  qui arrive alors compte pour l'image suivante, donc `keyp()` le voit
  encore).

Une boucle `main()` qui attend avec `system.wait()` ne perd donc rien, même
si elle ne regarde le clavier que de temps en temps. Un
`__rawasm__("WAIT")` nu saute cette lecture. Rien de tout cela n'est
présent dans un programme qui n'utilise pas le clavier.

**Le port de manette**

Le port du clavier est lu sans perturber la manette sélectionnée par le
programme : `btn()`, `btnp()` et `ioports.inp.*` continuent de lire la
manette qu'ils lisaient. Ne lisez pas le port du clavier avec `btn()` : ses
« boutons » sont des bits du code de touche.

La manette sélectionnée est mémorisée par l'environnement d'exécution
(`V32IO_GAMEPAD`) au lieu d'être relue dans `INP_SelectedGamepad` : les
émulateurs Vircon32 renvoient une valeur erronée quand on lit ce port. Les
lectures de `ioports.inp.gamepad` donnent elles aussi la valeur mémorisée.
Une écriture du port par `__rawasm__` contourne ce mécanisme.

---

## Tilemap : tilemap.\*

```
tilemap.get(NAME, x, y)        -> nombre ou nil (hors limites)
tilemap.set(NAME, x, y, v)     -> v (une écriture hors limites est un no-op silencieux)
tilemap.render(NAME, sx, sy, w, h, x, y, tile_w, tile_h [, skip_id])
```

`NAME` est toujours un identifiant nu déclaré par `--#tilemap`, résolu
entièrement à la compilation — jamais une valeur d'exécution, la même
restriction (et la même raison) que les noms `--#sound`/`--#texture` :
il n'y a rien de sensé contre quoi un nom calculé dynamiquement pourrait
se résoudre, puisque tout l'intérêt est que le compilateur connaisse la
largeur/hauteur et l'emplacement en ROM de la tilemap par son nom avant
que le moindre code ne s'exécute.

Contrairement à `--#texture`/`--#sound`, une tilemap n'est **pas** une
ressource cart-XML — pas d'entrée `<textures>`/`<sounds>`, pas
d'identifiant de ressource intégré dans le code généré. Ses données sont
incrustées sous forme de valeurs littérales directement dans le programme
assemblé.

**--#tilemap NOM "fichier" et le format CSV**

```lua
--#tilemap LEVEL1 "level1.csv"
```

Le fichier est du texte brut : des lignes d'identifiants de tuiles
séparés par des virgules, une ligne par rangée. Le nombre de lignes
devient la hauteur de la tilemap ; le nombre de valeurs de la première
ligne devient sa largeur, et chaque autre ligne doit correspondre
exactement à ce nombre, sinon c'est une erreur de compilation — une carte
irrégulière lisant silencieusement des données aléatoires au-delà d'une
ligne courte est pire que de refuser de compiler. Un identifiant de tuile
n'est qu'un nombre ; il n'a pas de signification requise, mais la
signification naturelle (et celle que suppose `tilemap.render()`) est un
identifiant de région GPU, prêt à être transmis à `spr()`.

Ce format est délibérément assez simple pour que la sortie **Export
As... CSV** (par calque) de Tiled puisse être utilisée directement sans
étape de conversion — aucune analyse TMX/TSX nulle part dans ce
compilateur.

**tilemap.get() / tilemap.set()**

```lua
local id = tilemap.get(LEVEL1, 4, 2)   -- tuile en colonne 4, ligne 2
tilemap.set(LEVEL1, 4, 2, 99)          -- l'écraser
```

Les deux sont indexés à partir de 0, `(x, y)` = `(colonne, ligne)`.
`tilemap.get()` hors limites (n'importe quel axe, n'importe quelle
direction) renvoie `nil`, comme lire au-delà de la fin d'une table Lua.
`tilemap.set()` hors limites est un no-op silencieux — il n'y a pas de
valeur sensée à renvoyer pour « vous avez essayé d'écrire nulle part »,
donc elle décline simplement, reflétant la façon dont le `mset()` de la
couche de compatibilité TIC-80 traite déjà une écriture hors plage.

Les valeurs sont stockées et renvoyées comme de simples nombres **sans
bornage** — contrairement au `mset()` de la couche TIC-80, qui borne à
0–255 parce que les identifiants de sprites de TIC-80 ont la taille d'un
octet. Une valeur de tuile ici est simplement ce que le code appelant
veut qu'elle signifie, typiquement un identifiant de région GPU, qui peut
largement dépasser 255.

**Promotion paresseuse de la ROM vers la RAM**

Une tilemap commence sa vie en lecture seule, se trouvant là où le
compilateur a placé ses données dans l'image du programme —
`tilemap.get()` avant toute écriture lit directement depuis là, sans coût
de RAM. Le **premier** `tilemap.set()` contre une tilemap donnée la
promeut : alloue une copie privée en RAM et copie chaque cellule, et ce
n'est qu'après cela que la tilemap devient modifiable. Toute lecture ou
écriture vers une tilemap *différente* qui n'a pas été promue n'est pas
affectée — la promotion est suivie par tilemap, pas globalement. Un
deuxième `tilemap.set()` ultérieur sur une tilemap déjà promue écrit
directement, sans recopier ni perturber les écritures antérieures.

**tilemap.render()**

```lua
tilemap.render(LEVEL1, sx, sy, w, h, x, y, tile_w, tile_h)
tilemap.render(LEVEL1, sx, sy, w, h, x, y, tile_w, tile_h, skip_id)
```

Dessine une région de `w` par `h` cellules, en commençant à la cellule de
tilemap `(sx, sy)`, vers l'écran en commençant au pixel `(x, y)`,
espacées de `tile_w`/`tile_h` pixels par cellule — un appel
`spr(tile_value, screen_x, screen_y)` par cellule visible, en lecture
seule (ne promeut jamais). `sx`/`sy` sont bornés à
`0 .. max(0, dimension - w_ou_h)`, la même philosophie de bornage que
celle qu'utilise déjà le `map()` de la couche de compatibilité TIC-80,
de sorte qu'une position de défilement puisse être poussée au-delà du
véritable bord de la carte sans dessiner de données aléatoires ni exiger
que l'appelant la borne d'abord.

`tile_w`/`tile_h` sont **obligatoires**, contrairement au `map()` de
TIC-80, qui suppose une grille fixe de 8×8 — cette API n'a aucune
supposition équivalente sur laquelle se rabattre, puisque les régions GPU
peuvent être de n'importe quelle taille. Elles ne contrôlent que
l'*espacement* en pixels entre les cellules dessinées ; `render()` dessine
chaque région à sa propre taille native quels que soient `tile_w`/
`tile_h`, donc une région plus étroite ou plus courte que le pas se cale
contre un bord de sa cellule plutôt que d'être étirée pour la remplir.

`skip_id` (optionnel) — une cellule dont la valeur est égale à `skip_id`
ne reçoit aucun appel `spr()` du tout, utile pour une carte éparse où la
plupart des cellules signifient « rien ici ». C'est un mécanisme plus
grossier que la transparence par colorkey du `map()` de TIC-80 (qui mélange
par pixel) ; les régions natives portent déjà un véritable canal alpha,
donc le besoin courant est simplement « ne prends pas la peine de dessiner
cette cellule », pas « dessine-la mais fais disparaître certains pixels
par mélange ».

**Le défilement se fait par granularité de cellule, pas au sous-pixel.**
`sx`/`sy` sont des indices de cellule ; il n'y a de décalage de source
fractionnaire nulle part dans la conception, donc déplacer `sx` de 1
déplace le contenu dessiné d'un `tile_w` entier à l'écran — la même
limitation que possède le propre `map()` de TIC-80. Un défilement pixel
fluide nécessiterait de dessiner une rangée/colonne supplémentaire
au-delà de `w`/`h` et de décaler l'origine écran de tout le bloc d'un
reste de pixel de sous-tuile ; c'est une extension réelle et distincte,
non implémentée ici.

**Ce qui n'est délibérément PAS ici**

- Aucun défilement fluide/au sous-pixel — voir ci-dessus.
- Aucune dénomination `mget()`/`mset()`/`map()` — ces noms appartiennent
  à la couche de compatibilité TIC-80 ; ceci est une surface native
  distincte, pas une extension de celle-ci.
- Aucun support multi-calques — un indice `--#tilemap` correspond à une
  grille plate unique. L'empilement de calques est à la charge de
  l'appelant (déclarer plusieurs tilemaps, les afficher dans l'ordre).
- Aucun outil de collision/requête au-delà de `tilemap.get()` lui-même —
  vérifier « est-ce un mur » revient simplement à comparer l'identifiant
  de tuile renvoyé.

---

## Carte mémoire : memcard.\*

```
memcard.save(value, position)   -> value   (écriture brute, exactement 1 mot)
memcard.save(value)             -> value   (auto-ajout ; voir ci-dessous)
memcard.load(position)          -> value   (lecture brute, exactement 1 mot)
memcard.load()                  -> value   (position 0)
memcard.load_table(position)    -> table ou nil   (voir Tables, ci-dessous)
memcard.title(str)              -> nil     (définit le titre de 20 mots)

memcard[position]                  == memcard.load(position)
memcard[position] = value          == memcard.save(value, position)
```

La carte mémoire est un véritable périphérique matériel Vircon32 : une
plage de stockage fixe et persistante à l'adresse physique `0x30000000`,
entièrement séparée de la ROM de la cartouche et de la RAM de Vircon32.
Contrairement à la RAM, elle survit à un cycle d'alimentation — c'est le
dispositif de sauvegarde de partie de la console.

**Cette VM est adressée par mot dans son intégralité**, et la carte
mémoire suit la même convention : une adresse (et une `position`) avance
par mots entiers de 4 octets, pas par octets individuels. Cela correspond
à la façon dont cette VM stocke déjà les chaînes Lua en interne — un mot
par caractère (voir `string.len()`) — plutôt qu'une représentation
compressée par octet.

**memcard.save() / memcard.load()**

Il existe deux formes distinctes, choisies selon qu'une `position` est
donnée ou non :

**Avec une `position` explicite** — la primitive de bas niveau. Écrit (ou
lit) exactement un mot brut à `position`, sans aucune forme de
comptabilité. `position 0` est le premier mot de la région de données ;
voir **Disposition des adresses** ci-dessous
pour la plage complète, y compris comment les positions négatives
atteignent le titre. Vous êtes entièrement responsable de savoir ce que
vous mettez où — écrire deux fois la même position l'écrase simplement.

```lua
memcard.save(1234, 0)     -- mot 0 : nombre brut
memcard.save(true, 1)     -- mot 1 : booléen brut
local hi = memcard.load(0)  -- 1234
```

**Sans aucune `position`** — `memcard.save(value)` s'auto-ajoute via un
curseur persistant stocké *sur la carte elle-même* (pas en RAM), de sorte
que des sauvegardes répétées sans position continuent d'étendre un
journal à travers de nombreuses sessions de jeu au lieu d'écraser le mot 0
à chaque exécution. Cette forme est consciente du type : sauvegarder une
véritable chaîne Lua écrit son contenu complet (étiqueté et préfixé par
sa longueur, voir **Étiquettes de type**),
pas seulement un pointeur brut.

```lua
memcard.save("high score run")   -- ajouté au curseur actuel
memcard.save(9001)               -- ajouté juste après
```

Le curseur lui-même — « combien de mots ont été auto-ajoutés jusqu'ici »
— est lisible à tout moment sous la forme `memcard.load(-1)` /
`memcard[-1]` ; il n'existe pas de fonction de comptage séparée.

`memcard.load()` sans `position` lit toujours le mot 0 — elle ne suit
**pas** le curseur d'auto-ajout comme le fait `memcard.save()`. Relire une
entrée écrite par la forme auto-ajoutée signifie lire vous-même son mot
d'étiquette à une position connue (voir **Étiquettes de type**),
ou simplement savoir ce que vous y avez écrit.

**memcard[position]**

`memcard[position]` et `memcard[position] = value` sont des raccourcis
pour la forme à position explicite de `load`/`save` ci-dessus — jamais
pour la forme auto-ajoutée, puisque la syntaxe de crochets de Lua n'a
aucun moyen d'exprimer « pas d'index ».

```lua
memcard[0] = 1234
local hi = memcard[0]        -- 1234
local cursor = memcard[-1]    -- lit le curseur d'auto-ajout
```

**memcard.title(str) -> nil**

Définit le titre de la carte mémoire — jusqu'à 20 caractères, un mot par
caractère, correspondant à la représentation interne des chaînes de cette
VM. Les chaînes plus longues sont tronquées ; les plus courtes sont
complétées par des zéros. Ceci est indépendant de tout indice de
cartouche `--#title`, qui nomme la *cartouche*, pas les *données de
sauvegarde* — une seule cartouche peut avoir de nombreuses cartes mémoire
en circulation, chacune avec son propre titre.

```lua
memcard.title("My Save File")
```

**Tables : memcard.save() / memcard.load_table()**

`memcard.save(a_table)` — la forme auto-ajoutée sans position
**uniquement** — écrit un **volcage brut** du contenu de la table : un
parcours direct de son stockage interne en compartiments de hachage
(hash buckets), de la même manière que l'on ferait `fwrite()` d'une
structure vers un fichier en C. Ce n'est pas un sérialiseur récursif
général.

```lua
local highscores = { alice = 500, bob = 350, carol = 900 }
memcard.save(highscores)

local restored = memcard.load_table(0)
print(10, 10, restored.alice)   -- 500
```

`memcard.save(a_table, position)` (la forme à **position explicite**)
n'est affectée par rien de tout cela — elle écrit toujours un unique mot
de pointeur brut, exactement comme sauvegarder une table de cette façon
l'a toujours fait. Le format de volcage de table ci-dessous est
exclusivement une fonctionnalité de la forme auto-ajoutée sans position.

**Pourquoi « le côté hachage » et pas un tableau** : l'implémentation des
tables de ce compilateur dispose en principe d'un chemin rapide pour la
partie tableau, mais son chemin de réallocation est actuellement un stub
non implémenté — la capacité ne dépasse jamais 0, donc **chaque** table,
qu'elle ait la forme d'un tableau (`{1, 2, 3}`) ou non, est déjà stockée
entièrement dans la chaîne de compartiments de hachage. Il n'existe
aujourd'hui aucun « cas tableau » séparé et plus simple à traiter
spécialement ; volcager le côté hachage couvre toutes les tables telles
qu'elles existent réellement en ce moment.

**Ce qui est copié, et ce qui ne l'est pas** : chaque clé et valeur est
écrite exactement telle qu'elle est encapsulée (boxed). Une clé/valeur
nombre, booléen, ou nil survit au cycle aller-retour correctement pour
toujours. Une clé ou valeur qui est elle-même une table, une chaîne, ou
une fonction est écrite comme son pointeur brut — **pas** désencapsulée
récursivement — donc elle n'a de sens que dans la même exécution qui l'a
écrite ; la recharger dans une session future (ou après que la cible du
pointeur ait bougé ou été collectée) est indéfini. C'est la même limite
de sécurité que trace déjà le reste de `memcard.*` (voir
*Note de sécurité*) — un volcage de table ne la
franchit pas, il l'applique simplement par entrée plutôt qu'une seule
fois.

**`memcard.load_table(position)`** reconstruit une table neuve à partir
d'un volcage écrit de cette manière. `position` est **obligatoire** —
contrairement à `memcard.load()`, il n'y a pas de valeur par défaut
sensée « position 0 » pour quelque chose dont la taille en mots n'est
pas connue avant que l'entrée elle-même ne soit lue. Elle valide le mot
d'étiquette avant de faire confiance à quoi que ce soit après lui ; lire
à une position qui ne contient pas un volcage de table renvoie `nil`
plutôt que de mal interpréter des mots non liés comme un nombre de
paires et des clés/valeurs aléatoires.

**Disposition des adresses**

```
0x30000000  +-------------------------------------+  position -24
            |  titre : 20 caractères               |
            |  (memcard.title() écrit ici)         |  position -5
            +-------------------------------------+
            |  réservé (3 mots, inutilisés)        |  position -4 .. -2
            +-------------------------------------+
            |  curseur d'auto-ajout                 |  position -1
0x30000018  +-------------------------------------+  position 0
            |  région de données                   |
            |  (memcard.save()/.load()/[pos])     |
            |  ...                                 |
0x3003FFFF  +-------------------------------------+  dernier mot valide
```

`position` est toujours relative au début de la région de données
(`0x30000018`). Les positions négatives remontent vers le bloc
titre/métadonnées — atteignable, mais seulement en allant délibérément au
négatif. Notez que la région de métadonnées (4 mots, positions -4..-1)
est séparée du bloc titre (20 mots, positions -24..-5) — auparavant, les
métadonnées étaient prélevées sur les *4 derniers mots du titre
lui-même*, plafonnant le titre utilisable à 16 caractères ; les 20 mots
complets sont disponibles maintenant.

| Constante | Valeur | Signification |
|---|---|---|
| `VIRCON32_MEMCARD_BASE` | `0x30000000` | début de la carte ; position `-24` |
| `VIRCON32_MEMCARD_DATA_BASE` | `0x30000018` | position `0` |
| `VIRCON32_MEMCARD_CURSOR_ADDR` | `0x30000017` | le curseur d'auto-ajout ; position `-1` |
| `VIRCON32_MEMCARD_END` | `0x3003FFFF` | dernier mot valide, inclus |

**Étiquettes de type (forme auto-ajoutée uniquement)**

`memcard.save(value)` sans position écrit l'une de trois formes au
curseur, puis avance le curseur du nombre de mots que cette forme a
utilisés :

| Type de valeur | Disposition | Mots utilisés |
|---|---|---|
| Véritable chaîne Lua | `[TAG_STRING][length][char 0][char 1]...` | `2 + length` |
| Table | `[TAG_TABLE][pair_count][key 0][val 0]...` | `2 + 2 * pair_count` |
| Nombre / booléen / nil / fonction | `[TAG_SCALAR][raw value]` | `2` |

`TAG_SCALAR` vaut `0`, `TAG_STRING` vaut `1`, `TAG_TABLE` vaut `2`. Une
fonction sauvegardée de cette manière est stockée comme son pointeur
encapsulé brut sous `TAG_SCALAR` — voir la note de sécurité ci-dessous,
ce n'est pas une sérialisation générale.

La forme à `position` explicite (`memcard.save(value, position)` /
`memcard[position] = value`) n'écrit jamais d'étiquette — c'est toujours
exactement un mot brut, quel que soit le type de valeur. Cela inclut les
tables : une table sauvegardée avec une position explicite est un unique
mot de pointeur brut, pas un volcage — voir
**Tables** ci-dessus.

*Note de sécurité*

Un nombre, booléen, ou nil survit au cycle aller-retour correctement pour
toujours — ce motif de bits signifie la même chose à n'importe quelle
exécution. Une véritable chaîne ou table Lua sauvegardée via la forme
auto-ajoutée survit également correctement au cycle aller-retour — les
caractères réels d'une chaîne sont copiés, et les paires clé/valeur
réelles d'une table sont copiées, restaurables avec
`memcard.load_table()`. Une table sauvegardée via la forme à *position
explicite*, une chaîne sauvegardée via la forme à *position explicite*
(qui stocke un pointeur brut, pas le contenu réel de la chaîne), ou une
valeur de fonction — y compris toute valeur de ce type trouvée comme
*clé ou valeur à l'intérieur d'une table sauvegardée*, puisque celles-ci
ne sont pas désencapsulées récursivement — survit au cycle aller-retour
correctement **au sein de la même exécution** — son pointeur reste
valide — mais devient dénuée de sens après qu'un démarrage neuf la relise
depuis une véritable carte mémoire, puisqu'il n'est pas garanti que la
disposition du tas/ROM corresponde d'une exécution à l'autre. Tenez-vous
en aux nombres/booléens/nil (ou aux véritables chaînes/tables de ceux-ci,
via la forme auto-ajoutée) pour tout ce qui est destiné à survivre à un
véritable cycle de sauvegarde/rechargement.

**Ce qui n'est délibérément PAS ici**

- Aucune sérialisation de table *récursive* — un volcage de table copie
  uniquement ses paires clé/valeur directes ; une table imbriquée à
  l'intérieur d'une autre est un pointeur brut, un seul niveau, comme
  partout ailleurs dans `memcard.*`.
- La valeur par défaut sans position de `memcard.load()` ne suit pas le
  curseur d'auto-ajout comme le fait `memcard.save()` — elle lit toujours
  le mot 0.
- Aucun appel de formatage/effacement — une carte se formate en écrivant
  dessus, pas via un appel séparé.

Tant `dget()`/`dset()` de PICO-8 que `pmem()` de TIC-80 sont des API sans
rapport qui utilisent également cette même plage d'adresses physiques
selon leurs propres dispositions — `memcard.*` n'est pas disponible
(erreur de compilation) sous `--#api pico8`/`--#api tic80` afin d'éviter
qu'un programme ne mélange les deux et ne corrompe celle qu'il n'adresse
pas actuellement.

---

## Autres ports d'E/S bruts

Chaque port `ioports.*` vit dans une seule table (`IOPortMap` de
`core.c`), organisée en sept catégories : `tim`, `rng`, `gpu`, `spu`,
`inp`, `car`, `mem`. Les catégories son (`spu`), graphismes (`gpu`,
partiellement — voir **Définir des régions de texture**),
et entrées (`inp`, partiellement — voir [btn()/btnp()](#entrées--btn--btnp))
sont couvertes plus haut là où elles disposent d'un enrobage de plus haut
niveau. Ce qui reste est soit du matériel brut sans aucun enrobage, soit
un enrobage qui ne couvre qu'une partie d'une catégorie. La table complète
des ports se trouve dans l'[Aide-mémoire](#ioports--every-hardware-port).

Une catégorie ou un nom de propriété inconnu est une erreur de
compilation listant les catégories valides, pas un no-op silencieux ni
une lecture de globale non déclarée — voir `validate_ioports_path()`.

**ioports.tim.\* — minuterie brute**

```lua
local d = ioports.tim.date    -- TIM_CurrentDate :  année * 65536 + jour de l'année
local t = ioports.tim.time    -- TIM_CurrentTime :  secondes depuis minuit
local f = ioports.tim.frames  -- TIM_FrameCounter : identique à system.frames()
local c = ioports.tim.cycles  -- TIM_CycleCounter : identique à system.cycles()
```

`ioports.tim.date`/`ioports.tim.time` sont les registres bruts compressés
que `system.date()`/`system.time()` décodent en une chaîne formatée et
trois nombres séparés — utilisez `system.date()`/`system.time()` sauf si
c'est la représentation compressée elle-même qui est nécessaire (par
exemple, stocker un mot dans une carte mémoire plutôt que trois champs
séparés).

**ioports.rng.\* — générateur aléatoire matériel**

```lua
local r = ioports.rng.value   -- RNG_CurrentValue, lecture : la valeur aléatoire suivante
ioports.rng.seed = 12345      -- RNG_CurrentValue, écriture : re-semer le générateur
```

Le même registre matériel sous-jacent dans les deux directions — la
lecture renvoie la valeur aléatoire actuelle (et fait avancer le
générateur), l'écriture le re-sème. C'est le propre générateur aléatoire
matériel de la console, indépendant de `math.random()` (qui est un
générateur pseudo-aléatoire logiciel dans le moteur d'exécution, semé
séparément) — les deux ne partagent pas d'état et ne produiront pas la
même séquence à partir de la même graine.

**ioports.car.\* — informations sur la cartouche**

```lua
local ok   = ioports.car.connected  -- CAR_Connected,        booléen
local size = ioports.car.romsize    -- CAR_ProgramROMSize,   entier
local ntex = ioports.car.numvtex    -- CAR_NumberOfTextures, entier
local nsnd = ioports.car.numvsnd    -- CAR_NumberOfSounds,   entier
```

Introspection en lecture seule de la cartouche actuellement insérée —
la taille de sa ROM de programme en mots, et combien de textures/sons son
cart-XML a déclarés. Puisque la propre cartouche d'un programme en cours
d'exécution est toujours connectée, que `ioports.car.connected` renvoie
`false` n'est pas un cas que le code de cartouche normal doit gérer ; cela
existe pour la complétude de la table de ports plutôt que comme une
condition de branchement pratique ; en réalité, seulement quelque chose
transigé dans le BIOS.

**ioports.mem.connected — présence d'une carte mémoire**

```lua
if ioports.mem.connected then
    memcard.save(highscore)
end
```

`MEM_Connected`, booléen, lecture seule — indique si une carte mémoire
est réellement présente avant que les appels `memcard.*` ne la touchent.
