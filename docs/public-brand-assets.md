# Public Brand Assets

This document defines the approved asset set for `joshtina.support` and other public-facing supporter surfaces.

## Primary Rules

- Use `PublicWordmark` for public React page headers and in-app wordmark treatments.
- Use the exported raster and SVG assets in `web/public/` for browser chrome, installs, and link previews.
- Do not create one-off logo treatments for public pages when an approved asset already exists.
- Do not use `logo-placeholder.svg` on public-facing pages. It is an internal fallback for admin surfaces only.

## Approved Public Assets

- `web/public/favicon.svg`: compact browser-tab favicon.
- `web/public/favicon-32x32.png`: raster favicon fallback for browsers that prefer PNG.
- `web/public/icon-192.png`: installable app icon and Android/PWA asset.
- `web/public/icon-512.png`: large installable app icon and social/platform fallback.
- `web/public/apple-touch-icon.png`: iOS home-screen icon.
- `web/public/og-image.svg`: editable source for the branded social preview image.
- `web/public/og-image.png`: exported Open Graph and Twitter preview image referenced by `web/index.html`.
- `web/public/joshtina-supporter.jpeg`: supporter artwork for landing and signup page cards.
- `web/public/joshtina-thank-you.avif`: thank-you page artwork.

## Usage Guidance

- Browser tab icon: `favicon.svg`, with `favicon-32x32.png` as fallback.
- Installed shortcut / home-screen icon: `apple-touch-icon.png`, `icon-192.png`, and `icon-512.png`.
- Link preview in iMessage, Facebook, X, Slack, Discord, and similar: `og-image.png`.
- Public page headers: `PublicWordmark` instead of image logos when rendering inside React.

## Regenerating Derived Assets

When the OG preview artwork changes, update `web/public/og-image.svg` first and then export the PNG:

```sh
sips -s format png "web/public/og-image.svg" --out "web/public/og-image.png"
```

When the install icon changes, regenerate the apple-touch and favicon PNGs from the approved square icon source:

```sh
sips -z 180 180 "web/public/icon-512.png" --out "web/public/apple-touch-icon.png"
sips -z 32 32 "web/public/icon-512.png" --out "web/public/favicon-32x32.png"
```

## Brand Consistency Notes

- Keep the public palette anchored to campaign blue `#0F3E86`, CTA red `#E23A22`, and gold `#D5A332`.
- Maintain the current public voice: official, clean, and campaign-forward rather than generic product marketing.
- Reuse the existing "Building Guam's Future Together" framing across public supporter surfaces unless leadership asks for a new campaign line.
