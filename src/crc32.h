#ifndef __CRC32_H__
#define __CRC32_H__
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t crc32_calcCheckSum(unsigned char * data, size_t length);

#ifdef __cplusplus
}
#endif

#endif	// __CRC32_H__
