# API native de la console de fantaisie Vircon32

Ce document couvre UNIQUEMENT l'API native de Vircon32 — la surface active
lorsque ni le mode de compatibilité `--#api pico8` ni `--#api tic80` n'est
sélectionné. Sous ces modes, `spr()`/`btn()`/etc. sont à la place la propre
API de cette console (voir la documentation de compatibilité PICO-8 /
TIC-80), et les appels ci-dessous ne sont pas disponibles.

Fichiers : `v32lua_sound_intrinsics.c`, `v32lua_sound_namespaces.c`,
`v32lua_spu_cmd_intrinsic.c`, `v32lua_ioport_boolean.c`,
`intrinsics_vircon32.c`, `intrinsics_vircon32_memcard.c`,
`runtime_vircon32_sound.s`, `runtime_vircon32_sfx.s`, `runtime_vircon32_spr.s`,
`runtime_vircon32_input.s`, `runtime_vircon32_memcard.s`.

Voir aussi `vircon32-spu-port-ordering.md` — l'ordre d'écriture des ports
SPU est important et chaque émetteur de son ici en dépend.

---

## Table des Matières

- [Son : music.\* / sfx.\*](#son--music--sfx)
  - [Ordre d'écriture des ports SPU](#spu-de-vircon32--lordre-décriture-des-ports)
  - [music.volume() / sfx.volume()](#musicvolumevol--channel--sfxvolumevol--channel)
  - [Pourquoi les noms nus ont disparu](#pourquoi-les-noms-nus-ont-disparu)
  - [Alias à la compilation](#alias-à-la-compilation)
  - [music.playing()](#musicplaying-et-pourquoi-un-drapeau-lua-est-le-mauvais-interrupteur)
  - [Génération de code : repliement hybride](#génération-de-code--repliement-hybride)
- [ioports.spu.cmd() — l'échappatoire brute](#ioportsspucmd--léchappatoire-brute)
- [Ports d'E/S booléens](#ports-des-booléens)
- [Système : system.\*](#système-system)
  - [system.wait() / system.halt()](#systemwait--systemhalt)
  - [system.date() / system.time()](#systemdate--systemtime)
  - [system.frames / system.cycles](#systemframes--systemcycles)
- [Graphismes : spr()](#graphismes--spr)
  - [Répartition à l'exécution](#répartition-à-lexécution-pas-de-repliement-à-la-compilation)
  - [ioports.gpu.clear()](#ioportsgpuclearcolor)
  - [Définir des régions de texture](#définir-des-régions-de-texture)
- [Entrées : btn() / btnp()](#entrées--btn--btnp)
  - [Identifiants de boutons](#identifiants-de-boutons)
  - [btn() : sondage direct](#btn--sondage-direct)
  - [btnp() : détection de front](#btnp--détection-de-front)
  - [ioports.inp.inputs](#ioportsinpinputs--masque-dun-mot)
  - [Ce qui n'est délibérément pas ici](#ce-qui-nest-délibérément-pas-ici)
- [Tilemap : tilemap.\*](#tilemap--tilemap)
  - [--#tilemap et le format CSV](#tilemap-nom-fichier-et-le-format-csv)
  - [tilemap.get() / tilemap.set()](#tilemapget--tilemapset)
  - [Promotion paresseuse de la ROM vers la RAM](#promotion-paresseuse-de-la-rom-vers-la-ram)
  - [tilemap.render()](#tilemaprender)
  - [Ce qui n'est délibérément pas ici](#ce-qui-nest-délibérément-pas-ici-1)
- [Autres ports d'E/S bruts](#autres-ports-des-bruts)
  - [ioports.tim.\* — minuterie brute](#ioportstim--minuterie-brute)
  - [ioports.rng.\* — générateur aléatoire matériel](#ioportsrng--générateur-aléatoire-matériel)
  - [ioports.car.\* — informations sur la cartouche](#ioportscar--informations-sur-la-cartouche)
  - [ioports.mem.connected — présence d'une carte mémoire](#ioportsmemconnected--présence-dune-carte-mémoire)
- [Carte mémoire : memcard.\*](#carte-mémoire--memcard)
  - [memcard.save() / memcard.load()](#memcardsave--memcardload)
  - [memcard[position]](#memcardposition)
  - [memcard.title()](#memcardtitlestr---nil)
  - [Tables : memcard.save() / memcard.load_table()](#tables--memcardsave--memcardload_table)
  - [Disposition des adresses](#disposition-des-adresses)
  - [Étiquettes de type (forme auto-ajoutée uniquement)](#étiquettes-de-type-forme-auto-ajoutée-uniquement)
  - [Ce qui n'est délibérément pas ici](#ce-qui-nest-délibérément-pas-ici-2)

---

# Son : music.\* / sfx.\*

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

## SPU de Vircon32 : l'ordre d'écriture des ports

### La règle

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

### États des canaux et ce que signifie réellement resume

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

### Types de ports

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

## music.volume(VOL [, CHANNEL]) / sfx.volume(VOL [, CHANNEL])

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

### Suivi de possession de canal

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

### Génération de code

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

## Pourquoi les noms nus ont disparu

`play` / `pause` / `resume` / `stop` étaient les quatre identifiants les
plus sujets aux collisions qu'un jeu pouvait vouloir pour lui-même, ce que
l'ancienne garde de contournement `resolve_symbol()` dans le répartiteur
compensait. Ils ont disparu ; les espaces de noms les remplacent, et le
mécanisme d'alias les restaure par choix plutôt que par défaut.

## Alias à la compilation

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

## music.playing() et pourquoi un drapeau Lua est le mauvais interrupteur

`SPU_ChannelState` est un port entier en lecture seule qui renvoie
`channel_stopped` 0x40, `channel_paused` 0x41, `channel_playing` 0x42.
`music.playing(ch)` sélectionne le canal, le lit, et renvoie un véritable
booléen Lua.

Un interrupteur pause/resume construit sur un drapeau Lua se dérègle dès
qu'un son se termine de lui-même : le programme croit toujours qu'il est
en lecture, donc l'appui suivant met en pause un canal déjà arrêté au
lieu de le reprendre. Interroger le matériel ne peut pas se dérégler.

## Génération de code : repliement hybride

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

# ioports.spu.cmd() — l'échappatoire brute

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

# Ports d'E/S booléens

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

# Système : system.\*

```
system.wait()   -> nil   (WAIT jusqu'au prochain signal de nouveau cycle)
system.halt()   -> nil   (HLT -- arrête le CPU)
system.date()   -> chaîne, année, mois, jour
system.time()   -> chaîne, heure, minute, seconde
```

## system.wait() / system.halt()

`system.wait()` se compile directement en `WAIT` — la même instruction
qu'utilise `ioports.gpu.sync()`, et interchangeable avec elle ; toutes
deux attendent simplement le prochain signal de nouveau cycle de la
minuterie. `system.halt()` se compile en `HLT`, arrêtant le CPU purement
et simplement — pour un programme qui a terminé son travail et n'a plus
rien à afficher.

## system.date() / system.time()

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

## system.frames / system.cycles

```lua
local f = system.frames()   -- TIM_FrameCounter -- images depuis la mise sous tension
local c = system.cycles()   -- TIM_CycleCounter -- cycles CPU depuis la mise sous tension
```

Les deux sont des compteurs matériels en lecture seule, monotones depuis
le démarrage — contrairement à `system.date()`/`system.time()`, ceux-ci
ne sont **pas** des horloges murales : ils mesurent le temps d'exécution
propre de la console, pas l'horloge temps réel. `system.frames()` est
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

# Graphismes : spr()

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
| `blend_mode` | `VIRCON32_BLEND_ALPHA` (`0x20`) | voir les modes de fondu ci-dessous |

Un argument peut être **omis** (simplement arrêter de fournir les
arguments suivants) ou passé comme un **`nil` explicite** pour le sauter
et atteindre un argument ultérieur — `spr(id, x, y, nil, nil, 45)` pour
faire pivoter sans toucher à l'échelle — les deux signifient « utiliser la
valeur par défaut ».

Modes de fondu :

| Constante | Valeur |
|---|---|
| `VIRCON32_BLEND_ALPHA` | `0x20` |
| `VIRCON32_BLEND_ADD` | `0x21` |
| `VIRCON32_BLEND_SUBTRACT` | `0x22` |

`spr()` ne renvoie rien (`nil` Lua), ce qui correspond au fait que la
console n'a aucune valeur significative à renvoyer d'un appel de dessin.
Plus de 8 arguments déclenche un avertissement à la compilation ; les
arguments en trop sont ignorés.

## Répartition à l'exécution, pas de repliement à la compilation

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

La valeur par défaut `0xFFFFFFFF` de `color_mult` est transmise via la
convention d'appel comme un flottant Lua, et `4294967295.0` n'est pas
exactement représentable dans un flottant 32 bits — elle est arrondie à
`4294967296.0`. Le moteur d'exécution la convertit via `CFI` (flottant →
motif de bits entier) plutôt que de l'utiliser directement, ce qui
récupère correctement `0xFFFFFFFF` dans tous les cas.

Un `nil` explicitement passé pour un argument optionnel (par exemple
`spr(id, x, y, nil, nil, 45)`) est traité de façon identique à cet
argument étant totalement omis — les deux retombent sur la valeur par
défaut. Un appel situé dans un contexte d'expression
(`local unused = spr(1, 10, 10)`) se voit correctement assigner `nil`,
comme tout autre intrinsèque de ce document.

## ioports.gpu.clear([couleur])

Efface l'écran : écrit `GPU_ClearColor` (si un argument de couleur est
fourni) puis émet `GPUCommand_ClearScreen`. `couleur` accepte soit un
entier RGBA compressé, soit l'une des cinq chaînes de nom prédéfinies —
`"black"`, `"white"`, `"blue"`, `"red"`, `"green"` — résolues à la
compilation lorsqu'il s'agit d'un littéral de chaîne. Omettez l'argument
pour effacer avec ce que `GPU_ClearColor` contient actuellement.

```lua
ioports.gpu.clear("black")
ioports.gpu.clear(0xFF202020)   -- RGBA compressé, pas un nom prédéfini
ioports.gpu.clear()             -- réutilise le dernier ClearColor défini
```

## Définir des régions de texture

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

**`hotX`/`hotY` doivent être définis aux mêmes valeurs que `minX`/`minY`,
pas à `0`.** Ceci a été découvert à la dure lors de la construction de
`tilemap.render()` : une région dont le point chaud (hotspot) est laissé
non défini (ou explicitement mis à zéro) se dessine décalée vers le bas et
vers la droite d'à peu près sa propre valeur `minX`/`minY` — une région
découpée près du coin supérieur gauche de la planche a l'air correcte, ce
qui est exactement ce qui a rendu cela facile à manquer au début, mais
une région découpée plus loin dans la planche dérive d'autant qu'elle a
été découpée loin. Définir `hotX`/`hotY` pour correspondre à
`minX`/`minY` ancre le point de dessin au propre coin supérieur gauche de
la région, ce que suppose chaque exemple de ce document lorsqu'il écrit
`spr(id, x, y, ...)`. Cela doit être fait pour **chaque** région qu'une
cartouche définit — ce n'est pas un réglage global à effectuer une seule
fois.

`GPU_RegionMinX/MinY/MaxX/MaxY/HotSpotX/HotSpotY` sont les ports bruts
derrière `ioports.gpu.minX` etc. — voir la table complète des ports dans
[Autres ports d'E/S bruts](#autres-ports-des-bruts) pour tout le reste
qu'expose `ioports.gpu.*` (point de dessin, échelle, angle, couleur de
multiplication, mélange, et le compteur en lecture seule GPU-occupée
`ioports.gpu.pixels`).

---

# Entrées : btn() / btnp()

```
btn(id [, player])   -> booléen, actuellement maintenu enfoncé
btnp(id [, player])  -> booléen, vrai uniquement sur l'image où il a été pressé pour la première fois
```

`player` sélectionne une manette 0–3 (`INP_SelectedGamepad`) ; omis ou
`nil` utilise la manette déjà sélectionnée sans écrire le port.

## Identifiants de boutons

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

## btn() : sondage direct

`__builtin_vircon32_btn` lit le port `INP_Gamepad*` mappé pour la manette
sélectionnée et renvoie `true` lorsque le matériel signale qu'il est
enfoncé (`>= 1`).

## btnp() : détection de front

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

## ioports.inp.inputs — masque d'un mot

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

## Ce qui n'est délibérément PAS ici

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

# Tilemap : tilemap.\*

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

## --#tilemap NOM "fichier" et le format CSV

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

## tilemap.get() / tilemap.set()

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

## Promotion paresseuse de la ROM vers la RAM

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

## tilemap.render()

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

## Ce qui n'est délibérément PAS ici

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

# Autres ports d'E/S bruts

Chaque port `ioports.*` vit dans une seule table (`IOPortMap` de
`core.c`), organisée en six catégories : `tim`, `rng`, `gpu`, `spu`,
`inp`, `car`, `mem`. Les catégories son (`spu`), graphismes (`gpu`,
partiellement — voir [Définir des régions de texture](#définir-des-régions-de-texture)),
et entrées (`inp`, partiellement — voir [btn()/btnp()](#entrées--btn--btnp))
sont couvertes plus haut là où elles disposent d'un enrobage de plus haut
niveau. Ce qui reste est soit du matériel brut sans aucun enrobage, soit
un enrobage qui ne couvre qu'une partie d'une catégorie.

Une catégorie ou un nom de propriété inconnu est une erreur de
compilation listant les catégories valides, pas un no-op silencieux ni
une lecture de globale non déclarée — voir `validate_ioports_path()`.

## ioports.tim.\* — minuterie brute

```lua
ioports.tim.date     -- TIM_CurrentDate,   lecture seule, entier compressé
ioports.tim.time     -- TIM_CurrentTime,   lecture seule, entier compressé
ioports.tim.frames    -- TIM_FrameCounter, lecture seule -- identique à system.frames()
ioports.tim.cycles    -- TIM_CycleCounter, lecture seule -- identique à system.cycles()
```

`ioports.tim.date`/`ioports.tim.time` sont les registres bruts compressés
que `system.date()`/`system.time()` décodent en une chaîne formatée et
trois nombres séparés — utilisez `system.date()`/`system.time()` sauf si
c'est la représentation compressée elle-même qui est nécessaire (par
exemple, stocker un mot dans une carte mémoire plutôt que trois champs
séparés).

## ioports.rng.\* — générateur aléatoire matériel

```lua
ioports.rng.value            -- RNG_CurrentValue, lecture : la valeur aléatoire actuelle
ioports.rng.seed = 12345      -- RNG_CurrentValue, écriture : re-semer le générateur
```

Le même registre matériel sous-jacent dans les deux directions — la
lecture renvoie la valeur aléatoire actuelle (et fait avancer le
générateur), l'écriture le re-sème. C'est le propre générateur aléatoire
matériel de la console, indépendant de `math.random()` (qui est un
générateur pseudo-aléatoire logiciel dans le moteur d'exécution, semé
séparément) — les deux ne partagent pas d'état et ne produiront pas la
même séquence à partir de la même graine.

## ioports.car.\* — informations sur la cartouche

```lua
ioports.car.connected  -- CAR_Connected,          booléen, lecture seule
ioports.car.romsize    -- CAR_ProgramROMSize,     entier, lecture seule
ioports.car.numvtex    -- CAR_NumberOfTextures,   entier, lecture seule
ioports.car.numvsnd    -- CAR_NumberOfSounds,     entier, lecture seule
```

Introspection en lecture seule de la cartouche actuellement insérée —
la taille de sa ROM de programme en mots, et combien de textures/sons son
cart-XML a déclarés. Puisque la propre cartouche d'un programme en cours
d'exécution est toujours connectée, que `ioports.car.connected` renvoie
`false` n'est pas un cas que le code de cartouche normal doit gérer ; cela
existe pour la complétude de la table de ports plutôt que comme une
condition de branchement pratique ; en réalité, seulement quelque chose
transigé dans le BIOS.

## ioports.mem.connected — présence d'une carte mémoire

```lua
if ioports.mem.connected then
    memcard.save(highscore)
end
```

`MEM_Connected`, booléen, lecture seule — indique si une carte mémoire
est réellement présente avant que les appels `memcard.*` ne la touchent.

---

# Carte mémoire : memcard.\*

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

## memcard.save() / memcard.load()

Il existe deux formes distinctes, choisies selon qu'une `position` est
donnée ou non :

**Avec une `position` explicite** — la primitive de bas niveau. Écrit (ou
lit) exactement un mot brut à `position`, sans aucune forme de
comptabilité. `position 0` est le premier mot de la région de données ;
voir [Disposition des adresses](#disposition-des-adresses) ci-dessous
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
sa longueur, voir [Étiquettes de type](#étiquettes-de-type-forme-auto-ajoutée-uniquement)),
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
d'étiquette à une position connue (voir [Étiquettes de type](#étiquettes-de-type-forme-auto-ajoutée-uniquement)),
ou simplement savoir ce que vous y avez écrit.

## memcard[position]

`memcard[position]` et `memcard[position] = value` sont des raccourcis
pour la forme à position explicite de `load`/`save` ci-dessus — jamais
pour la forme auto-ajoutée, puisque la syntaxe de crochets de Lua n'a
aucun moyen d'exprimer « pas d'index ».

```lua
memcard[0] = 1234
local hi = memcard[0]        -- 1234
memcard[-1]                  -- lit le curseur d'auto-ajout
```

## memcard.title(str) -> nil

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

## Tables : memcard.save() / memcard.load_table()

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
print(restored.alice)   -- 500
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
[Note de sécurité](#note-de-sécurité)) — un volcage de table ne la
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

## Disposition des adresses

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

## Étiquettes de type (forme auto-ajoutée uniquement)

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
[Tables](#tables--memcardsave--memcardload_table) ci-dessus.

### Note de sécurité

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

## Ce qui n'est délibérément PAS ici

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
