import RealModule

/// Binomial distribution implementation with optimizations for large n values
@frozen public struct Binomial {
    @inlinable static var thresholdNormal: Double { 10_000 }
    @inlinable static var thresholdBTPE: Double { 30 }
    @inlinable static var thresholdRare: Double { 0.05 }

    private static var iterations: Int { 200 }

    public let n: Int64
    public let p: Double

    @inlinable init(n: Int64, p: Double) {
        self.n = n
        self.p = p
    }
}
extension Binomial {
    @inlinable public static subscript(n: Int64, p: Double) -> Self {
        guard p.isFinite else {
            fatalError("Binomial.subscript cannot be called with `p` = \(p)")
        }
        return .init(n: n, p: p)
    }
}
extension Binomial {
    /// Sample the binomial distribution. As long as ``n`` is non-negative, the result is
    /// guaranteed to lie in the range `0 ... n`.
    @inlinable public func sample(using generator: inout some RandomNumberGenerator) -> Int64 {
        if self.p <= 0 { return 0 }
        if self.p >= 1 { return self.n }
        if self.n <= 0 { return 0 }

        let n: Double = Double.init(self.n)
        let μ: Double = n * self.p
        let q: Double = 1 - self.p
        let σ²: Double = μ * q
        if  σ² > Self.thresholdNormal {
            let σ: Double = .sqrt(σ²)
            let u: Double = .random(in: 0 ... 1, using: &generator)
            let z: Double = Normal.cdfInverse(u)
            let x: Double = (μ + z * σ).rounded()
            if  x >= n {
                return self.n
            } else if
                x <= 0 {
                return 0
            } else {
                return Int64.init(x)
            }
        } else if q < self.p {
            let m: Int64
            if  σ² >= Self.thresholdBTPE {
                m = Self.sampleBTPE(
                    n: self.n,
                    μ: n * q,
                    σ: .sqrt(σ²),
                    p: q,
                    q: self.p,
                    using: &generator
                )
            } else if q < Self.thresholdRare {
                m = Self.sampleGeometric(n: self.n, p: q, using: &generator)
            } else {
                m = Self.cdfInverse(
                    n: self.n,
                    μ: n * q,
                    σ²: σ²,
                    p: q,
                    q: self.p,
                    u: .random(in: 0 ... 1, using: &generator),
                )
            }
            return self.n - m
        } else {
            let m: Int64
            if  σ² >= Self.thresholdBTPE {
                m = Self.sampleBTPE(
                    n: self.n,
                    μ: μ,
                    σ: .sqrt(σ²),
                    p: self.p,
                    q: q,
                    using: &generator
                )
            } else if p < Self.thresholdRare {
                m = Self.sampleGeometric(n: self.n, p: self.p, using: &generator)
            } else {
                m = Self.cdfInverse(
                    n: self.n,
                    μ: μ,
                    σ²: σ²,
                    p: self.p,
                    q: q,
                    u: .random(in: 0 ... 1, using: &generator),
                )
            }
            return m
        }
    }
}
extension Binomial {
    // geometric jumps
    @inlinable static func sampleGeometric(
        n: Int64,
        p: Double,
        using generator: inout some RandomNumberGenerator
    ) -> Int64 {
        let scale: Double = 1 / Double.log(onePlus: -p)

        var successes: Int64 = 0
        var remaining: Int64 = n

        repeat {
            let u: Double = .random(in: 0 ... 1, using: &generator)
            // calculate number of failures before the next success
            // this number may be very large, so it should not be cast to `Int64` eagerly
            let jump: Double = Double.log(u) * scale
            if  jump >= Double.init(remaining) {
                break
            } else {
                successes += 1
                remaining -= 1
                remaining -= Int64.init(jump)
            }
        } while remaining > 0
        return successes
    }
}
extension Binomial {
    // Theoretical binomial probability.
    @inlinable public func pdf(_ k: Int64) -> Double {
        if  self.p <= 0 {
            return k == 0 ? 1 : 0
        }
        if  self.p >= 1 {
            return k == self.n ? 1 : 0
        }

        guard 0 ... self.n ~= k else {
            return 0
        }

        let l: Double = .init(self.n - k)
        let n: Double = .init(self.n)
        let k: Double = .init(k)
        let q: Double = 1 - self.p
        /// this calculation done in log space to avoid numerical saturation
        let nCk: Double = Double.logGamma(n + 1)
            - Double.logGamma(k + 1)
            - Double.logGamma(l + 1)
        return Double.exp(nCk + k * Double.log(self.p) + l * Double.log(q))
    }
}
extension Binomial {
    /// Executes the BTPE (Binomial, Triangle, Parallelogram, Exponential) Algorithm.
    /// Guarantees exact statistical accuracy in O(1) expected time for variance >= 30.
    @inlinable static func sampleBTPE(
        n: Int64,
        μ: Double,
        σ: Double,
        p: Double,
        q: Double,
        using generator: inout some RandomNumberGenerator
    ) -> Int64 {
        /// continuous mode
        let peak: Double = μ + p
        /// discrete mode
        let mode: Double = peak.rounded(.down)
        let width: Double = Double.init(Int64.init(2.195 * σ - 4.6 * q)) + 0.5

        /// defines the horizontal dimensions of the triangular region, and the two
        /// parallelograms stacked above it on either side
        let envelope: (l: Double, center: Double, r: Double)

        envelope.center = mode + 0.5
        envelope.l = envelope.center - width
        envelope.r = envelope.center + width

        /// dictates the vertical height of the parallelogram (region 2) that sits on top of
        /// the triangle (region 1), the exact formula is a mathematically derived upper bound
        /// created by Kachitvichyanukul and Schmeiser
        let c: Double = 0.134 + 20.5 / (15.3 + mode)

        /// tangent slopes of the exponential tails
        let slope: (l: Double, r: Double) = (
            l: (peak - envelope.l) / (peak - envelope.l * p),
            r: (envelope.r - peak) / (envelope.r * q)
        )
        let λ: (l: Double, r: Double) = (
            l: slope.l * (1 + 0.5 * slope.l),
            r: slope.r * (1 + 0.5 * slope.r)
        )

        let area: (Double, Double, total: Double)
        // area of the triangle, plus the two parallelograms (looks like a house)
        area.0 = width * (1 + 2 * c)
        // area of the triangle, plus parallelograms, plus the left tail
        area.1 = area.0 + c / λ.l
        // area of the triangle, plus parallelograms, plus both tails
        area.2 = area.1 + c / λ.r

        var logCache: (scale: Double, odds: Double)? = nil
        while true {
            /// v in the range (0, 1] to avoid log(0)
            let v: Double = 1 - Double.random(in: 0 ..< 1, using: &generator)
            let u: Double = area.total * Double.random(in: 0 ..< 1, using: &generator)

            let k: Int64
            let y: Double

            if  u <= width {
                // region 1: triangle, automatically accepted, point generated by
                // transforming uniform random point into triangle
                return Int64.init(envelope.center - width * v + u)
            } else if u <= area.0 {
                // region 2: parallelograms
                let x: Double = envelope.l + (u - width) / c
                if  x < 0 {
                    continue
                }

                k = Int64.init(x)

                guard k <= n else {
                    // this point won’t possibly be accepted
                    continue
                }

                /// this is the height of the triangle, to which a random uniform offset is
                /// added to generate a point in the parallelogram
                let h: Double = 1 - abs(envelope.center - x) / width
                y = h + v * c

                guard y > 0 else {
                    continue
                }
            } else if u <= area.1 {
                // region 3: left exponential tail
                let x: Double = envelope.l + Double.log(v) / λ.l
                if  x < 0 {
                    continue
                }

                k = Int64.init(x)
                y = v * (u - area.0) * λ.l
            } else {
                // region 4: right exponential tail
                let x: Double = envelope.r - Double.log(v) / λ.r
                if  x >= Double.init(Int64.max) {
                    continue
                }

                k = Int64.init(x)

                guard k <= n else {
                    continue
                }

                y = v * (u - area.1) * λ.r
            }

            // Compares the generated point mathematically against the true Binomial probability
            let x: Double = Double.init(k)
            let n: Double = Double.init(n)
            // note that there is sometimes a “squeeze test” that appears here, as was written
            // in the original paper, but it was later revealed to be incorrect
            let log: (scale: Double, odds: Double)
            if  let logCache: (scale: Double, odds: Double) {
                log = logCache
            } else {
                /// these are heavy computations, and they are only used 20 to 25 percent of the
                /// time, so we compute them lazily and then cache the result for later
                let success: Double = .logGamma(mode + 1)
                let failure: Double = .logGamma(n - mode + 1)
                log = (scale: success + failure, odds: Double.log(p / q))
                logCache = log
            }

            let pdf: Double = log.scale
                + (x - mode) * log.odds
                - Double.logGamma(x + 1)
                - Double.logGamma(n - x + 1)

            if  pdf >= Double.log(y) {
                return k
            }
        }
    }
}
extension Binomial {
    /// Find the binomial value using binary search on the CDF
    @usableFromInline static func cdfInverse(
        n: Int64,
        μ: Double,
        σ²: Double,
        p: Double,
        q: Double,
        u: Double,
    ) -> Int64 {
        let n: (i: Int64, f: Double) = (n, Double.init(n))

        // Use quantile function of normal distribution
        let guess: Int64

        let z: Double = Normal.cdfInverse(u)
        let x: Double = (μ + z * Double.sqrt(σ²)).rounded()
        if  x >= n.f {
            guess = n.i
        } else if x <= 0 {
            guess = 0
        } else {
            guess = Int64.init(x)
        }

        // For smaller n, continue with binary search for greater accuracy
        // Start with our initial guess from normal approximation
        var y: Double = Self.cdf(n: n.i, k: guess, p: p, q: q)
        if abs(y - u) < 1e-10 {
            return guess
        }

        // Binary search
        var bound: (min: Int64, max: Int64) = u < y ? (0, guess) : (guess, n.i)

        // Actual binary search
        while bound.min + 1 < bound.max {
            let guess: Int64 = (bound.min + bound.max) / 2

            y = Self.cdf(n: n.i, k: guess, p: p, q: q)

            if  u <= y {
                bound.max = guess
            } else {
                bound.min = guess
            }
        }

        // Final check
        y = Self.cdf(n: n.i, k: bound.min, p: p, q: q)
        return u <= y ? bound.min : bound.max
    }

