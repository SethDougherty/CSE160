// Configuration

configuration LSRoutingC{
	provides interface LSRouting;
}

implementation{
	components LSRoutingP;
	components new TimerMilliC() as RouteTimer;
	components new SimpleSendC(150);
	components new AMReceiverC(150);
	
	// External Wiring
	LSRouting = LSRoutingP.LSRouting;

	// Internal Wiring
	LSRoutingP.RouteSender -> SimpleSendC;
	LSRoutingP.RouteReceive -> AMReceiverC;
	LSRoutingP.RouteTimer -> RouteTimer;
	components NeighborDiscoveryC;
	LSRoutingP.NeighborDiscovery -> NeighborDiscoveryC;
	

} 