# Media slots

Drop files here with these exact names and the site swaps them in automatically,
replacing the hand-drawn line-art placeholder. Anything missing keeps its illustration.

| File | Slot | Where it appears |
|---|---|---|
| `hero-raw.jpg` | `HERO_IMAGE_RAW` | Left side of the hero drag-reveal (raw shea nuts / kernels) |
| `hero-jar.jpg` | `HERO_IMAGE_JAR` | Right side of the hero drag-reveal (finished Banini jar) |
| `story.jpg` or `story.mp4` | `STORY_IMAGE` / `STORY_VIDEO` | Brand story section, beside the founder's note. The video wins if both exist and is lazy-loaded. |
| `product.jpg` | `PRODUCT_IMAGE` | The Jar section, replacing the illustrated jars. Most important slot. |
| `scents.jpg` | Scent range | The Blends section. The frame stays hidden until this file exists, so the section reads fine without it. |
| `texture.jpg` | `TEXTURE_IMAGE` (optional) | Not wired by default. See the `SLOTS` object at the bottom of `index.html` to place it. |

Notes

- Hero images are cropped to a 4:3.4 frame, story and product to 4:5 on desktop, so keep the subject centred.
- Alt text lives in the `SLOTS` object in `index.html`. Update it to describe the real photograph once you upload one.
- JPEG or WebP both work; rename the file to the `.jpg` name above, or edit the path in `SLOTS`.
