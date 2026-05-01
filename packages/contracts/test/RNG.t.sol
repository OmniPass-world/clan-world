// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {RNG} from "../src/lib/RNG.sol";

contract RNGTest is Test {
    bytes32 internal constant SEED = keccak256("clanworld.test.seed");
    uint256 internal constant DOMAIN_A = uint256(keccak256("clanworld.mission.resolve.v1"));
    uint256 internal constant DOMAIN_B = uint256(keccak256("clanworld.bandit.spawn.v1"));

    function test_determinism_allHelpers() public pure {
        uint256[] memory weights = new uint256[](4);
        weights[0] = 1;
        weights[1] = 3;
        weights[2] = 0;
        weights[3] = 6;

        assertEq(RNG.rngUniform(SEED, DOMAIN_A, 7), RNG.rngUniform(SEED, DOMAIN_A, 7), "uniform deterministic");
        assertEq(RNG.rngBounded(SEED, DOMAIN_A, 7, 10), RNG.rngBounded(SEED, DOMAIN_A, 7, 10), "bounded deterministic");
        assertEq(RNG.rngBool(SEED, DOMAIN_A, 7), RNG.rngBool(SEED, DOMAIN_A, 7), "bool deterministic");
        assertEq(
            RNG.rngWeightedPick(SEED, DOMAIN_A, 7, weights),
            RNG.rngWeightedPick(SEED, DOMAIN_A, 7, weights),
            "weighted deterministic"
        );

        uint8[] memory first = RNG.rngShuffle(SEED, DOMAIN_A, 7, 12);
        uint8[] memory second = RNG.rngShuffle(SEED, DOMAIN_A, 7, 12);
        _assertSameUint8Array(first, second);
    }

    function test_domainSeparation_outputsDifferAcrossDomains() public pure {
        uint256 uniformDiffs = 0;
        uint256 boundedDiffs = 0;
        uint256 boolDiffs = 0;
        uint256 weightedDiffs = 0;
        uint256 shuffleDiffs = 0;

        uint256[] memory weights = new uint256[](10);
        for (uint256 i = 0; i < weights.length; i++) {
            weights[i] = 1;
        }

        for (uint256 nonce = 0; nonce < 32; nonce++) {
            if (RNG.rngUniform(SEED, DOMAIN_A, nonce) != RNG.rngUniform(SEED, DOMAIN_B, nonce)) {
                uniformDiffs++;
            }
            if (RNG.rngBounded(SEED, DOMAIN_A, nonce, 10_000) != RNG.rngBounded(SEED, DOMAIN_B, nonce, 10_000)) {
                boundedDiffs++;
            }
            if (RNG.rngBool(SEED, DOMAIN_A, nonce) != RNG.rngBool(SEED, DOMAIN_B, nonce)) {
                boolDiffs++;
            }
            if (
                RNG.rngWeightedPick(SEED, DOMAIN_A, nonce, weights)
                    != RNG.rngWeightedPick(SEED, DOMAIN_B, nonce, weights)
            ) {
                weightedDiffs++;
            }
            if (!_sameUint8Array(RNG.rngShuffle(SEED, DOMAIN_A, nonce, 8), RNG.rngShuffle(SEED, DOMAIN_B, nonce, 8))) {
                shuffleDiffs++;
            }
        }

        assertGe(uniformDiffs, 30, "uniform domains should diverge");
        assertGe(boundedDiffs, 30, "bounded domains should diverge");
        assertGe(boolDiffs, 8, "bool domains should diverge often enough");
        assertGe(weightedDiffs, 20, "weighted domains should diverge");
        assertGe(shuffleDiffs, 20, "shuffle domains should diverge");
    }

    function test_rngUniform_distributionVariationAcrossNonces() public pure {
        uint256 minValue = type(uint256).max;
        uint256 maxValue = 0;

        for (uint256 nonce = 0; nonce < 100; nonce++) {
            uint256 value = RNG.rngUniform(SEED, DOMAIN_A, nonce);
            if (value < minValue) {
                minValue = value;
            }
            if (value > maxValue) {
                maxValue = value;
            }
        }

        assertGt(maxValue - minValue, type(uint256).max / 2, "uniform range should be non-trivial");
    }

    function test_rngBounded_distributionForMaxTen() public pure {
        uint256[10] memory buckets;

        for (uint256 nonce = 0; nonce < 1000; nonce++) {
            uint256 value = RNG.rngBounded(SEED, DOMAIN_A, nonce, 10);
            buckets[value]++;
        }

        for (uint256 i = 0; i < buckets.length; i++) {
            assertGe(buckets[i], 50, "bucket should get enough hits");
        }
    }

    function test_rngBounded_powerOfTwoBoundsUseFirstSample() public pure {
        _assertPowerOfTwoBoundUsesFirstSample(uint256(1) << 200);
        _assertPowerOfTwoBoundUsesFirstSample(uint256(1) << 255);
    }

    function test_rngBounded_distributionForMax256() public pure {
        uint256[256] memory buckets;
        uint256 hitBuckets = 0;

        for (uint256 nonce = 0; nonce < 1000; nonce++) {
            uint256 value = RNG.rngBounded(SEED, DOMAIN_A, nonce, 256);
            assertLt(value, 256, "value must stay in range");

            if (buckets[value] == 0) {
                hitBuckets++;
            }
            buckets[value]++;
        }

        assertGe(hitBuckets, 245, "nearly every bucket should be represented");
        for (uint256 i = 0; i < buckets.length; i++) {
            assertLe(buckets[i], 12, "bucket should not dominate");
        }
    }

    function test_rngBool_distribution() public pure {
        uint256 trueCount = 0;

        for (uint256 nonce = 0; nonce < 1000; nonce++) {
            if (RNG.rngBool(SEED, DOMAIN_A, nonce)) {
                trueCount++;
            }
        }

        assertGe(trueCount, 400, "true count too low");
        assertLe(trueCount, 600, "true count too high");
    }

    function test_rngWeightedPick_degenerateAndWeightedCases() public pure {
        uint256[] memory empty = new uint256[](0);
        assertEq(RNG.rngWeightedPick(SEED, DOMAIN_A, 0, empty), 0, "empty weights return 0");

        uint256[] memory zeros = new uint256[](3);
        assertEq(RNG.rngWeightedPick(SEED, DOMAIN_A, 0, zeros), 0, "zero-total weights return 0");

        uint256[] memory single = new uint256[](1);
        single[0] = 42;
        for (uint256 nonce = 0; nonce < 100; nonce++) {
            assertEq(RNG.rngWeightedPick(SEED, DOMAIN_A, nonce, single), 0, "single non-zero weight always wins");
        }

        uint256[] memory equal = new uint256[](4);
        equal[0] = 1;
        equal[1] = 1;
        equal[2] = 1;
        equal[3] = 1;
        uint256[4] memory equalCounts;
        for (uint256 nonce = 0; nonce < 1000; nonce++) {
            equalCounts[RNG.rngWeightedPick(SEED, DOMAIN_A, nonce, equal)]++;
        }
        for (uint256 i = 0; i < equalCounts.length; i++) {
            assertGe(equalCounts[i], 150, "equal buckets should all be represented");
        }

        uint256[] memory zeroFront = new uint256[](4);
        zeroFront[0] = 0;
        zeroFront[1] = 0;
        zeroFront[2] = 7;
        zeroFront[3] = 3;
        uint256[4] memory zeroFrontCounts;
        for (uint256 nonce = 0; nonce < 1000; nonce++) {
            zeroFrontCounts[RNG.rngWeightedPick(SEED, DOMAIN_A, nonce, zeroFront)]++;
        }
        assertEq(zeroFrontCounts[0], 0, "zero-weight index 0 should not be picked");
        assertEq(zeroFrontCounts[1], 0, "zero-weight index 1 should not be picked");
        assertGe(zeroFrontCounts[2], 600, "weight 7 bucket should dominate");
        assertLe(zeroFrontCounts[2], 800, "weight 7 bucket should stay plausible");
        assertGe(zeroFrontCounts[3], 200, "weight 3 bucket should be represented");
        assertLe(zeroFrontCounts[3], 400, "weight 3 bucket should stay plausible");
    }

    function test_rngShuffle_permutationAndDeterminism() public pure {
        uint256 n = 16;
        uint8[] memory permutation = RNG.rngShuffle(SEED, DOMAIN_A, 99, n);
        uint8[] memory repeat = RNG.rngShuffle(SEED, DOMAIN_A, 99, n);

        _assertSameUint8Array(permutation, repeat);
        _assertPermutation(permutation, n);
    }

    function _assertPermutation(uint8[] memory permutation, uint256 n) internal pure {
        assertEq(permutation.length, n, "length mismatch");

        bool[] memory seen = new bool[](n);
        for (uint256 i = 0; i < permutation.length; i++) {
            uint256 value = uint256(permutation[i]);
            assertLt(value, n, "value out of range");
            assertFalse(seen[value], "duplicate value");
            seen[value] = true;
        }

        for (uint256 i = 0; i < n; i++) {
            assertTrue(seen[i], "missing value");
        }
    }

    function _assertPowerOfTwoBoundUsesFirstSample(uint256 max) internal pure {
        for (uint256 nonce = 0; nonce < 100; nonce++) {
            uint256 firstSample = uint256(keccak256(abi.encodePacked(DOMAIN_A, SEED, nonce, max, uint256(0))));
            assertEq(RNG.rngBounded(SEED, DOMAIN_A, nonce, max), firstSample & (max - 1), "should not reject");
        }
    }

    function _assertSameUint8Array(uint8[] memory a, uint8[] memory b) internal pure {
        assertTrue(_sameUint8Array(a, b), "arrays differ");
    }

    function _sameUint8Array(uint8[] memory a, uint8[] memory b) internal pure returns (bool) {
        if (a.length != b.length) {
            return false;
        }

        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }

        return true;
    }
}
