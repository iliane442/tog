# Kit de cartes

Ce kit reprend les contours ombrés, la lumière chaude et les textures en pixel art des objets de l’inventaire.

## Décors

Ouvre `palette_decors.tscn` dans Godot et copie les nœuds qui t’intéressent dans ta carte. L’origine des sprites se trouve au pied du décor pour faciliter le placement et le tri sur l’axe Y.

| Dossier | Contenu |
| --- | --- |
| `nature` | Chêne, pin, palmier, roncier, fleurs médicinales et rochers moussus |
| `bourg_port` | Maison, cabane de pêche, étal, borne d’amarrage, barque et lanterne |
| `ruines_mine` | Arche, colonne brisée, stèle, filon de cristaux, entrée de mine et monument à l’ancre |

## Sols

Attribue `sols.tres` à la propriété **Tile Set** d’un `TileMapLayer`. La palette propose six tuiles répétables de 64 × 64 px, dans l’ordre herbe, terre battue, sable, pavés, ardoise et planches.

## Génération

Les quatre planches ont été créées avec l’outil ImageGen intégré, à partir d’une planche de référence composée avec les sprites d’inventaire du projet. Les invites ci-dessous sont celles utilisées pour générer les planches.

<details>
<summary>Nature</summary>

```text
Use case: stylized-concept.
Asset type: transparent environment prop atlas for Godot map building.
Input image: the attached sheet of existing Godot inventory icons is a style reference. Match these items' hand-placed pixel clusters, dark colored (never pure black) stepped silhouettes, warm upper-left light and pale specular edges, deep cool contact shading, varied saturated local hues, and material-specific texture. Render as authentic detailed hand-dithered pixel art for a pirate-fantasy adventure. Objects should read clearly at 64–160 game pixels. Render the assets orthographic from a shallow overhead RPG angle: visible tops and generous front faces, parallel straight verticals, front-facing with a little right side visible, the same camera for all assets. No perspective vanishing points, no thick vector contours, no gradients, no glow, no floor discs, no characters, no text.
One landscape production sprite sheet, exactly THREE columns and TWO rows of equal cells, a centered asset in each. Every sprite must fit entirely inside its own cell, with a generous empty margin on all four sides, never touch a neighbor, and never touch the canvas edge. Keep the baselines level within each row. Blank space and inside open cutouts must be genuinely transparent alpha. Clean opaque pixel edges with no white or dark halo. No grid rules, frames, labels, watermarks, decoration between the sprites, or faux transparency. Each asset should have its own unmistakable silhouette.
Top row, left to right: a big windswept leafy oak with knotted brown trunk and mossy roots; a tall blue-green conifer with layered branches and a visible trunk base; a warm tropical palm with long arcing fronds, three coconuts and an elegantly curled trunk.
Bottom row, left to right: a low vivid bramble bush studded with small red berries; a clump of upright medicinal leaves with white blossoms and broad lime-lit leaves; a low cluster of three weathered sparsely mossy blue-gray boulders with green fern leaves peeking from the cracks. Preserve enough visible trunk below the oak and pine foliage for ground anchoring.
```

</details>

<details>
<summary>Bourg et port</summary>

```text
Use case: stylized-concept.
Asset type: transparent village and port prop atlas for Godot map building.
Input image: the attached sheet of existing Godot inventory icons is a style reference. Match these items' hand-placed pixel clusters, dark colored (never pure black) stepped silhouettes, warm upper-left light and pale specular edges, deep cool contact shading, varied saturated local hues, and material-specific texture. Render as authentic detailed hand-dithered pixel art for a pirate-fantasy adventure. Objects should read clearly at 64–160 game pixels. Render the assets orthographic from a shallow overhead RPG angle: visible tops and generous front faces, parallel straight verticals, front-facing with a little right side visible, the same camera for all assets. No perspective vanishing points, no thick vector contours, no gradients, no glow, no floor discs, no characters, no text.
One landscape production sprite sheet, exactly THREE columns and TWO rows of equal cells, a centered asset in each. Every sprite must fit entirely inside its own cell, with a generous empty margin on all four sides, never touch a neighbor, and never touch the canvas edge. Keep the baselines level within each row. Blank space and inside open cutouts must be genuinely transparent alpha. Clean opaque pixel edges with no white or dark halo. No grid rules, frames, labels, watermarks, decoration between the sprites, or faux transparency. Each asset should have its own unmistakable silhouette.
Top row, left to right: a small two-story warm limestone cottage with a burnt red terracotta roof, blue shutters and ground-level wooden door; a compact weathered fishing cabin with a slate navy roof, sea-green board siding and rope hanging on its wall, raised only on short legs; a market stall with rust-red and warm cream striped fabric roof, a wooden counter and a few baskets.
Bottom row, left to right: a weathered port bollard with a distinct coil of hemp rope at its base; a small empty wooden fishing rowboat seen slightly from above, resting on its own hull with two oars inside; a rustic square lantern mounted on a tall dark timber post with a visible base and small warm honey-yellow panes. No dock or pier floor underneath any object.
```

