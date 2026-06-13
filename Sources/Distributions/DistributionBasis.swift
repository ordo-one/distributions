import Assert
import Random

/// Pre-processed, sorted, and compacted distribution targets.
@frozen public struct DistributionBasis<Channel, Target> where Channel: DistributionChannel {
    @usableFromInline let weightCDF: [Float]
    @usableFromInline let targets: [(channel: Channel, target: Target, weight: Float)]

    @inlinable init(
        weightCDF: [Float],
        targets: [(channel: Channel, target: Target, weight: Float)]
    ) {
        self.weightCDF = weightCDF
        self.targets = targets
    }
}
extension DistributionBasis {
    @inlinable public static func create(
        from targets: [(channel: Channel, target: Target, weight: Float)],
        rescale: (Channel) -> Float
    ) -> Self? {
        // filter zeros and sort ascending (fixes sparse arrays & float precision)
        var targets: [(channel: Channel, target: Target, weight: Float)] = targets.filter {
            $0.weight > 0
        }

        targets.sort { $0.weight < $1.weight }

        guard
        let last: Int = targets.indices.last else {
            return nil
        }

        var totalsUnnormalized: Channel.InlineMap = .zero
        for (channel, _, weight): (Channel, _, Float) in targets {
            totalsUnnormalized[channel] += weight
        }

        let totals: Channel.InlineMap = totalsUnnormalized.mapKeys { rescale($0) }
        let scales: Channel.InlineMap = totalsUnnormalized.mapKeyedValues { rescale($0) / $1 }
        for i: Int in targets.indices {
            {
                $0.weight *= scales[$0.channel]
                #assert($0.weight >= 0, "target weight must not be negative!!!")
            } (&targets[i])
        }

        let total: Float = totals.sum
        let count: Int = targets.count
        let remainder: Int = count & 3
        let countPadded: Int = remainder == 0 ? count : count + (4 - remainder)

        var weightCDF: [Float] = []
        ;   weightCDF.reserveCapacity(countPadded)

        var sum: Float = 0
        for i: Int in targets.startIndex ..< last {
            sum = min(1, sum + targets[i].weight / total)
            weightCDF.append(sum)
        }
        // mathematically lock the tail and pad for SIMD
        // `targets` is unpadded, but its tail should never be accessed
        for _: Int in last ..< countPadded {
            weightCDF.append(1)
        }

        return .init(weightCDF: weightCDF, targets: targets)
    }
}

extension DistributionBasis {
    /// Distributes counts and accumulates them into a pre-existing global buffer.
    @inlinable public func distribute<Source>(
        sources: [Source],
        count: (Source) -> Int64,
        using random: inout PseudoRandom,
        yield: (Channel, Target, Int32) -> ()
    ) {
        let chunks: Int = self.weightCDF.count / 4
        for source: Source in sources {
            let N: SIMD4<Float> = .init(repeating: Float.init(count(source)))
            let u: SIMD4<Float> = .init(
                repeating: Float.random(in: 0 ..< 1, using: &random.generator)
            )
            var carry: Int32 = 0
            // uninterrupted simd hot loop
            for c: Int in 0 ..< chunks {
                let i: Int = c * 4
                let weightCDF: SIMD4<Float> = .init(
                    self.weightCDF[i],
                    self.weightCDF[i + 1],
                    self.weightCDF[i + 2],
                    self.weightCDF[i + 3]
                )

                let n: SIMD4<Int32> = .init((N * weightCDF) + u)
                let m: SIMD4<Int32> = .init(carry, n[0], n[1], n[2])

                carry = n[3]

                let k: SIMD4<Int32> = n &- m

                if  k.x > 0 {
                    let (channel, target, _): (Channel, Target, _) = self.targets[i]
                    yield(channel, target, k.x)
                }
                if  k.y > 0 {
                    let (channel, target, _): (Channel, Target, _) = self.targets[i + 1]
                    yield(channel, target, k.y)
                }
                if  k.z > 0 {
                    let (channel, target, _): (Channel, Target, _) = self.targets[i + 2]
                    yield(channel, target, k.z)
                }
                if  k.w > 0 {
                    let (channel, target, _): (Channel, Target, _) = self.targets[i + 3]
                    yield(channel, target, k.w)
                }
            }
        }
    }
}
