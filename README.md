# Starscream Child

![Starscream Child Logo](screenshot.png)

Permanent WordPress child theme for the `starscream` parent theme.

## Quick Install

1. In WordPress Admin, go to `Appearance -> Themes -> Add New -> Upload Theme`.
2. Upload the theme ZIP and install it.
3. Confirm `Template: starscream` in `style.css` matches your parent theme folder.
4. Activate **Starscream Child**.

## What This Theme Does

- Loads parent `style.css` first, then child `style.css`.
- Uses file modification time for cache busting on child CSS.
- Keeps your customizations upgrade-safe from parent theme updates.

## Customize

- CSS overrides: `style.css`
- PHP overrides/helpers: `functions.php` (or included files)
- Theme card image: `screenshot.png`

## Theme Meta

- Theme Name: `Starscream Child`
- Template: `starscream`
- Text Domain: `starscream-child`
- Update URI: `https://github.com/emkowale/starscream-child`

## Release Workflow

Use:

```bash
./release.sh patch
```

Also supports:

```bash
./release.sh minor
./release.sh major
```

The script bumps version metadata, updates changelog, commits, tags, pushes, and builds a ZIP artifact.
