# Media slots

Drop files here with these exact names and the site swaps them in automatically,
replacing the hand-drawn line-art placeholder. Anything missing keeps its illustration.

| File | Slot | Where it appears |
|---|---|---|
| `hero-raw.jpg` | `HERO_IMAGE_RAW` | Left side of the hero drag-reveal (raw shea nuts / kernels) |
| `hero-jar.jpg` | `HERO_IMAGE_JAR` | Poster frame for the hero video, and the fallback if the clip cannot play |
| `story.mp4` | `HERO_VIDEO` | Plays on the refined half of the hero. Currently the only clip we have |
| `story.jpg` | `STORY_IMAGE` | Brand story section, beside the founder's note. Upload as `.jpg`, not `.jpeg` |
| `product.jpg` | `PRODUCT_IMAGE` | The Jar section, replacing the illustrated jars. Most important slot. |
| `scents.jpg` | Scent range | The Blends section. The frame stays hidden until this file exists, so the section reads fine without it. |
| `texture.jpg` | `TEXTURE_IMAGE` (optional) | Not wired by default. See the `SLOTS` object at the bottom of `index.html` to place it. |

Notes

- The hero is full bleed and crops to fill, so keep the subject away from the edges. Every other frame now takes the photograph's own proportions, so nothing is cut off.
- Upload JPEGs rather than PNGs. The four PNGs first uploaded came to 25MB between them; the same pictures as JPEG are 1.06MB with no visible difference.
- Alt text lives in the `SLOTS` object in `index.html`. Update it to describe the real photograph once you upload one.
- JPEG or WebP both work; rename the file to the `.jpg` name above, or edit the path in `SLOTS`.

## If you use a video for the story slot

`assets/story.mp4` replaces both the illustration and `story.jpg`. It plays
muted, loops, and carries no controls, so treat it as moving wallpaper rather
than something anyone will sit and watch. A clip of the whipping, the nuts being
sorted, or hands working the butter is the sort of thing that suits it.

- **Keep it under about 8MB.** GitHub warns above 50MB and refuses above 100MB, but the real limit is your visitor's data. A 15 to 25 second clip at 1080p encodes well under 8MB.
- **MP4, H.264, AAC or no audio at all.** It is muted either way, so silent is fine and smaller.
- **Portrait suits the frame,** which is 4:5 on desktop. Something like 1080 by 1350.
- **Add `story.jpg` too if you can.** When both exist the still becomes the poster, so the frame is never empty while the video loads.

The file is only fetched once the section is nearly on screen, and it pauses
whenever it scrolls out of view. Visitors who ask for reduced motion get the
video with controls and no autoplay.