    /// Calculate the CDF of a binomial distribution
    /// Uses the relationship with the incomplete beta function
    private static func cdf(n: Int64, k: Int64, p: Double, q: Double) -> Double {
        if k < 0 { return 0 }
        if k >= n { return 1 }

        // The binomial CDF is related to the incomplete beta function:
        // CDF(k; n, p) = I_{1-p}(n-k, k+1)
        // where I_x(a,b) is the regularized incomplete beta function

        // We know `k + 1` will never overflow, because it is less than `n`.
        return Self.I(a: Double.init(n - k), b: Double.init(k + 1), p: p, q: q)
    }

    /// Compute the regularized incomplete beta function
    private static func I(a: Double, b: Double, p: Double, q: Double) -> Double {
        // Use continued fraction representation for numerical stability
        // First calculate the factor x^a * (1-x)^b / (a*Beta(a,b))
        let bt: Double = Double.exp(
            Double.logGamma(a + b) -
            Double.logGamma(a) -
            Double.logGamma(b) +
            Double.log(q) * a +
            Double.log(p) * b
        )

        if q < (a + 1.0) / (a + b + 2.0) {
            // Use continued fraction directly
            return     bt * Self.fraction(a: a, b: b, x: q) / a
        } else {
            // Use symmetry relation: I_x(a,b) = 1 - I_{1-x}(b,a)
            return 1 - bt * Self.fraction(a: b, b: a, x: p) / b
        }
    }

