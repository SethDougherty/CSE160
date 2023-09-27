#include "../../includes/channels.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"
#include "../../includes/neighbors.h"
#define DELAY_PERIOD 30000 //5000 ms or 5 seconds
#define LIST_SIZE 255

module NeighborDiscoveryP{
	// uses interface
	uses interface Timer<TMilli> as delayTimer;
	uses interface SimpleSend as NeighborSender;
	uses interface Receive as NeighborReceive;
	
	provides interface NeighborDiscovery;
}

implementation{
	pack send_package;
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);

	uint16_t neighbor_element = 0;
	struct neighborList Neighbors[LIST_SIZE];

	command void NeighborDiscovery.startTimer(){
		dbg(NEIGHBOR_CHANNEL, "Starting Neighbor discovery Delay Timer \n");
		call delayTimer.startPeriodic(DELAY_PERIOD);
	}

	void calculateLinkQuality(int i){
		if(Neighbors[i].messages_sent != 0){
			Neighbors[i].link_quality = (Neighbors[i].messages_received*100) / Neighbors[i].messages_sent;
		}
	}

	// command neighborList* NeighborDiscovery.getNeighborList(){
	// 	return Neighbors;
	// }

	void checkNeighbors(uint16_t src){
		uint32_t i = 0;
		for (i = 0; i < LIST_SIZE; i++){
			//check if the neighbor is already known
			if(Neighbors[i].node_id == src){
				//if known, refresh active neighbor threshold and increment received and sent, since it will send after that
				Neighbors[i].active_neighbor = 1;
				Neighbors[i].messages_received++;
				return;
			}
		}
		//If not known, add to next open position of Neighbor and increment messages received and sent by new neighbor
		Neighbors[neighbor_element].node_id = src;
		Neighbors[neighbor_element].active_neighbor = 1;
		Neighbors[neighbor_element].messages_received++;
		neighbor_element++;

	}

	//update the neighbors and remove any neighbors that are past the threshold	
	void updateNeighbors(){
		uint32_t i = 0;
		uint32_t j = 0;

		for(i = 0; i < LIST_SIZE; i++){
			if(Neighbors[i].active_neighbor == 6){
				for(j = i; j < LIST_SIZE - 1; j++){
					//dbg(NEIGHBOR_CHANNEL, "active_neighbor is: %u \n", Neighbors[i].active_neighbor);
					Neighbors[j].node_id = Neighbors[j + 1].node_id;
					Neighbors[j].active_neighbor = Neighbors[j + 1].active_neighbor;
					Neighbors[j].messages_sent = Neighbors[j + 1].messages_sent;
					Neighbors[j].messages_received = Neighbors[j + 1].messages_received;
				}

			Neighbors[LIST_SIZE - 1].node_id = 0;
			Neighbors[LIST_SIZE - 1].active_neighbor = 0;
			Neighbors[LIST_SIZE - 1].messages_sent = 0;
			Neighbors[LIST_SIZE - 1].messages_received = 0;
			neighbor_element--;
			}
		}
		//call NeighborDiscovery.print();
	}

	command void NeighborDiscovery.print(){
		uint32_t i = 0;
		dbg(NEIGHBOR_CHANNEL, "Printing Neighbors of %u:\n", TOS_NODE_ID);
		for(i = 0; i < LIST_SIZE; i++){
			if(Neighbors[i].node_id != 0){
				calculateLinkQuality(i);
				dbg(NEIGHBOR_CHANNEL, "Neighbor: %u, age: %u, link quality: %u% \n", Neighbors[i].node_id, Neighbors[i].active_neighbor, Neighbors[i].link_quality);
			}
		}
	}

	event void delayTimer.fired(){
		uint32_t i = 0;
		//make package
		makePack(&send_package, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, 0, PROTOCOL_PING, "", PACKET_MAX_PAYLOAD_SIZE);
		//send package
		call NeighborSender.send(send_package, AM_BROADCAST_ADDR);
		//increment number of messages sent
		for(i = 0; i < LIST_SIZE; i++){
			Neighbors[i].messages_sent++;
		}
	}

	event message_t* NeighborReceive.receive(message_t* msg, void* payload, uint8_t len){
		uint32_t i = 0;
		pack *reply_msg = (pack *) payload;
		if(reply_msg->dest == AM_BROADCAST_ADDR){
			for (i = 0; i < LIST_SIZE; i++){
				if(Neighbors[i].node_id == reply_msg->src){
					Neighbors[i].messages_received++;
					Neighbors[i].messages_sent++;
				}
			}
			reply_msg->dest = reply_msg->src;
			reply_msg->src = TOS_NODE_ID;
			reply_msg->protocol = PROTOCOL_PINGREPLY;
			//send reply
			call NeighborSender.send(*reply_msg, reply_msg->dest);
		}
		else if(reply_msg->dest == TOS_NODE_ID){
			checkNeighbors(reply_msg->src);
			for(i = 0; i < LIST_SIZE; i++){
				if(Neighbors[i].active_neighbor < 6 && Neighbors[i].active_neighbor > 0){
					Neighbors[i].active_neighbor++;
				}
			}
		//update the neighbors and remove any neighbors that are past the threshold
		updateNeighbors();
		}
		return msg;
		
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