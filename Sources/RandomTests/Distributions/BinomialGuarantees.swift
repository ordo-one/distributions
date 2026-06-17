import Random
import Testing

@Suite struct BinomialGuarantees {
    private var random: PseudoRandom

    init() {
        self.random = .init(seed: 10)
    }

    @Test mutating func OutputRange() {
        let n: Int64 = Int64.max - 1
        let distribution = Binomial[n, 1.nextDown]
        for _: Int in 0 ..< 1000 {
            let result: Int64 = distribution.sample(using: &self.random.generator)
            #expect(result >= 0)
            #expect(result <= n)
        }
    }
}
