<div align="center">

🃏 &nbsp; **distributions** &nbsp; 🃏

a portable, Foundation-free library for working with statistical distributions in Swift, with a focus on efficient sampling and random number generation

[documentation](https://swiftinit.org/docs/package-distributions) ·
[license](LICENSE)

</div>


## Requirements

The package-distributions library requires Swift 6.1 or later.


<!-- DO NOT EDIT BELOW! AUTOSYNC CONTENT [STATUS TABLE] -->
| Platform | Status |
| -------- | ------ |
| 💬 Documentation | [![Status](https://raw.githubusercontent.com/ordo-one/distributions/refs/badges/ci/Documentation/_all/status.svg)](https://github.com/ordo-one/distributions/actions/workflows/Documentation.yml) |
| 🐧 Linux | [![Status](https://raw.githubusercontent.com/ordo-one/distributions/refs/badges/ci/Tests/Linux/status.svg)](https://github.com/ordo-one/distributions/actions/workflows/Tests.yml) |
| 🍏 Darwin | [![Status](https://raw.githubusercontent.com/ordo-one/distributions/refs/badges/ci/Tests/macOS/status.svg)](https://github.com/ordo-one/distributions/actions/workflows/Tests.yml) |
| 🍏 Darwin (iOS) | [![Status](https://raw.githubusercontent.com/ordo-one/distributions/refs/badges/ci/Tests/iOS/status.svg)](https://github.com/ordo-one/distributions/actions/workflows/Tests.yml) |
| 🍏 Darwin (tvOS) | [![Status](https://raw.githubusercontent.com/ordo-one/distributions/refs/badges/ci/Tests/tvOS/status.svg)](https://github.com/ordo-one/distributions/actions/workflows/Tests.yml) |
| 🍏 Darwin (visionOS) | [![Status](https://raw.githubusercontent.com/ordo-one/distributions/refs/badges/ci/Tests/visionOS/status.svg)](https://github.com/ordo-one/distributions/actions/workflows/Tests.yml) |
| 🍏 Darwin (watchOS) | [![Status](https://raw.githubusercontent.com/ordo-one/distributions/refs/badges/ci/Tests/watchOS/status.svg)](https://github.com/ordo-one/distributions/actions/workflows/Tests.yml) |
<!-- DO NOT EDIT ABOVE! AUTOSYNC CONTENT [STATUS TABLE] -->

[Check deployment minimums](https://swiftinit.org/docs/package-distributions#ss:platform-requirements)


## Examples

```swift
import Random

var random: PseudoRandom = .init(seed: 13)

let binomial: (Int64, Int64, Int64, Int64) = (
    Binomial[10, 0.2].sample(using: &random.generator),
    Binomial[10, 0.2].sample(using: &random.generator),
    Binomial[10, 0.2].sample(using: &random.generator),
    Binomial[10, 0.2].sample(using: &random.generator),
)

// Generated binomial samples: (1, 4, 2, 4)

let normal: (Double, Double, Double, Double) = (
    Normal[0, 1].sample(using: &random.generator),
    Normal[0, 1].sample(using: &random.generator),
    Normal[0, 1].sample(using: &random.generator),
    Normal[0, 1].sample(using: &random.generator),
)

// Generated normal samples: (1.031, 1.201, -1.607, -0.243)
```
