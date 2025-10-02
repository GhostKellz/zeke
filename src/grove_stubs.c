// Stub implementations for Grove language parsers that aren't compiled
// These satisfy the linker but should never be called

typedef struct TSLanguage TSLanguage;

// Stub for Rust parser (not included in Grove build)
const TSLanguage *tree_sitter_rust(void) {
    return (const TSLanguage *)0; // Return null - will error if actually used
}

// Stub for TypeScript parser (available but not compiled)
const TSLanguage *tree_sitter_typescript(void) {
    return (const TSLanguage *)0;
}

// Stub for TSX parser (available but not compiled)
const TSLanguage *tree_sitter_tsx(void) {
    return (const TSLanguage *)0;
}
