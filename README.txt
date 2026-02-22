Starscream Child Theme (v1.0.0)
===================================

1) Upload the ZIP to **Appearance → Themes → Add New → Upload Theme**.
2) Ensure the **Template** in style.css matches your parent theme's folder name.
   - Current value: `starscream`
   - If your parent theme folder is different (e.g. `starscream-v1.4.23`), edit `Template:` accordingly.
3) Activate **Starscream Child**.
4) Put custom CSS into `style.css` and custom PHP into `functions.php` or separate files you include from there.

Notes
-----
- The child theme enqueues the parent `style.css` and then this child `style.css`, with cache-busting via file modification time.
- A placeholder `screenshot.png` is included so the theme card looks nice in the admin.
- Text domain: `starscream-child`