</details>

<details>
<summary>Ruines et mine</summary>

```text
Use case: stylized-concept.
Asset type: transparent ruins and mine prop atlas for Godot map building.
Input image: the attached sheet of existing Godot inventory icons is a style reference. Match these items' hand-placed pixel clusters, dark colored (never pure black) stepped silhouettes, warm upper-left light and pale specular edges, deep cool contact shading, varied saturated local hues, and material-specific texture. Render as authentic detailed hand-dithered pixel art for a pirate-fantasy adventure. Objects should read clearly at 64–160 game pixels. Render the assets orthographic from a shallow overhead RPG angle: visible tops and generous front faces, parallel straight verticals, front-facing with a little right side visible, the same camera for all assets. No perspective vanishing points, no thick vector contours, no gradients, no glow, no floor discs, no characters, no text.
One landscape production sprite sheet, exactly THREE columns and TWO rows of equal cells, a centered asset in each. Every sprite must fit entirely inside its own cell, with a generous empty margin on all four sides, never touch a neighbor, and never touch the canvas edge. Keep the baselines level within each row. Blank space and inside open cutouts must be genuinely transparent alpha. Clean opaque pixel edges with no white or dark halo. No grid rules, frames, labels, watermarks, decoration between the sprites, or faux transparency. Each asset should have its own unmistakable silhouette.
Top row, left to right: an ancient rounded stone archway with chipped slate blocks and a modest fringe of ivy, a visibly open transparent arch aperture; a broken circular stone column with angled fractures and moss in its crevices; a squat carved stone waymarker with an incised geometric wave symbol, standing upright on a small square base.
Bottom row, left to right: a clustered rose-gold and dusty-lilac crystal deposit embedded in jagged dark stone; a walk-in mine entrance formed by a gray-brown rocky mound with a visible timber frame around its deep dark opening; a carved weathered anchor monument on a stone plinth with strands of sea grass. Palette is cool weathered stone, rose-gold ore and rich restrained forest green, inspired by the supplied material reference.
```

</details>

<details>
<summary>Sols</summary>

```text
Use case: stylized-concept.
Asset type: game-ready 2D pixel-art terrain texture swatch atlas for a top-down Godot TileMap.
Input image: supplied game items are a style and color reference only. Match their handcrafted pixel clusters, material readability, warm highlights, cool shaded crevices and rich restrained local palette, adapted to quiet playable floor textures. View is strictly orthographic straight down. Authentic coarse pixel-art treatment with clean stepped shapes and flat clusters, no photography or smooth gradients.
One landscape sheet, exactly THREE columns and TWO rows. In each equal cell draw one large centered PERFECT SQUARE opaque material swatch with straight, clean sides and true transparent padding around all sides. Each swatch should be at least 75 percent of the narrowest cell edge. Keep generous clear gutters. No grid lines or text. Each is an unframed texture, with content continuing across the boundary of the square, no rim, no bevel, no island silhouette, no edge effect, no shadow. Uniform texture density. Each swatch should tile independently across both axes without a visible repeat seam; cover the whole square.
Top row left to right: gentle green short meadow grass with sparse tiny pixel grass streaks; warm tan packed dirt trail with very sparse small pebbles; light warm golden beach sand with subtle small grain clusters. Bottom row left to right: irregular gray-brown village cobblestones with subdued blue-gray joints; cool charcoal blue slate cave ground with small mottled slate streaks and no large rocks; close-set horizontal medium-brown dock boards with staggered joints and subdued fine wood grain. No plants, objects, sparkles or flecks that read as a pickup.
```

</details>

