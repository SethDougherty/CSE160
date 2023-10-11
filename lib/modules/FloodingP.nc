#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#include "../../includes/neighbors.h"
#include "../../includes/cache.h"
#define CACHE_SIZE 30

module FloodingP{
	//provides interface Receive as MainReceive;
    provides interface Flooding;
	uses interface SimpleSend as InternalSender;
	uses interface Receive as InternalReceiver;
	//uses interface NeighborDiscovery;
}
implementation{
	pack ping_package;
	uint16_t monotonic_seq = 0;
	uint16_t counter = 0;
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
	void addToCache(uint16_t src, uint16_t seq, uint16_t dest);

	struct cache Caches[CACHE_SIZE];

	command void Flooding.start(uint16_t destination, uint8_t *payload){
		dbg(FLOODING_CHANNEL, "SENDER %d\n", TOS_NODE_ID);
        dbg(FLOODING_CHANNEL, "DEST %d\n", destination);
		makePack(&ping_package, TOS_NODE_ID, destination, CACHE_SIZE, PROTOCOL_PING, monotonic_seq, payload, PACKET_MAX_PAYLOAD_SIZE);
        call InternalSender.send(ping_package, AM_BROADCAST_ADDR);
		addToCache(TOS_NODE_ID, monotonic_seq, destination);
        monotonic_seq++;
	}

	void addToCache(uint16_t src, uint16_t seq, uint16_t dest){
		uint32_t i;
		// Check if Cache has room left
		if (counter < CACHE_SIZE){ 
			Caches[counter].src = src;
			Caches[counter].seq = seq;
			Caches[counter].dest = dest;
			counter++;
		} 
		// If there isn't more space, remove oldest item and add new item to the end of the cach
		else{
			for (i = 0; i < CACHE_SIZE-1; i++) {
				Caches[i].src = Caches[i+1].src;
				Caches[i].seq = Caches[i+1].seq;
				Caches[i].dest = Caches[i+1].dest;
			}

			Caches[CACHE_SIZE].src = src;
			Caches[CACHE_SIZE].seq = seq;
			Caches[CACHE_SIZE].dest = dest;
		}
		// return;
	}

	event message_t* InternalReceiver.receive(message_t* raw_msg, void* payload, uint8_t len){
		pack *msg = (pack *) payload;
		uint32_t i;
		//struct neighborList* TempNeighbors = call NeighborDiscovery.getNeighborList();
		dbg(FLOODING_CHANNEL, "Ping received!\n");
		//Check if item is in cache, if it is, return
		for (i = 0; i < CACHE_SIZE; i++){
			if (msg->src == Caches[i].src && msg->seq == Caches[i].seq){
				dbg(FLOODING_CHANNEL, "Packet in Cache. Dropping...\n");
				return raw_msg;
			}
		}
		addToCache(msg->src, msg->seq, msg->dest);
		if(msg->TTL == 0){		
			dbg(FLOODING_CHANNEL, "TTL = 0. Dropping...\n");
			return raw_msg;		
		}

		if (msg->dest == TOS_NODE_ID){
			if(msg->protocol == PROTOCOL_PING){
				// dbg(FLOODING_CHANNEL, "Ping received!\n");
		        makePack(&ping_package, msg->dest, msg->src, CACHE_SIZE, PROTOCOL_PINGREPLY, ++monotonic_seq,(uint8_t *) msg->payload, PACKET_MAX_PAYLOAD_SIZE);
				call InternalSender.send(ping_package, AM_BROADCAST_ADDR);
				addToCache(msg->dest, monotonic_seq, msg->src);
				dbg(FLOODING_CHANNEL, "Pingreply Sent from %u\n", TOS_NODE_ID);
			}
			else{
				dbg(FLOODING_CHANNEL, "reply received!\n");
				dbg(FLOODING_CHANNEL, "Final response from: %u \n", msg->src);
			}
		}

		else{ 
			msg->TTL--;
			call InternalSender.send(*msg, AM_BROADCAST_ADDR);
			dbg(FLOODING_CHANNEL, "Packet forwarded from %u with new TTL and logged\n", TOS_NODE_ID);
		} 
		return raw_msg;
	}

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}
}