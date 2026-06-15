public protocol DistributionTarget<Channel> {
    associatedtype ChannelMap: DistributionChannelMap<Channel>
    associatedtype Channel

    var channel: Channel { get }
}
