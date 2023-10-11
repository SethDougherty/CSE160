#include "../../includes/neighbors.h"
interface NeighborDiscovery{
    command void startTimer();
	command void print();
    command neighborList* getNeighborList();
    command uint16_t getNeighborListSize();
}