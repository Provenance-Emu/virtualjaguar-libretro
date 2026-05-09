/* SPM-only fallback version.h.
 *
 * Upstream gitignores this file and regenerates it from
 * `scripts/gen-version-h.sh` on every Makefile build. SPM has no hook
 * to run that script, so we ship a pinned fallback here on the
 * `provenance-spm-fixes` branch.
 *
 * If the parent build system defines CORE_VERSION (or BUILD_TIMESTAMP)
 * through cSettings, those win — otherwise this header sets a sensible
 * default that lets libretro.c compile.
 *
 * Makefile builds overwrite this file at build time, so on Make-based
 * platforms there's no behaviour change.
 */
#ifndef VJAG_VERSION_H
#define VJAG_VERSION_H

#ifndef CORE_BASE_VERSION
#define CORE_BASE_VERSION "v2.3.0"
#endif

#ifndef GIT_VERSION
#define GIT_VERSION " spm"
#endif

#ifndef CORE_VERSION
#ifdef BUILD_TIMESTAMP
#define CORE_VERSION CORE_BASE_VERSION GIT_VERSION " " BUILD_TIMESTAMP
#else
#define CORE_VERSION CORE_BASE_VERSION GIT_VERSION
#endif
#endif

#endif
