// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title ClanWorld domain-separated RNG helpers
/// @notice Cheap deterministic randomness derived from a published per-tick seed.
library RNG {
    uint256 internal constant DOMAIN_MISSION_RESOLUTION = uint256(keccak256("clanworld.mission.resolve.v1"));
    uint256 internal constant DOMAIN_BANDIT_SPAWN = uint256(keccak256("clanworld.bandit.spawn.v1"));
    uint256 internal constant DOMAIN_MARKET_NOISE = uint256(keccak256("clanworld.market.noise.v1"));
    uint256 internal constant DOMAIN_WEATHER = uint256(keccak256("clanworld.weather.v1"));
    uint256 internal constant DOMAIN_FAIR_ITERATION = uint256(keccak256("clanworld.fair.iteration.v1"));

    uint256 internal constant MAX_SHUFFLE_N = 64;

    error ShuffleSizeTooLarge(uint256 n, uint256 max);

    /// @notice Returns a uniform uint256 in [0, 2^256).
    function rngUniform(bytes32 seed, uint256 domainSalt, uint256 nonce) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(domainSalt, seed, nonce)));
    }

    /// @notice Returns a uniform value in [0, max) using rejection sampling.
    /// @dev Returns 0 when max is 0 so callers can handle optional random choices cheaply.
    function rngBounded(bytes32 seed, uint256 domainSalt, uint256 nonce, uint256 max) internal pure returns (uint256) {
        if (max == 0) {
            return 0;
        }

        uint256 remainder;
        unchecked {
            // Computes 2^256 % max without trying to represent 2^256 directly.
            remainder = (uint256(0) - max) % max;
        }
        uint256 maxValid = type(uint256).max - remainder;
        uint256 attempt = 0;

        while (true) {
            uint256 value = uint256(keccak256(abi.encodePacked(domainSalt, seed, nonce, max, attempt)));
            if (value <= maxValid) {
                return value % max;
            }

            unchecked {
                attempt++;
            }
        }

        revert("RNG: unreachable");
    }

    /// @notice Returns true with 50% probability.
    function rngBool(bytes32 seed, uint256 domainSalt, uint256 nonce) internal pure returns (bool) {
        return rngUniform(seed, domainSalt, nonce) & 1 == 1;
    }

    /// @notice Picks an index in proportion to each weight.
    /// @dev Returns 0 for empty arrays and zero-total arrays.
    function rngWeightedPick(bytes32 seed, uint256 domainSalt, uint256 nonce, uint256[] memory weights)
        internal
        pure
        returns (uint256 index)
    {
        uint256 total = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            total += weights[i];
        }

        if (total == 0) {
            return 0;
        }

        uint256 pick = rngBounded(seed, domainSalt, nonce, total);
        uint256 cumulative = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            cumulative += weights[i];
            if (pick < cumulative) {
                return i;
            }
        }

        return weights.length - 1;
    }

    /// @notice Returns a Fisher-Yates permutation of [0, n).
    /// @dev Reverts above MAX_SHUFFLE_N to keep callers away from accidental gas blowups.
    function rngShuffle(bytes32 seed, uint256 domainSalt, uint256 nonce, uint256 n)
        internal
        pure
        returns (uint8[] memory permutation)
    {
        if (n > MAX_SHUFFLE_N) {
            revert ShuffleSizeTooLarge(n, MAX_SHUFFLE_N);
        }

        permutation = new uint8[](n);
        for (uint256 i = 0; i < n; i++) {
            // casting is safe because n is bounded by MAX_SHUFFLE_N (64).
            // forge-lint: disable-next-line(unsafe-typecast)
            permutation[i] = uint8(i);
        }

        for (uint256 i = n; i > 1; i--) {
            uint256 stepNonce = uint256(keccak256(abi.encodePacked(nonce, n, i)));
            uint256 j = rngBounded(seed, domainSalt, stepNonce, i);
            uint8 tmp = permutation[i - 1];
            permutation[i - 1] = permutation[j];
            permutation[j] = tmp;
        }
    }
}
