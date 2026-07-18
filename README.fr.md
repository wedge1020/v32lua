# v32lua : Compilateur Lua Vircon32

[Version anglaise / English version](README.md) | [Version espagnole / Versión en español](README.es.md)

**Architecture cible :** Console Fantasy Vircon32 (32-bit)

**Langage d'implémentation :** C (Flex/Bison + Émetteur sémantique personnalisé)

**Dépôt :** [github.com/wedge1020/v32lua](https://www.google.com/search?q=https://github.com/wedge1020/v32lua)

`v32lua` est un compilateur Lua écrit en C qui cible la console fantasy **Vircon32**. Au lieu d'intégrer un interpréteur de bytecode lourd, `v32lua` analyse le code source Lua et le compile directement en assembleur Vircon32 natif, tout en produisant des définitions de cartouche XML.

Bien qu'il ne soit pas encore complet, l'un des objectifs du développement est de faire de `v32lua` un substitut (en aucun cas un remplacement total) au compilateur C Vircon32 dans la pile de développement Vircon32. En gros, vous choisissez votre langage — C ou Lua —, puis une fois compilé, vous obtenez du code assembleur et pouvez poursuivre la compilation sans vous soucier du langage d'implémentation. Par conséquent, des efforts ont été faits pour imiter divers comportements du compilateur C Vircon32 afin de rendre la substitution du compilateur plus transparente.

Conçu à partir de zéro en gardant à l'esprit les contraintes des consoles fantasy rétro, ce compilateur intègre des intrinsèques matérielles sans coût (zero-cost), un [NaN-boxing](doc/NaN_boxing.md) personnalisé, des optimisations peephole algébriques et des outils de développement riches conçus pour faciliter vos projets de développement de jeux Lua.

```
+------------------+     +-------------------+     +------------------+
| Source (.lua)    | --> | Lexer & Parser    | --> | Construction AST |
+------------------+     | (Flex / Bison)    |     +------------------+
                         +-------------------+              |
                                                            v
+------------------+     +-------------------+     +------------------+
| Config Cartouche | <-- | Émetteur Assembleur|<-- | Émetteur Sémant. |
| (.xml)           |     | Vircon32 (.asm)   |     | & Opt. Peephole  |
+------------------+     +-------------------+     +------------------+

```



---

## Interaction avec l'IA

REMARQUE : Il y a eu une utilisation et une interaction intensives avec l'IA tout au long de ce projet. Il convient de faire la distinction avec le « vibe coding », mais la frontière entre l'humain et l'IA est définitivement floue. Au final, les deux en profitent et pourraient compenser les lacunes de l'autre.

Cette initiative n'avait pas pour but premier de développer un compilateur ; elle a commencé comme une tentative honnête de mieux comprendre l'IA et son impact : son rôle et ses inconvénients pour la pensée humaine et l'éducation. Le fait d'avoir choisi le thème d'un compilateur servait simplement à accentuer un point d'intérêt. Ce fut certainement une expérience enrichissante. Si des concepts de base suffisants sur les compilateurs et des connaissances de fond n'avaient pas été connus au départ, l'effort aurait connu beaucoup moins de succès.

---

## 🚀 Fonctionnalités clés et nouveaux développements

### Modèles d'exécution flexibles : `main()` vs. `game_loop()`

Pour s'adapter à différents styles d'architecture de jeu, le compilateur prend en charge deux paradigmes de points d'entrée distincts :

* **Le harnais à cadence automatique (`game_loop`)** : Si votre programme déclare une fonction `game_loop()`, le compilateur génère automatiquement un harnais d'exécution continu. Le processeur appelle `game_loop()`, met l'exécution en pause pour la trame actuelle à l'aide de l'instruction matérielle `WAIT`, et boucle à l'infini. C'est idéal pour les jeux d'arcade standard et les démos. Cela imite le comportement de plusieurs autres consoles fantasy.
* **Contrôle manuel (`main`)** : Si votre programme déclare une fonction `main()`, le contrôle est directement transmis à `__function_main`. Vous prenez le contrôle total du cycle de trame et devez exécuter manuellement de l'assembleur inline ou des instructions d'attente matérielles. Le compilateur suit si une instruction `WAIT` est émise dans `main()` ; si elle est manquante, `v32lua` émet un avertissement sémantique lors de la compilation.
* **Hook d'initialisation** : Dans les deux modèles, si une fonction `init()` est présente, elle est garantie de s'exécuter exactement une fois après les allocations de RAM globale de plus haut niveau et avant que la boucle principale ne commence.

### NaN-Boxing amélioré : Éléments RAM vs. ROM

`v32lua` utilise une architecture d'étiquetage 32 bits qui regroupe les métadonnées de type et les pointeurs de charge utile dans des valeurs unifiées. Les améliorations récentes séparent strictement les **éléments ROM** immuables des **objets de tas RAM** dynamiques pour garantir la sécurité de la mémoire et le référencement de littéraux sans copie (zero-copy) :

| Type de données | Masque Hex / Tag | Description de l'architecture |
| --- | --- | --- |
| **Nil** | `0xFFC00000` | Représentation canonique des valeurs indéfinies/manquantes. |
| **Booléen Faux** | `0xFFC00001` | Valeur fausse (falsy) en court-circuit. |
| **Booléen Vrai** | `0xFFC00002` | Valeur vraie (truthy) en court-circuit. |
| **Chaîne ROM** | `0x7FC00000` | Pointeurs vers des sections de données de chaînes en lecture seule (`__string_%d`) dans la ROM. |
| **Fonction / Closure** | `0xFF800000` | Adresses mémoire de fonctions encapsulées (Bit 31=1, Bit 22=0). |
| **Nombre** | IEEE 754 Float | Valeurs à virgule flottante natives Vircon32 non encapsulées pour des calculs directs. |

### Intrinsèques matérielles étendues et mappage E/S

Les jeux Vircon32 à hautes performances ne peuvent pas se permettre des recherches dans des tables de hachage pour la manipulation matérielle. `v32lua` intercepte des expressions spécifiques de membres de tables et les compile directement en instructions d'E/S matérielles natives :

* **Accès matériel à coût nul** : L'accès à des espaces de noms comme `ioports.gpu.*`, `ioports.spu.*`, `ioports.tim.*` ou `system.*` (par ex., `ioports.gpu.x = 100` ou `system.frames`) contourne complètement les routines de recherche dans les tables. Ils sont compilés directement en opérations de port matériel (telles que `GPU_DrawingPointX` ou `TIM_FrameCounter`).
* **Scrutin consolidé de la manette (Polling) et entrées traditionnelles** : La scrutation des entrées de la manette est optimisée en une seule intrinsèque de variable (`ioports.inp.inputs`). Le compilateur scrute d'`INP_GamepadLeft` à `INP_GamepadButtonR`, rassemble les états des boutons actifs dans un masque d'entiers 32 bits décalés par bits, et le convertit en un flottant Lua dans un seul registre. Les entrées individuelles de la manette sont également disponibles (`ioports.inp.left`, `ioports.inp.A`, etc.) sous forme d'intrinsèques de variables.
* **Chemins rapides intégrés** : Les opérations Lua standards telles que la concaténation de chaînes (`..`), la longueur (`#`) et le moins unaire (`-`) sont mappées directement vers des sous-routines d'exécution optimisées (`__builtin_strcat`, `__builtin_len`, `__builtin_unm`).

### Pipeline du compilateur d'optimisation (`-O1`)

REMARQUE : les optimisations du compilateur sont encore en plein développement. Bien que l'infrastructure ait été mise en place, des tests approfondis restent à faire et risquent fort de casser des choses (et gravement). Seules **l'optimisation peephole** et **l'omission du pointeur de trame** ont été soumises à des tests significatifs, et les deux peuvent actuellement être inopérantes en raison d'autres modifications récentes du compilateur. Il est probablement préférable de ne pas activer les optimisations pour le moment si vous souhaitez obtenir des résultats fonctionnels.

Lorsque l'optimisation est activée via les arguments de ligne de commande (`o_optflag >= 1`), `v32lua` applique des transformations de code en plusieurs étapes :

* **Optimisation Peephole** : Analyse l'assembleur émis pour éliminer les transferts auto-référencés redondants (`MOV R0, R0`) et les rechargements mémoire inutiles (`MOV A, B` immédiatement suivi de `MOV B, A`).
* **Simplification algébrique** : Simplifie les opérations à virgule flottante neutres lors de la compilation. Les expressions telles que `x + 0.0`, `x * 1.0`, `x - 0.0` et `x / 1.0` sont directement simplifiées en `x`. Les expressions pures multipliées par zéro (`x * 0.0`) sont directement optimisées en `0.000000` sans évaluer l'opérande de gauche si elle ne comporte aucun effet de bord.
* **Omission du pointeur de trame (fonctions feuilles)** : Les fonctions qui ne déclarent pas de variables locales, n'acceptent pas de paramètres ou n'empilent pas de trames de pile suppriment entièrement le prologue et l'épilogue standards `PUSH BP` / `MOV BP, SP`, s'exécutant ainsi comme de simples sauts.
* **Élimination du stockage mort et des branches** : Intègre la propagation des constantes et des tables de suivi DSE (`DeadStoreCandidate`, `ConstSymbol`) pour supprimer les branches conditionnelles inaccessibles et les écritures de variables inutilisées.

### Expérience développeur et outils de débogage

* **Rapports d'erreurs ASCII visuels** : Les erreurs lexicales, syntaxiques, sémantiques et internes du compilateur affichent des extraits de code ASCII multilignes mis en évidence, pointant directement vers la ligne fautive dans le fichier source (`yyin`).
* **Mappage source vers assembleur (`-g`)** : Passer l'argument de débogage `-g` génère un fichier `.debug` d'accompagnement aux côtés de l'assembleur généré. Ce fichier associe les décalages relatifs des lignes d'assembleur Vircon32 aux lignes sources Lua d'origine et aux points d'entrée fonctionnels, permettant un débogage étape par étape. Cela devrait être identique à l'option `-g` du compilateur C.
* **Bulles d'assembleur Inline et Brut** : Vous pouvez écrire du code assembleur natif directement dans Lua à l'aide de `__asm__("votre ASM")` (qui capture et restaure en toute sécurité les pointeurs de pile et les registres d'usage général verrouillés `R0` à `R13`) ou `__rawasm__("votre ASM")` pour une exécution non protégée. Les deux modes prennent en charge l'interpolation de chaînes des variables Lua en utilisant la même syntaxe `{var_name}` présente dans le compilateur C (l'assembleur inline fonctionne, l'interpolation nécessite encore d'être testée).

---

## 🛠️ Hints de ressources de cartouche

`v32lua` vous permet d'intégrer les métadonnées de la cartouche Vircon32 directement dans votre code source Lua en utilisant des commentaires de bloc spéciaux. Le compilateur analyse ces indications (hints) pour générer automatiquement la définition de ROM `.xml` du projet et assigner des identifiants de ressources matérielles séquentiels.

Les indications prises en charge sont :

* `--#version "X.Y"` influence le champ de version de la cartouche dans le XML
* `--#title "TITLE"` définit le titre CART
* `--#texture var "path/image.png"` configure une texture en jeu
* `--#sound var "path/sound.wav"` configure un son en jeu (non terminé)

```lua
--#version "1.1"
--#title "Space Grinder: Tech Demo"

-- Enregistrer des textures (associe automatiquement 'bg_space' à l'ID 0, 'spr_ship' à l'ID 1)
--#texture bg_space "assets/background.png"
--#texture spr_ship "assets/player.png"

function init()
    -- Les variables déclarées dans les indications sont accessibles globalement en Lua à l'exécution !
    ioports.gpu.texture = bg_space
end

```



Une fois compilé, `v32lua` produit à la fois le code assembleur compilé `.asm` et un fichier de définition de cartouche XML Vircon32 complet reliant les assets `.vtex` et `.vsnd`. Avec cela, et le traitement adéquat des données PNG et WAV, vous pouvez passer à l'étape `packrom`.

---

## 💻 Démo technique : Programme d'exemple

Voici un exemple complet démontrant les fonctionnalités de `v32lua`, y compris les intrinsèques matérielles et la boucle de jeu à cadence automatique :

```lua
--#title "v32lua Tech Demo"
--#version "1.0"
--#texture tex_logo "logo.png"

x_pos = 160.0
y_pos = 120.0
speed = 2.5

function init()
    -- Définir la couleur d'effacement d'arrière-plan à l'aide de mappages de ports GPU à coût nul
    ioports.gpu.bgcolor = 0xFF003366
    ioports.gpu.texture = tex_logo -- définir la texture
    ioports.gpu.region  = 0 -- définir la région

    -- définir la région
    ioports.gpu.minX    = 0
    ioports.gpu.minY    = 0
    ioports.gpu.maxX    = 100
    ioports.gpu.maxY    = 50
    ioports.gpu.hotX    = 0
    ioports.gpu.hotY    = 0
end

function game_loop()

    -- Mettre à jour l'état en utilisant des calculs à virgule flottante purs
    if ioports.inp.left > 1 then
        x_pos = x_pos - speed
    else if ioports.inp.right > 1 then
        x_pos = x_pos + speed
    end

    -- Dessin matériel direct
    ioports.gpu.x = x_pos
    ioports.gpu.y = y_pos
    ioports.gpu.draw()
    
    -- Accès aux tables et concaténation de chaînes intégrée
    local frame = system.frames
    if frame > 1000 then
        local msg = "Demo Running: Frame " .. frame
        print(msg)
    end
end

```



---

## 📦 Pipeline du compilateur et utilisation

### Flux de compilation

1. **Analyse lexicale et syntaxique** : Flex/Bison analyse la source Lua en un arbre de syntaxe abstraite (AST) typé.
2. **Résolution des symboles et de la portée** : Résout les variables dans les portées lexicales, en mappant les variables globales à des adresses RAM séquentielles commençant à `1` et les variables locales à des positions de trame de pile `[BP - offset]`.
3. **Génération de code et optimisation Peephole** : Émet des instructions en assembleur Vircon32 tout en appliquant les transformations `-O1` et les substitutions d'intrinsèques matérielles.
4. **Assemblage de la cartouche** : Émet le fichier `.asm` final, intègre les bibliothèques d'exécution (runtime), génère la section de données de chaînes en lecture seule et produit la définition de cartouche `.xml`.

### Intégration de la ligne de commande

```bash
# Compiler avec des optimisations et la génération de symboles pour le débogage
$ v32lua -O1 -g -o program.asm program.lua

```



Options disponibles :

* `-O0` : Désactive les optimisations du compilateur (par défaut)
* `-O1` : Active les optimisations peephole, la simplification algébrique et l'omission du pointeur de trame
* `-g` : Génère le fichier texte de mappage de lignes `program.asm.debug`
* `-o` : Spécifie le nom du fichier de sortie assembleur (par défaut sur stdout si omis)
* `-v` : Sortie plus détaillée (verbeuse)
* `-w` : Supprime tous les avertissements du compilateur
* `--version` : Affiche la version du compilateur et les informations sur l'auteur
* `--help`, `-h` : Affiche les instructions d'utilisation de la ligne de commande

### Étapes de compilation

Lorsque `-v` est activé, `v32lua` signale sa progression à travers cinq étapes principales du pipeline :

1. **Étape 1 : Lexer** — Tokenise la source Lua, en supprimant les commentaires standards et en traitant les séquences d'échappement de chaînes (`\n`, `\t`, `\r`, `\\`, `\"`).
2. **Étape 2 : Préprocesseur** — Évalue les indications de cartouche (`--#...`) et les syntaxes de commentaires personnalisées.
3. **Étape 3 : Parser** — Construit un arbre de syntaxe abstraite (AST) complet en utilisant une grammaire Bison LALR(1) avec une précédence stricte des opérateurs (PEMDAS + cœur logique).
4. **Étape 4 : Analyseur sémantique** — Exécute une pré-passe des fonctions pour enregistrer les symboles de fonctions globales, initialiser la portée globale et résoudre les annotations de type.
5. **Étape 5 : Émetteur** — Traverse l'AST pour générer l'assembleur Vircon32, en appliquant l'allocation de registres, les décalages de portée et les optimisations peephole. Enfin, il produit le fichier de configuration XML de la cartouche.

---

## Instructions de compilation et cibles du Makefile

Le dépôt inclut un Makefile à la racine pour gérer la compilation du binaire du compilateur, les tests automatisés, le déploiement et la maintenance du code.

### Instructions de compilation

Pour compiler le binaire principal du compilateur à partir de la source, exécutez la cible par défaut depuis le répertoire racine :

```bash
make

```



### Tableau de référence des cibles du Makefile

| Cible | Description | Actions principales et dépendances |
| --- | --- | --- |
| **`all`** | **Cible par défaut.** Compile l'exécutable principal du compilateur. | Lance le processus de compilation en natif dans le sous-répertoire `src/`. |
| **`clean`** | Utilitaire standard de nettoyage de l'espace de travail. | Supprime récursivement les artefacts de compilation intermédiaires de `src/` et supprime les fichiers générés de `testing/` et `demos/`. |
| **`install`** | Installe le binaire du compilateur sur le système hôte. | Transmet la cible aux scripts d'installation localisés du répertoire `src/`. |
| **`tests`** | Exécute la suite de tests de compilation automatisée. | Dépend explicitement de la compilation préalable du binaire du compilateur (`bin/v32lua`), puis déclenche les routines de test dans `testing/`. |
| **`demos`** | Compile la collection de démos disponibles. | Dépend explicitement de la compilation préalable du binaire du compilateur (`bin/v32lua`), puis compile chaque démo dans `demos/`. |
| **`asmcheck`** | Valide l'exactitude de l'assembleur. | Nécessite la présence de `bin/v32lua`, puis traite les validations d'assembleur via la suite `testing/`. |
| **`monofiles`** | Compile des variantes de fichiers monolithiques simplifiées. | Exécute le flux de création de `monofile` séquentiellement dans à la fois `src/` et `testing/`. |

### Évaluation en court-circuit Truthy et Falsy

En Lua, seuls `nil` et `false` sont évalués à faux dans les expressions conditionnelles ; toute autre valeur (y compris `0` et les chaînes vides) est **vraie (truthy)**. `v32lua` implémente ceci via deux primitives d'émission d'assembleur haute vitesse :

* **`emit_falsy_jump(reg, label)`** : Teste si `reg` correspond à `0xFFC00000` (Nil) ou `0xFFC00001` (False). Si l'une des conditions correspond, l'exécution saute vers le label cible.
* **`emit_truthy_jump(reg, label)`** : Teste par rapport à Nil et False ; si aucun ne correspond, l'exécution saute directement (en court-circuit) vers le label cible.

Lorsque des opérateurs logiques (`and`, `or`) sont évalués, le résultat évalué est laissé intact dans le registre de destination, préservant l'idiome de Lua qui consiste à retourner la valeur réelle de l'opérande plutôt qu'un booléen strict.

## Fonctionnalités du langage Lua prises en charge

`v32lua` implémente un sous-ensemble de Lua, spécialement adapté au développement de jeux sur matériel embarqué.

### Variables et portée

* **Variables globales :** Enregistrées automatiquement en RAM (à partir de l'adresse `1`, l'adresse `0` étant réservée pour le pointeur de tas) et accessibles via des symboles (`[var_name]`, `[func_name]`).
* **Variables locales :** Déclarées avec le mot-clé `local`. Portée lexicale limitée au bloc englobant (`do ... end`, corps de fonctions, boucles ou conditions) et mappées aux décalages de pile (`[BP - offset]`).

Dans le jargon de Lua, les fonctions sont des « citoyens de première classe » (first-class citizens) et sont en réalité des variables. Cela se confirme dans `v32lua`, car toutes deux sont gérées dans le cadre du schéma de NaN-boxing.

### Affectation multiple

Le compilateur prend en charge nativement l'affectation multiple et l'échange de variables sans nécessiter de variables temporaires explicites par l'utilisateur :

```lua
local x, y, z = 10, 20, 30
x, y = y, x -- Synthetise des chaînes de registres temporaires pour échanger les valeurs en toute sécurité

```



### Programmation orientée objet et tables

`v32lua` offre un sucre syntaxique transparent pour les modèles de POO basés sur les tables :

* **Désucrage de la définition de méthode :** Définir une fonction sur une table génère automatiquement un label altéré (mangled) et lie la propriété de pointeur de fonction :

```lua
function Player.move(dx, dy) ... end
-- Se désucre en : Player["move"] = __function_Player_move

```



* **Désucrage d'appel de méthode (opérateur :) :** L'utilisation de l'opérateur deux-points évalue automatiquement l'expression de la table et l'injecte comme paramètre implicite `self` :

```lua
Player:move(5, -2)
-- Se désucre en : Player.move(Player, 5, -2)

```



### Flux de contrôle

* **Boucles :** Les instructions `while <cond> do ... end` sont prises en charge avec une portée de bloc complète.
* **Contrôle de boucle :** Les instructions `break` sautent immédiatement au label de fin de la boucle la plus interne actuelle (suivi via une pile de boucles interne de compilation).
* **Conditions :** Structures `if <cond> then ... elseif <cond> then ... else ... end` avec branchement en court-circuit.

### Opérateurs et expressions

* **Arithmétiques :** `+`, `-`, `*`, `/` (mappés sur les instructions matérielles à virgule flottante Vircon32 `FADD`, `FSUB`, `FMUL`, `FDIV`), et moins unaire (`-` via `__builtin_unm`).
* **Relationnels :** `==`, `~=` (via `__builtin_eq` avec déballage NaN / NaN unboxing), `<`, `>`, `<=`, `>=` (via le matériel `FLT`, `FLE`, `FGT`, `FGE`).
* **Logiques :** `and`, `or`, `not` (avec évaluation en court-circuit).
* **Concaténation de chaînes :** L'opérateur `..` empile automatiquement les opérandes et invoque la sous-routine d'exécution `__builtin_strcat`.
* **Opérateur de longueur :** L'opérateur `#` invoque `__builtin_len` pour résoudre les longueurs des chaînes ou des tables.

### Fonctions et retours à valeurs multiples

Les fonctions peuvent retourner plusieurs valeurs simultanément. La convention d'appel optimise les trois premières expressions retournées en les plaçant directement dans les registres `R0`, `R2` et `R3`. Toutes les valeurs de retour supplémentaires (4ème et au-delà) sont déversées directement dans la trame de pile de l'appelant à `[BP + 2 + arg_count + offset]`.

### Mise en commun des littéraux de chaînes (Pooling)

Tous les littéraux de chaînes déclarés dans le code source (par ex., `"GAME OVER"`) sont collectés pendant la compilation, dédupliqués et émis dans une section de données dédiée à la fin de la ROM (`__string_0: string "GAME OVER"`), évitant ainsi une consommation redondante de ROM.

---

## E/S matérielles et intrinsèques du compilateur

L'une des fonctionnalités les plus puissantes de `v32lua` est son **moteur d'interception d'intrinsèques statique**. Lorsque le compilateur rencontre des accès aux tables ou des appels de fonctions correspondant à des chemins système spécifiques (par ex., `ioports.gpu.clear()`), il **contourne complètement les recherches dynamiques dans les tables** et émet des instructions directes d'E/S matérielles Vircon32 (`IN`, `OUT`).

### Typage automatique (Casting) à travers les frontières d'E/S

Parce que les variables Lua sont stockées sous forme de flottants IEEE 754 en NaN-boxing alors que les ports matériels Vircon32 attendent des entiers 32 bits ou des booléens, `v32lua` injecte automatiquement des instructions de conversion matérielles lors des lectures et écritures de ports :

* **`CFI` (Cast Float to Integer) :** Émis automatiquement lors de l'écriture de valeurs numériques dans les ports d'entiers GPU/Entrée.
* **`CFB` (Cast Float to Boolean) :** Émis lors de l'écriture de drapeaux booléens dans les registres matériels.
* **`CIF` (Cast Integer to Float) :** Émis immédiatement après l'exécution d'une instruction `IN` à partir de ports matériels entiers, garantissant que la valeur est immédiatement utilisable comme un nombre Lua.

---

### Tableau de référence complet des intrinsèques

#### Contrôle GPU et Dessin (`ioports.gpu.*`)

| Chemin Lua / Intrinsèque | Port Vircon32 / Commande | Accès | Description et comportement |
| --- | --- | --- | --- |
| **`ioports.gpu.texture`** | `GPU_SelectedTexture` | Lecture / Écriture | Définit ou lit l'ID de texture actif utilisé pour les opérations de dessin. |
| **`ioports.gpu.region`** | `GPU_SelectedRegion` | Lecture / Écriture | Sélectionne la sous-région de la texture (trame de sprite) à rendre. |
| **`ioports.gpu.x`** | `GPU_DrawingPointX` | Lecture / Écriture | Coordonnée X de l'écran pour le positionnement du dessin. |
| **`ioports.gpu.y`** | `GPU_DrawingPointY` | Lecture / Écriture | Coordonnée Y de l'écran pour le positionnement du dessin. |
| **`ioports.gpu.minX`** | `GPU_RegionMinX` | Lecture / Écriture | Définit la limite de pixels gauche de la région de texture active. |
| **`ioports.gpu.minY`** | `GPU_RegionMinY` | Lecture / Écriture | Définit la limite de pixels supérieure de la région de texture active. |
| **`ioports.gpu.maxX`** | `GPU_RegionMaxX` | Lecture / Écriture | Définit la limite de pixels droite de la région de texture active. |
| **`ioports.gpu.maxY`** | `GPU_RegionMaxY` | Lecture / Écriture | Définit la limite de pixels inférieure de la région de texture active. |
| **`ioports.gpu.hotX`** | `GPU_RegionHotSpotX` | Lecture / Écriture | Définit l'origine de dessin X (hotspot) par rapport à la région du sprite. |
| **`ioports.gpu.hotY`** | `GPU_RegionHotSpotY` | Lecture / Écriture | Définit l'origine de dessin Y (hotspot) par rapport à la région du sprite. |
| **`ioports.gpu.draw([mode])`** | `GPU_Command` | Appel de fonction | Exécute une commande de dessin matérielle. Accepte un mode sous forme de chaîne en option : `"zoom"` (`GPUCommand_DrawRegionZoomed`), `"rotate"` (`GPUCommand_DrawRegionRotated`), `"rotozoom"` (`GPUCommand_DrawRegionRotozoomed`) ou par défaut (`GPUCommand_DrawRegion`). |
| **`ioports.gpu.clear([color])`** | `GPU_ClearColor` + `GPU_Command` | Appel de fonction | Définit la couleur d'effacement et nettoie l'écran (`GPUCommand_ClearScreen`). Prend en charge des chaînes de couleurs prédéfinies : `"black"` (`0x000000FF`), `"white"` (`0xFFFFFFFF`), `"blue"` (`0x0000FFFF`), `"red"` (`0xFF0000FF`), `"green"` (`0x00FF00FF`) ou des valeurs hexadécimales numériques. |

#### Manette et Entrées (`ioports.inp.*`)

| Chemin Lua / Intrinsèque | Port Vircon32 / Commande | Accès | Description et comportement |
| --- | --- | --- | --- |
| **`ioports.inp.gamepad`** | `INP_SelectedGamepad` | Lecture / Écriture | Sélectionne l'index de la manette active (`0` à `3`) pour la scrutation (polling) des entrées. |
| **`ioports.inp.status`** | `INP_GamepadConnected` | Lecture seule | Retourne `1` si la manette sélectionnée est connectée, `0` sinon. |
| **`ioports.inp.left`** | `INP_GamepadLeft` | Lecture seule | État directionnel Gauche de la croix directionnelle (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.right`** | `INP_GamepadRight` | Lecture seule | État directionnel Droite de la croix directionnelle (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.up`** | `INP_GamepadUp` | Lecture seule | État directionnel Haut de la croix directionnelle (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.down`** | `INP_GamepadDown` | Lecture seule | État directionnel Bas de la croix directionnelle (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.start`** | `INP_GamepadButtonStart` | Lecture seule | État du bouton Start (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.A`** | `INP_GamepadButtonA` | Lecture seule | État du bouton d'action A (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.B`** | `INP_GamepadButtonB` | Lecture seule | État du bouton d'action B (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.X`** | `INP_GamepadButtonX` | Lecture seule | État du bouton d'action X (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.Y`** | `INP_GamepadButtonY` | Lecture seule | État du bouton d'action Y (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.L`** | `INP_GamepadButtonL` | Lecture seule | État de la gâchette supérieure gauche (L) (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.R`** | `INP_GamepadButtonR` | Lecture seule | État de la gâchette supérieure droite (R) (`> 0` enfoncé, `< 0` relâché). |
| **`ioports.inp.inputs`** | *Sous-routine d'action personnalisée* | Lecture seule | **Intrinsèque de rassemblement :** Exécute une séquence de scrutation multi-port rapide sur l'ensemble des 11 boutons/axes de la manette, décalant et combinant leurs états booléens en un seul masque d'entiers 32 bits avant la conversion en flottant (`CIF`). Extrêmement efficace pour les instantanés d'états de boutons ! |

#### Utilitaires Système et d'Exécution

| Chemin Lua / Intrinsèque | Instruction Vircon32 | Accès | Description et comportement |
| --- | --- | --- | --- |
| **`system.halt()`** | `HLT` | Appel de fonction | Émet l'instruction matérielle `HLT`, terminant immédiatement l'exécution du CPU ou gelant la trame jusqu'à la prochaine interruption/cycle de trame. |
| **`system.wait()`** | `WAIT` | Appel de fonction | Émet l'instruction matérielle `WAIT`, mettant l'exécution en pause jusqu'à la prochaine interruption/cycle de trame. |
| **`print(x, y, ...)`** | `__builtin_tostring` + `__builtin_print` | Appel de fonction | Convertit les arguments en représentation textuelle via des sous-routines de conversion d'exécution et les affiche dans le terminal de débogage de la console. Les deux premiers paramètres sont les positions X et Y sur l'écran, en pixels. |

---

## Assembleur Inline (`__asm__` et `__rawasm__`)

Pour les boucles internes critiques en termes de performances ou la manipulation avancée du matériel Vircon32, `v32lua` permet l'injection directe d'assembleur inline.

### Assembleur Inline standard (`__asm__`)

La directive `__asm__` permet d'intégrer des chaînes d'assembleur Vircon32 brutes directement dans les fonctions Lua. Crucialement, elle prend en charge **l'interpolation de variables**, permettant un pontage transparent entre les symboles de portée Lua et les registres d'assembleur :

```lua
local speed = 5.0
__asm__( "MOV R0, {speed}\n" ..
         "FADD R0, 1.5\n" ..
         "MOV {speed}, R0" )

```



* **Comment ça marche :** Tout identifiant entouré d'accolades (par ex., `{speed}`) est résolu dynamiquement par `emit_interpolated_asm` lors de la compilation. Si `speed` est une variable locale au décalage de pile 1, `{speed}` est automatiquement remplacé par `[BP - 1]`. S'il s'agit d'une variable globale, elle est résolue en `[var_speed]`.
* Chaque ligne d'assembleur interpolé est transmise au moteur de formatage du compilateur, garantissant une indentation et un alignement des commentaires cohérents dans le fichier `.asm` de sortie.
* Cet assembleur inline standard applique quelques garde-fous et protections légers, sous la forme d'une sauvegarde des registres existants utilisés ainsi que de la pile. Bien que cela n'empêche pas les problèmes, cela peut aider à en atténuer certains causés par accident. À noter que toutes les modifications de registres effectuées ici seront perdues en dehors de la « bulle » inline.

### Assembleur Brut (`__rawasm__`)

La directive `__rawasm__` produit la chaîne littérale directement dans le flux d'assembleur sans appliquer de sécurités. Cela peut être assez dangereux et ne devrait être utilisé que par les utilisateurs d'assembleur les plus avertis et expérimentés.

---

## 🧠 Tableau de référence de la carte mémoire

| Plage d'adresses RAM | Désignation | Utilisation |
| --- | --- | --- |
| `0` | `heap_pointer` | Stocke l'adresse de départ dynamique pour les allocations de tables à l'exécution. |
| `1` à `N` | RAM Globale | Emplacements alloués séquentiellement pour les variables globales Lua et les ID de ressources. |
| `N + 1`+ | Tas Dynamique | Mémoire d'exécution gérée par `__builtin_table_new` et les allocateurs de chaînes. |
| Sommet de la pile (`SP`) | Pile d'appels | Enregistrements d'activation de fonctions, variables locales et états de registres sauvegardés. |

---

## Particularités et hypothèses du compilateur

Bien que `v32lua` tente d'être un compilateur Lua fonctionnel, il est loin d'être une implémentation de la langue entièrement conforme aux spécifications. Par exemple, il n'y a ni machine virtuelle de bytecode, ni interpréteur.

De plus, il existe quelques divergences explicites par rapport à une implémentation standard du langage pour mieux s'adapter à l'environnement autonome (freestanding) de la Vircon32 :

* `print()` requiert, comme ses deux premiers paramètres, les positions `x` et `y` sur l'écran.
* Les instructions `return` isolées ne fonctionnent pas (elles généreront une erreur de syntaxe). Fournissez-lui une valeur (`nil`, 0, etc.) pour qu'elle soit valide.
* L'exécution du programme DOIT résider dans une fonction. Bien que vous puissiez déclarer des fonctions, vous devez utiliser l'un des points de départ désignés pour initier la chaîne d'exécution (sous la forme de `init()`, `game_loop()` ou `main()`). L'absence d'une fonction `main()` ou `game_loop()` entraînera une erreur. De plus, `game_loop()` émettra automatiquement un `WAIT` avant de s'appeler à nouveau, ce qui en fait l'emplacement naturel pour votre boucle de jeu. Cela a été conçu pour être similaire à d'autres consoles fantasy (comme la fonction `TIC()` dans la TIC-80, qui est également requise).

Clairement, cet effort vise à créer un outil de développement sur Vircon32, et non à être une implémentation Lua parfaitement conforme. Des efforts seront faits pour s'en rapprocher autant que possible et faisable, sans sacrifier de performances significatives ni s'éloigner de l'objectif initial de l'outil.
