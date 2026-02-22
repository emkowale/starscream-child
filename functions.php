<?php
/*
 * File: /starscream-child/functions.php
 * Description: Child theme bootstrap — enqueue styles, add supports, and set up text domain.
 * Theme: Starscream Child
 * Author: Eric Kowalewski
 * Author URI: https://thebeartraxs.com
 * Version: 1.0.0
 * Last Updated: 2025-08-28 15:49 
 */

if ( ! defined( 'ABSPATH' ) ) { exit; }

if ( ! defined( 'STARSCREAM_CHILD_VERSION' ) ) {
    define( 'STARSCREAM_CHILD_VERSION', '1.0.0' );
}

/**
 * Enqueue parent and child styles.
 */
add_action( 'wp_enqueue_scripts', function() {
    // Load parent theme stylesheet
    wp_enqueue_style( 'parent-style', get_template_directory_uri() . '/style.css' );

    // Load child stylesheet, dependent on parent
    $child_style_path = get_stylesheet_directory() . '/style.css';
    $child_ver = file_exists( $child_style_path ) ? filemtime( $child_style_path ) : STARSCREAM_CHILD_VERSION;
    wp_enqueue_style( 'starscream-child-style', get_stylesheet_uri(), array( 'parent-style' ), $child_ver );
} );

/**
 * Theme setup.
 */
add_action( 'after_setup_theme', function() {
    // Make theme available for translation
    load_child_theme_textdomain( 'starscream-child', get_stylesheet_directory() . '/languages' );

    // Common supports (inherit from parent, but safe to declare)
    add_theme_support( 'title-tag' );
    add_theme_support( 'post-thumbnails' );
    add_theme_support( 'woocommerce' );
} );

/**
 * Vector uploads (EPS/AI/SVG and more) — theme-level.
 * Drop this into functions.php. Safe to migrate into Starscream later.
 *
 * Notes:
 * - SVGs can contain scripts. If non-admins upload SVGs, use a sanitizer plugin.
 * - On Multisite, Network Admin → Settings → "Upload file types" must also include these extensions.
 */
add_action('after_setup_theme', function () {
    // 1) Declare the vector whitelist once (ext => mime)
    $GLOBALS['bt_vector_mimes'] = [
        // Core / common
        'svg'  => 'image/svg+xml',
        'svgz' => 'image/svg+xml',
        'ai'   => 'application/postscript',
        'eps'  => 'application/postscript',
        'ps'   => 'application/postscript',
        'pdf'  => 'application/pdf',

        // App-specific / legacy
        'cdr'  => 'application/vnd.corel-draw',
        'cmx'  => 'image/x-cmx',
        'fh'   => 'application/vnd.adobe.freehand',
        'fh7'  => 'application/vnd.adobe.freehand',
        'fh8'  => 'application/vnd.adobe.freehand',
        'fh9'  => 'application/vnd.adobe.freehand',
        'fh10' => 'application/vnd.adobe.freehand',
        'fh11' => 'application/vnd.adobe.freehand',
        'wpg'  => 'application/x-wpg',
        'xar'  => 'application/vnd.xara',
        'fig'  => 'application/x-xfig',
        'drw'  => 'image/x-drw',

        // CAD / technical
        'dxf'  => 'application/dxf',
        'dwg'  => 'application/acad',
        'dgn'  => 'application/vnd.microstation-dgn',
        'igs'  => 'model/iges',
        'iges' => 'model/iges',
        'cgm'  => 'image/cgm',
        'hpgl' => 'application/vnd.hp-hpgl',
        'plt'  => 'application/vnd.hp-hpgl',

        // Windows / Office
        'wmf'  => 'image/wmf',
        'emf'  => 'image/emf',
        'vsd'  => 'application/vnd.visio',
        'vsdx' => 'application/vnd.ms-visio.drawing.main+xml',

        // 3D / manufacturing (vector geometry / meshes)
        'stl'  => 'model/stl',
        'amf'  => 'model/amf',
        'skp'  => 'application/vnd.sketchup.skp',

        // Open/LibreOffice Draw
        'sxd'  => 'application/vnd.sun.xml.draw',
        'odg'  => 'application/vnd.oasis.opendocument.graphics',
    ];
});

/**
 * 2) Allow the extensions via the "upload_mimes" list.
 */
add_filter('upload_mimes', function ($mimes) {
    if (!isset($GLOBALS['bt_vector_mimes'])) return $mimes;
    // Merge but don't clobber existing keys unless we provide a better MIME
    foreach ($GLOBALS['bt_vector_mimes'] as $ext => $mime) {
        $mimes[$ext] = $mime;
    }
    return $mimes;
}, 10, 1);

/**
 * 3) Pass the deeper file/extension check for our whitelist.
 *    This addresses the classic "Sorry, you are not allowed to upload this file type." on EPS/AI/SVG.
 */
add_filter('wp_check_filetype_and_ext', function ($data, $file, $filename, $mimes, $real_mime) {
    if (!isset($GLOBALS['bt_vector_mimes'])) return $data;

    $ext = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
    if (isset($GLOBALS['bt_vector_mimes'][$ext])) {
        $data['ext']  = $ext;
        $data['type'] = $GLOBALS['bt_vector_mimes'][$ext];

        // Preserve original filename if WP couldn't determine a "proper filename"
        if (empty($data['proper_filename'])) {
            $data['proper_filename'] = $filename;
        }
    }
    return $data;
}, 10, 5);


