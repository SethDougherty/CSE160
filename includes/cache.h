#ifndef CACHE_H
#define CACHE_H

typedef struct cache {
	uint16_t src;
	uint16_t seq;
	uint16_t dest;
	uint8_t data[0];
} cache;

#endif