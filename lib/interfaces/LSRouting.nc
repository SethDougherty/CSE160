// #include "../../includes/neighbors.h"
interface LSRouting{
    command error_t start();
	command void print();
    command void ping(uint16_t destination, uint8_t *payload);
    command void routePacket(pack* myMsg);
    command void neighborchange(uint16_t lostNeighbor);
}