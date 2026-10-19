# App icon artwork

Asset: `HamsterLab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
Generated with the built-in imagegen tool on 19 October 2026, inspired by the
user's ink-and-watercolor hamster reference. The illustration replaces the old
procedural gradient icon; the obsolete drawing script was removed to prevent
accidentally restoring that artwork.

The final asset is an opaque 1024 × 1024 RGB PNG. The universal iOS icon entry
lets Xcode produce the required device sizes. Keep the full square image;
iOS applies the icon corner mask. Do not use HEIC for this app icon asset.

To import a new square, opaque PNG, run from the repository root:

```sh
sips --resampleHeightWidth 1024 1024 /path/to/square-icon.png --out \
  ios/hamsterlab/HamsterLab/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Generation prompt:

> Use case: illustration-story.
> Asset type: finished iOS app icon for the children's hamster puzzle game HamsterLab, square 1024x1024, one single image.
> Primary request: a funny hand-drawn golden hamster peeking happily out of a transparent laboratory tube, in expressive pen-and-watercolor children's sketchbook style. Match the spirit of the user's cartoon reference: energetic slightly irregular dark ink outlines, fluffy little fur strokes, enormous cream cheek pouches, orange-gold fur, small round pink inner ears, wonderfully goofy expressive white eyes with small dark pupils, pink nose, open joyful smile, two little front teeth and a pink tongue.
> Composition: tight iconic front view, one hamster only, face fills most of the square, slight playful head tilt. Both small pink hands rest over the lower rim of the tube. A single broad turquoise-tinted glass opening frames the hamster, simple slightly oval sketched ring with a few pale aqua reflections. Ears, paws and whiskers all fit comfortably within the center 82 percent of the canvas; strong immediately recognizable silhouette and readable at 60 pixels. Keep the face large and background uncluttered.
> Style/medium: authentic lively ink drawing with watercolor washes, visibly drawn on clean white paper; confident variable-weight black-brown outlines, small loose hatch marks in the fur; charming funny personality, imperfect organic drawing, like a polished illustration from a humorous children's picture book. Flat illustration with minimal watercolor shading, not a rendered character.
> Palette: warm honey-orange fur, ivory-white cheeks, blush-pink paws and nose, soft aqua glass accents; opaque clean white background all the way to each edge.
> Constraints: full square canvas with no pre-rounded app icon corners, no outer border, no typography, no letters, no watermark, no extra objects, no laboratory stand, no other hamsters. No 3D, no CGI, no glossy plastic, no airbrushed gradients, no emoji or vector geometric clipart look. This is final app artwork, not a mockup, not a contact sheet.