    /// Compute the continued fraction part of the incomplete beta function
    private static func fraction(a: Double, b: Double, x: Double) -> Double {
        // Implementation of the modified Lentz algorithm for continued fractions
        let fpmin: Double = 1e-30
        let ε: Double = 1e-15

        let qab: Double = a + b
        let qap: Double = a + 1
        let qam: Double = a - 1

        var c: Double = 1
        var d: Double = 1 - qab * x / qap
        if abs(d) < fpmin { d = fpmin }
        d = 1 / d
        var h: Double = d

        for m: Int in 1 ... Self.iterations {
            let m: (Void, Double, Double) = ((), Double.init(m), Double.init(m * 2))
            let aa: Double = m.1 * (b - m.1) * x / ((qam + m.2) * (a + m.2))

            // Even step
            d = 1 + aa * d
            if abs(d) < fpmin { d = fpmin }
            c = 1 + aa / c
            if abs(c) < fpmin { c = fpmin }
            d = 1 / d
            h *= d * c

            // Odd step
            let bb: Double = -(a + m.1) * (qab + m.1) * x / ((a + m.2) * (qap + m.2))

            d = 1 + bb * d
            if abs(d) < fpmin { d = fpmin }
            c = 1 + bb / c
            if abs(c) < fpmin { c = fpmin }
            d = 1 / d
            let del: Double = d * c
            h *= del

            // Check for convergence
            if abs(del - 1) <= ε {
                return h
            }
        }

        // If we reached here, we didn't converge - return best approximation
        return h
    }
}
