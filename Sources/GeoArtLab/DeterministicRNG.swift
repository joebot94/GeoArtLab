import Foundation

struct DeterministicRNG: RandomNumberGenerator {
    private(set) var state: UInt64

    init(seed: UInt64) {
        // Avoid zero state collapse for xorshift*.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 0x2545F4914F6CDD1D
    }

    mutating func nextUnitDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let t = nextUnitDouble()
        return range.lowerBound + ((range.upperBound - range.lowerBound) * t)
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound <= range.upperBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        let value = next() % span
        return range.lowerBound + Int(value)
    }

    func spawn(stream: UInt64) -> DeterministicRNG {
        DeterministicRNG(seed: state &+ (0x9E3779B97F4A7C15 &* (stream &+ 1)))
    }
}
