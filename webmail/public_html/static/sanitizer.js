// ==ClosureCompiler==
// @compilation_level SIMPLE_OPTIMIZATIONS
// @output_file_name sanitizer.js
// @use_closure_library true
// ==/ClosureCompiler==

// goog.module('webmail');

const Builder = goog.require('goog.html.sanitizer.HtmlSanitizer.Builder');
const SafeUrl = goog.require('goog.html.SafeUrl');

export function sanitizeEmail(input_html) {
    const sanitizer = new Builder()
        .withCustomNetworkRequestUrlPolicy(SafeUrl.sanitize)
        .allowCssStyles()
        .allowFormTag()
        .addOriginalTagNames()
        .build();

    return sanitizer.sanitizeToDomNode(input_html);
}

window.sanitize = sanitizeEmail;