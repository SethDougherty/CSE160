// Configuration

configuration NeighborDiscoveryC{
	provides interface NeighborDiscovery;
}

implementation{
	components NeighborDiscoveryP;
	components new TimerMilliC() as delayTimer;
	components new SimpleSendC(50);
	components new AMReceiverC(50);
	
	// External Wiring
	NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

	// Internal Wiring
	NeighborDiscoveryP.NeighborSender -> SimpleSendC;
	NeighborDiscoveryP.NeighborReceive -> AMReceiverC;
	NeighborDiscoveryP.delayTimer -> delayTimer;

	components LSRoutingC;
    NeighborDiscoveryP.LSRouting -> LSRoutingC;

} 