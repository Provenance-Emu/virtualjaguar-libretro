/* Stub cdrom.h for SPM module map compatibility.
 * VirtualJaguar does not use libretro cdrom passthrough;
 * this satisfies the include from vfs_implementation_cdrom.h
 * when HAVE_CDROM is defined elsewhere in the SPM build. */

#ifndef __LIBRETRO_SDK_CDROM_H
#define __LIBRETRO_SDK_CDROM_H

#include <stdint.h>
#include <retro_common_api.h>

RETRO_BEGIN_DECLS

typedef struct
{
   unsigned lba_start;
   unsigned lba;
   unsigned track_size;
   unsigned track_bytes;
   unsigned char track_num;
   unsigned char min;
   unsigned char sec;
   unsigned char frame;
   unsigned char mode;
   _Bool audio;
} cdrom_track_t;

typedef struct
{
   cdrom_track_t track[99];
   unsigned char num_tracks;
   char drive;
} cdrom_toc_t;

RETRO_END_DECLS

#endif
