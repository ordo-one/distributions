import Assert
import Random

/// Pre-processed, sorted, and compacted distribution targets.
@frozen public struct DistributionBasis<Target> {
    @usableFromInline let weightCDF: [Float]
    @usableFromInline let targets: [(target: Target, weight: Float)]

    @inlinable init(weightCDF: [Float], targets: [(target: Target, weight: Float)]) {
        self.weightCDF = weightCDF
        self.targets = targets
    }
}
extension DistributionBasis where Target: DistributionTarget {
    /// Create a distribution basis from weighted targets which belong to normalization classes.
    ///
    /// -   Parameter targets:
    ///     The list of weighted targets, each of which is tagged with a
    ///     ``DistributionTarget/channel`` indicating its normalization class.
    ///     By default, the array provided will be reused for internal computations.
    ///
    /// -   Parameter rescale:
    ///     A closure that returns the total class weight given a channel identifier. All
    ///     targets included in this channel will have their weights rescaled such that they
    ///     sum to the value returned by the closure.
    ///
    /// -   Returns:
    ///     An instance of ``DistributionBasis``, or nil if `targets` contains no nonzero
    ///     weights.
    ///
    /// If all targets belong to a single normalization class, ``create(from:)`` may be called
    /// instead, which avoids the need for a ``DistributionTarget``-witnessing type, and also
    /// saves some intermediate calculations.
    @inlinable public static func create(
        from targets: consuming [(target: Target, weight: Float)],
        rescale: (Target.Channel) -> Float
    ) -> Self? {
        // filter zeros and sort ascending (fixes sparse arrays & float precision)
        targets.removeAll { $0.weight <= 0 }

        if  targets.isEmpty {
            return nil
        } else {
            targets.sort { $0.weight < $1.weight }
            return .create(ordered: &targets, rescale: rescale)
        }
    }

    @inline(always) @inlinable static func create(
        ordered targets: inout [(target: Target, weight: Float)],
        rescale: (Target.Channel) -> Float
    ) -> Self {
        var totalsUnnormalized: Target.ChannelMap = .zero
        for (target, weight): (Target, Float) in targets {
            totalsUnnormalized[target.channel] += weight
        }

        let totals: Target.ChannelMap = totalsUnnormalized.mapKeys { rescale($0) }
        let scales: Target.ChannelMap = totalsUnnormalized.mapKeyedValues { rescale($0) / $1 }
        for i: Int in targets.indices {
            {
                $0.weight *= scales[$0.target.channel]
                #assert($0.weight >= 0, "target weight must not be negative!!!")
            } (&targets[i])
        }

        let total: Float = totals.sum
        return .create(ordered: targets) { $0 / total }
    }
}
extension DistributionBasis {
    /// Create a distribution basis from weighted targets which are all assumed to be part of a
    /// single normalization class.
    ///
    /// -   Parameter targets:
    ///     The list of weighted targets.
    ///     By default, the array provided will be reused for internal computations.
    ///
    /// -   Returns:
    ///     An instance of ``DistributionBasis``, or nil if `targets` contains no nonzero
    ///     weights.
    @inlinable public static func create(
        from targets: consuming [(target: Target, weight: Float)],
    ) -> Self? {
        targets.removeAll { $0.weight <= 0 }

        if  targets.isEmpty {
            return nil
        } else {
            targets.sort { $0.weight < $1.weight }
            return .create(ordered: &targets)
        }

    }

    @inline(always) @inlinable static func create(
        ordered targets: inout [(target: Target, weight: Float)],
    ) -> Self {
        var total: Float = .zero
        for (_, weight): (Target, Float) in targets {
            total += weight
        }

        let scale: Float = 1 / total
        for i: Int in targets.indices {
            {
                $0.weight *= scale
                #assert($0.weight >= 0, "target weight must not be negative!!!")
            } (&targets[i])
        }

        return .create(ordered: targets) { $0 }
    }

    @inline(always) @inlinable static func create(
        ordered targets: [(target: Target, weight: Float)],
        normalize: (_ weight: Float) -> Float
    ) -> Self {
        let last: Int = targets.index(before: targets.endIndex)
        let count: Int = targets.count
        let remainder: Int = count & 3
        let countPadded: Int = remainder == 0 ? count : count + (4 - remainder)

        var weightCDF: [Float] = []
        ;   weightCDF.reserveCapacity(countPadded)

        var sum: Float = 0
        for i: Int in targets.startIndex ..< last {
            sum = min(1, sum + normalize(targets[i].weight))
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
        yield: (Target, Int32) -> ()
    ) {
        let chunks: Int = self.chunks
        for source: Source in sources {
            self.distribute(
                count: count(source),
                chunks: chunks,
                using: &random,
                yield: yield
            )
        }
    }

    @inlinable public func distribute(
        count: Int64,
        using random: inout PseudoRandom,
        yield: (Target, Int32) -> ()
    ) {
        self.distribute(
            count: count,
            chunks: self.chunks,
            using: &random,
            yield: yield
        )
    }
}
extension DistributionBasis {
    @inlinable var chunks: Int { self.weightCDF.count / 4 }
    @inlinable func distribute(
        count: Int64,
        chunks: Int,
        using random: inout PseudoRandom,
        yield: (Target, Int32) -> ()
    ) {
        let N: SIMD4<Float> = .init(repeating: Float.init(count))
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
                yield(self.targets[i].target, k.x)
            }
            if  k.y > 0 {
                yield(self.targets[i + 1].target, k.y)
            }
            if  k.z > 0 {
                yield(self.targets[i + 2].target, k.z)
            }
            if  k.w > 0 {
                yield(self.targets[i + 3].target, k.w)
            }
        }
    }
}
