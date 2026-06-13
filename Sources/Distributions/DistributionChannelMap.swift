public protocol DistributionChannelMap<Channel> {
    associatedtype Channel
    static var zero: Self { get }

    var sum: Float { get }

    subscript(channel: Channel) -> Float { get set }
    consuming func mapKeyedValues(_ transform: (Channel, Float) -> Float) -> Self
}
extension DistributionChannelMap {
    @inlinable public consuming func mapKeys(_ transform: (Channel) -> Float) -> Self {
        self.mapKeyedValues { (channel: Channel, _: Float) in transform(channel) }
    }
}
