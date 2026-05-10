/*
 * Blitter SIMD ops -- out-of-line sse2 vtable.
 *
 * The implementations themselves live in blitter_simd_sse2.h so that
 * blitter.c can inline them (see blitter_simd.h).  This file only
 * provides the function-pointer table, which test/test_blitter_simd.c
 * uses to exercise the very same code the core runs.
 *
 * SSE2 is baseline for all x86_64 processors and available on x86 since
 * Pentium 4 (2001).  No runtime feature detection needed.
 */

/* Two guards, and they are not the same guard.
 *
 * The outer arch check makes this whole TU empty on the wrong host.  The
 * SPM build (Package.swift) compiles every SIMD variant together rather
 * than letting the Makefile pick one, so without it the wrong intrinsic
 * header gets pulled in and the build dies on a cross-arch host.
 *
 * The inner define selects our own arch before blitter_simd.h picks one.
 * This file IS the sse2 implementation, so it must get the sse2 inline set
 * even when compiled standalone without the Makefile's -DBLITTER_SIMD_SSE2
 * -- as .github/workflows/c-cpp.yml does when it builds test_blitter_simd
 * by hand.  Without it the header chain pulled in the scalar set as well
 * and the two collided. */
#if defined(__x86_64__) || defined(__i386__) || defined(_M_X64) || defined(_M_IX86)

#ifndef BLITTER_SIMD_SSE2
#define BLITTER_SIMD_SSE2 1
#endif

#include "blitter_simd.h"
#include "blitter_simd_sse2.h"

static uint64_t ops_lfu(uint64_t srcd, uint64_t dstd, uint8_t lfu_func)
{
   return blitter_simd_lfu(srcd, dstd, lfu_func);
}

static uint8_t ops_dcomp(uint64_t patd, uint64_t srcd, uint64_t dstd, bool cmpdst)
{
   return blitter_simd_dcomp(patd, srcd, dstd, cmpdst);
}

static uint8_t ops_zcomp(uint64_t srcz, uint64_t dstz, uint8_t zmode)
{
   return blitter_simd_zcomp(srcz, dstz, zmode);
}

static uint64_t ops_byte_merge(uint64_t src, uint64_t dst, uint16_t mask)
{
   return blitter_simd_byte_merge(src, dst, mask);
}

static void ops_add16sat_x4(uint16_t *addq, uint8_t *co,
                            const uint16_t *adda, const uint16_t *addb,
                            const uint8_t *cin,
                            bool sat, bool eightbit, bool hicinh)
{
   blitter_simd_add16sat_x4(addq, co, adda, addb, cin, sat, eightbit, hicinh);
}

const blitter_simd_ops_t blitter_simd_ops = {
   ops_lfu,
   ops_dcomp,
   ops_zcomp,
   ops_byte_merge,
   ops_add16sat_x4
};

#endif /* __x86_64__ || __i386__ || _M_X64 || _M_IX86 */
