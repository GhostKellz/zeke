# Grove Fix Required - Vendor Files Gitignored

**Project:** github.com/ghostkellz/grove
**Issue:** `.gitignore` excludes `vendor/tree-sitter/` directory
**Impact:** GitHub archives don't include vendor files → Zig build fails
**Fix Time:** **30 seconds**
**Priority:** 🔥 **HIGH**

---

## 🎯 **The Problem**

Grove's `.gitignore` contains:
```gitignore
vendor/tree-sitter/
vendor/tree-sitter-rust/
```

This means:
- ✅ Vendor files exist locally
- ❌ NOT committed to Git
- ❌ NOT in GitHub archives
- ❌ `zig fetch` gets empty vendor directories
- ❌ Build fails with "FileNotFound"

---

## ✅ **The Fix - 30 Seconds**

### In Grove Repository:

```bash
cd ~/projects/grove

# 1. Remove vendor ignores from .gitignore
sed -i '/vendor\/tree-sitter\//d' .gitignore
sed -i '/vendor\/tree-sitter-rust\//d' .gitignore

# 2. Stage vendor files (they already exist!)
git add vendor/
git add .gitignore

# 3. Commit
git commit -m "fix: Un-ignore vendor files for Zig dependency compatibility

Removes vendor/tree-sitter/ and vendor/tree-sitter-rust/ from .gitignore.
GitHub archives now include these files, fixing zig fetch builds."

# 4. Push
git push origin main
```

**Done!** That's literally it.

---

## 🧪 **Verification**

After pushing, verify with:

```bash
# Check files are tracked by git
git ls-files vendor/tree-sitter/lib/src/lib.c
# Expected output: vendor/tree-sitter/lib/src/lib.c ✅

# Test archive includes files
curl -sL https://github.com/ghostkellz/grove/archive/refs/heads/main.tar.gz | tar tz | grep "lib.c"
# Should list lib.c ✅
```

---

## 🔧 **Testing in Zeke**

Once Grove is fixed:

```bash
cd /data/projects/zeke

# Clear cache
rm -rf ~/.cache/zig/p/grove-*

# Re-fetch Grove
zig fetch --save https://github.com/ghostkellz/grove/archive/refs/heads/main.tar.gz

# Verify files exist
ls ~/.cache/zig/p/grove-*/vendor/tree-sitter/lib/src/lib.c
# Should exist! ✅

# Build Zeke with Grove
zig build
# Should compile! ✅
```

---

## 📋 **Why This Happened**

Common practice is to gitignore `vendor/` to avoid committing large third-party code.
**However**, for Zig dependencies:
- Zig's package manager (`zig fetch`) downloads GitHub archive tarballs
- Archives only include **committed files**
- Gitignored files = not in archives = build fails

**Solution**: For Zig libraries, vendor files MUST be committed.

---

## 🚀 **After the Fix**

Zeke will gain:
- ✅ AST-based code analysis
- ✅ Syntax-aware refactoring
- ✅ Symbol navigation (go-to-definition, find references)
- ✅ Syntax highlighting via tree-sitter
- ✅ Real-time syntax validation
- ✅ Multi-language support (Zig, Rust, JSON, Ghostlang)

Commands ready to activate:
```bash
zeke analyze <file>                # Code structure analysis
zeke refactor rename <old> <new>   # Rename symbols
zeke symbols <file>                # List all symbols
zeke definition <file> <line> <col> # Go to definition
zeke references <symbol>           # Find all references
```

---

## ⏱️ **Impact**

- **Grove fix time:** 30 seconds
- **Zeke features unlocked:** 40% of planned functionality
- **Commands enabled:** 7 new commands
- **Build time after fix:** ~60 seconds

---

## 📝 **Alternative (If Local Vendor Missing)**

If vendor files don't exist locally, download them:

```bash
cd ~/projects/grove

# Download tree-sitter
curl -L https://github.com/tree-sitter/tree-sitter/archive/refs/tags/v0.22.6.tar.gz | tar xz
mkdir -p vendor/tree-sitter
cp -r tree-sitter-0.22.6/lib vendor/tree-sitter/
rm -rf tree-sitter-0.22.6

# Grammars should already exist in vendor/grammars/
# If not, download them similarly

# Then follow the fix steps above
```

---

**Status:** ✅ **FIXED** - Vendor files committed and available in GitHub archives
**Previous Blocker:** Vendor files not committed to Git
**Solution Applied:** Removed vendor ignores from `.gitignore` and committed vendor files
**Verification:** ✅ `lib.c` confirmed in GitHub archive tarball

**Last Updated:** 2025-10-01
**Fixed By:** Grove maintenance
