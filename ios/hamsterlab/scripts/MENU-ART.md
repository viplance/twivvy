# Static menu artwork

Source: `../menu-source.png` — the exact illustration supplied by the user.
Asset: `HamsterLab/Resources/Assets.xcassets/MenuHamsters.imageset/menu-hamsters.heic`.

On 19 October 2026 the generated placeholder was replaced with the supplied
1254 × 1254 image. The full composition and resolution are preserved; only the
encoding changes. The HEIC asset is approximately 146 KiB, compared with about
1.8 MiB for the source PNG. The source stays outside the app target.

Regenerate from the repository root on macOS:

```sh
sips -s format heic -s formatOptions 75 ios/hamsterlab/menu-source.png --out \
  ios/hamsterlab/HamsterLab/Resources/Assets.xcassets/MenuHamsters.imageset/menu-hamsters.heic
```

The image is bundled in the asset catalog and shown with SwiftUI
`Image("MenuHamsters")`, preserving its square aspect ratio. The menu does not
create an animated RealityKit showcase or render subscription. Xcode compiles
and may re-encode images when packaging the asset catalog; the size above is
for the source HEIC asset, not a claim about final app download size.
