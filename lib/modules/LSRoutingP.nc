#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/cache.h"
#include "../../includes/linkedstate.h"
#define LS_MAX_ROUTES 255
#define LS_MAX_COST 17
#define LS_TTL 17
#define CACHE_SIZE 30

module LSRoutingP {
    provides interface LSRouting;
    
    uses interface SimpleSend as RouteSender;
    uses interface NeighborDiscovery as NeighborDiscovery;
    uses interface Timer<TMilli> as RouteTimer;
    uses interface Receive as RouteReceive;
    
}

implementation {

    uint8_t linkState[LS_MAX_ROUTES][LS_MAX_ROUTES];
    Route routingTable[LS_MAX_ROUTES];
    cache Caches[CACHE_SIZE];
    uint16_t numKnownNodes = 0;
    uint16_t numRoutes = 0;
    uint16_t sequenceNum = 0;
    uint16_t cache_counter = 0;
    pack routePack;
    // struct cache Caches[CACHE_SIZE];
    struct neighborList TempNeighbors[255];

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length);
    void initilizeRoutingTable();
    bool updateState(pack* myMsg);
    bool updateRoute(uint8_t dest, uint8_t nextHop, uint8_t cost);
    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost);
    void removeRoute(uint8_t dest);
    void sendLSP(uint8_t lostNeighbor);
    void djikstra();

    bool checkChache(uint16_t src, uint16_t seq){
		uint32_t i;
		for (i = 0; i < 30; i++) {
			if (src == Caches[i].src && seq == Caches[i].seq) {
				return TRUE;
			}
		}
		return FALSE;
	}

	void addToCache(uint16_t src, uint16_t seq, uint16_t dest){
		uint32_t i;
		// Check if Cache has room left
		if (cache_counter < CACHE_SIZE){ 
			Caches[cache_counter].src = src;
			Caches[cache_counter].seq = seq;
			Caches[cache_counter].dest = dest;
			cache_counter++;
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


    command error_t LSRouting.start() {
        // Initialize routing table and neighbor state structures
        // Start one-shot
        dbg(ROUTING_CHANNEL, "Link State Routing Started on node %u!\n", TOS_NODE_ID);
        initilizeRoutingTable();
        call RouteTimer.startPeriodic(40000);
   }

    event void RouteTimer.fired() {
            // Send flooding packet w/neighbor list
            sendLSP(0);
    }

    command void LSRouting.ping(uint16_t destination, uint8_t *payload) {
        makePack(&routePack, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(ROUTING_CHANNEL, "PING FROM %d TO %d\n", TOS_NODE_ID, destination);
       
        call LSRouting.routePacket(&routePack);
    }    

    command void LSRouting.routePacket(pack* myMsg) {
        // Look up value in table and forward
        uint8_t nextHop;

        if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PING) {
            dbg(ROUTING_CHANNEL, "PING Packet has reached destination %d!!!\n", TOS_NODE_ID);
            makePack(&routePack, myMsg->dest, myMsg->src, 0, PROTOCOL_PINGREPLY, 0,(uint8_t *) myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
            call LSRouting.routePacket(&routePack);
            return;
        } 
        else if(myMsg->dest == TOS_NODE_ID && myMsg->protocol == PROTOCOL_PINGREPLY) {
            dbg(ROUTING_CHANNEL, "PING_REPLY Packet has reached destination %d!!!\n", TOS_NODE_ID);
            return;
        }
        if(routingTable[myMsg->dest].cost < LS_MAX_COST) {
            nextHop = routingTable[myMsg->dest].nextHop;
            dbg(ROUTING_CHANNEL, "Node %d routing packet through %d\n", TOS_NODE_ID, nextHop);
            
            call RouteSender.send(*myMsg, nextHop);
        } 
        else{
            dbg(ROUTING_CHANNEL, "No route to destination. Dropping packet...\n");
            
        }
    }

    command void LSRouting.neighborchange(uint16_t lostNeighbor) {
        uint32_t* neighbors = call NeighborDiscovery.getNeighborList();
        uint16_t neighborsListSize = call NeighborDiscovery.getNeighborListSize();
        uint16_t i = 0;
        if(lostNeighbor == 0){
            // dbg(ROUTING_CHANNEL, "neighbor list: %d \n", neighbors[i]);
            for(i = 0; i < neighborsListSize; i++) {
                linkState[TOS_NODE_ID][neighbors[i]] = 1;
                linkState[neighbors[i]][TOS_NODE_ID] = 1;
            }
            sendLSP(0);
            djikstra();
        }
        else{
            dbg(ROUTING_CHANNEL, "Neighbor lost %u\n", lostNeighbor);
            if(linkState[TOS_NODE_ID][lostNeighbor] != LS_MAX_COST){
                linkState[TOS_NODE_ID][lostNeighbor] = LS_MAX_COST;
                linkState[lostNeighbor][TOS_NODE_ID] = LS_MAX_COST;
                numKnownNodes--;
                removeRoute(lostNeighbor);
            }
            sendLSP(lostNeighbor);
            djikstra();
        }
    }

    command void LSRouting.print() {
        uint16_t i;
        dbg(ROUTING_CHANNEL, "DEST  HOP  COST\n");
        for(i = 1; i < LS_MAX_ROUTES; i++) {
            if(routingTable[i].cost != LS_MAX_COST)
                dbg(ROUTING_CHANNEL, "%4d%5d%6d\n", i, routingTable[i].nextHop, routingTable[i].cost);
        }
    }

    void initilizeRoutingTable() {
        uint16_t i, j;
        for(i = 0; i < LS_MAX_ROUTES; i++) {
            routingTable[i].nextHop = 0;
            routingTable[i].cost = LS_MAX_COST;
        }
        for(i = 0; i < LS_MAX_ROUTES; i++) {
            linkState[i][0] = 0;
        }
        for(i = 0; i < LS_MAX_ROUTES; i++) {
            linkState[0][i] = 0;
        }
        for(i = 1; i < LS_MAX_ROUTES; i++) {
            for(j = 1; j < LS_MAX_ROUTES; j++) {
                linkState[i][j] = LS_MAX_COST;
            }
        }
        routingTable[TOS_NODE_ID].nextHop = TOS_NODE_ID;
        routingTable[TOS_NODE_ID].cost = 0;
        linkState[TOS_NODE_ID][TOS_NODE_ID] = 0;
        numKnownNodes++;
        numRoutes++;
    }

    bool updateState(pack* myMsg) {
        uint16_t i;
        LSP *lsp = (LSP *)myMsg->payload;
        bool flag = FALSE;
        for(i = 0; i < 10; i++) {
            if(linkState[myMsg->src][lsp[i].neighbor] != lsp[i].cost) {
                if(linkState[myMsg->src][lsp[i].neighbor] == LS_MAX_COST) {
                    numKnownNodes++;
                } else if(lsp[i].cost == LS_MAX_COST) {
                    numKnownNodes--;
                }
                linkState[myMsg->src][lsp[i].neighbor] = lsp[i].cost;
                linkState[lsp[i].neighbor][myMsg->src] = lsp[i].cost;
                flag = TRUE;
            }
        }
        return flag;
    }

    void sendLSP(uint8_t lostNeighbor) {
        uint32_t* neighbors = call NeighborDiscovery.getNeighborList();
        uint16_t neighborsListSize = call NeighborDiscovery.getNeighborListSize();
        uint16_t i = 0;
        uint16_t counter = 0;
        LSP linkStatePayload[10];
        // Zero out the array
        for(i = 0; i < 10; i++) {
            linkStatePayload[i].neighbor = 0;
            linkStatePayload[i].cost = 0;
        }
        i = 0;
        // If neighbor lost -> send out infinite cost
        if(lostNeighbor != 0) {
            dbg(ROUTING_CHANNEL, "Sending out lost neighbor %u\n", lostNeighbor);
            linkStatePayload[counter].neighbor = lostNeighbor;
            linkStatePayload[counter].cost = LS_MAX_COST;
            i++;
            counter++;
        }
        // Add neighbors in groups of 10 and flood LSP to all neighbors
        for(; i < neighborsListSize; i++) {
            linkStatePayload[counter].neighbor = neighbors[i];
            linkStatePayload[counter].cost = 1;
            counter++;
            if(counter == 10 || i == neighborsListSize-1) {
                // Send LSP to each neighbor                
                makePack(&routePack, TOS_NODE_ID, 0, LS_TTL, PROTOCOL_LINKSTATE, sequenceNum++, &linkStatePayload, sizeof(linkStatePayload));
                call RouteSender.send(routePack, AM_BROADCAST_ADDR);
                // Zero the array
                while(counter > 0) {
                    counter--;
                    linkStatePayload[i].neighbor = 0;
                    linkStatePayload[i].cost = 0;
                }
            }
        }
    }

    void djikstra() {
        uint16_t i = 0;
        uint8_t currentNode = TOS_NODE_ID, minCost = LS_MAX_COST, nextNode = 0, prevNode = 0;
        uint8_t prev[LS_MAX_ROUTES];
        uint8_t cost[LS_MAX_ROUTES];
        bool visited[LS_MAX_ROUTES];
        uint16_t count = numKnownNodes;
        for(i = 0; i < LS_MAX_ROUTES; i++) {
            cost[i] = LS_MAX_COST;
            prev[i] = 0;
            visited[i] = FALSE;
        }
        cost[currentNode] = 0;
        prev[currentNode] = 0;
        while(TRUE) {
            for(i = 1; i < LS_MAX_ROUTES; i++) {
                if(i != currentNode && linkState[currentNode][i] < LS_MAX_COST && cost[currentNode] + linkState[currentNode][i] < cost[i]) {
                    cost[i] = cost[currentNode] + linkState[currentNode][i];
                    prev[i] = currentNode;
                }
            }
            visited[currentNode] = TRUE;            
            minCost = LS_MAX_COST;
            nextNode = 0;
            for(i = 1; i < LS_MAX_ROUTES; i++) {
                if(cost[i] < minCost && !visited[i]) {
                    minCost = cost[i];
                    nextNode = i;
                }
            }
            currentNode = nextNode;
            if(--count == 0) {
                break;
            }
        }
        for(i = 1; i < LS_MAX_ROUTES; i++) {
            if(i == TOS_NODE_ID) {
                continue;
            }
            if(cost[i] != LS_MAX_COST) {
                prevNode = i;
                while(prev[prevNode] != TOS_NODE_ID) {
                    prevNode = prev[prevNode];
                }
                addRoute(i, prevNode, cost[i]);
            } else {
                removeRoute(i);
            }
        }
    }

    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost) {
        if(cost < routingTable[dest].cost) {
            routingTable[dest].nextHop = nextHop;
            routingTable[dest].cost = cost;
            numRoutes++;
        }
    }

    void removeRoute(uint8_t dest) {
        routingTable[dest].nextHop = 0;
        routingTable[dest].cost = LS_MAX_COST;
        numRoutes--;
    }
    event message_t* RouteReceive.receive(message_t* msg, void* payload, uint8_t len){
        pack* myMsg = (pack *) payload;
        uint32_t i;
        if(myMsg->protocol == PROTOCOL_LINKSTATE){
            // dbg(ROUTING_CHANNEL, "Is receive being called?\n");
            if(myMsg->src == TOS_NODE_ID || checkChache(myMsg->src, myMsg->seq)) {
                // dbg(ROUTING_CHANNEL, "Is in cache. Dropping packet...\n");
                return msg;
            } 
            else{
                addToCache(myMsg->src, myMsg->seq, myMsg->dest);
            }
            // If state changed -> rerun djikstra
            if(updateState(myMsg)) {
            
                djikstra();
            }
            // Forward to all neighbors
            call RouteSender.send(*myMsg, AM_BROADCAST_ADDR);
        }
        else{
            call LSRouting.routePacket(myMsg);
        }
        
        return msg;
    }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }                            
}