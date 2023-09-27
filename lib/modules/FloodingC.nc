configuration FloodingC{
	provides interface Flooding;
}

implementation{
	components FloodingP;
	components new SimpleSendC(100);
	components new AMReceiverC(100);

	Flooding = FloodingP.Flooding;

	FloodingP.InternalSender -> SimpleSendC;
	FloodingP.InternalReceiver -> AMReceiverC;
	
	components NeighborDiscoveryC;
	FloodingP.NeighborDiscovery -> NeighborDiscoveryC;
} 