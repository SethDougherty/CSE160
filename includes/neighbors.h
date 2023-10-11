#ifndef NEIGHBORS_H
#define NEIGHBORS_H

typedef struct neighborList{
	uint16_t node_id;
	uint16_t active_neighbor;
	uint16_t link_quality;
	uint8_t messages_sent;
	uint8_t messages_received;
} neighborList;

#endif