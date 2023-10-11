#include "../../includes/packet.h"

interface Flooding{
     command void start(uint16_t destination, uint8_t *payload);
     //command void addToCache(uint16_t src, uint16_t seq, uint16_t dest);
}