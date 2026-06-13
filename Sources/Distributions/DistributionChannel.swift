public protocol DistributionChannel {
    associatedtype InlineMap: DistributionChannelMap<Self>
}
