// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";

/// @title  EnvLoader
/// @notice Base abstract script for loading and validating environment variables in Forge scripts
abstract contract EnvLoader is Script {
    string internal constant ERR_INVALID_ENV = " is missing or invalid in .env";

    /// @notice Abstract method to be implemented by inheriting scripts for loading .env variables
    /// @dev    Called at the beginning of the `run()` method in deployment scripts
    function loadEnvVars() internal virtual;

    /// @notice    Loads private key from the .env as a uint256
    /// @param key The .env variable key
    /// @return    'The' private key as uint256
    function getEnvPrivateKey(string memory key) internal view returns (uint256) {
        try vm.envBytes32(key) returns (bytes32 keyBytes) {
            require(keyBytes != bytes32(0), string.concat(key, " is empty"));
            return uint256(keyBytes);
        } catch {
            revert(string.concat(key, ERR_INVALID_ENV));
        }
    }

    /// @notice    Loads address from the .env
    /// @param key The .env variable key
    /// @return    'The' parsed Ethereum address
    function getEnvAddress(string memory key) internal view returns (address) {
        try vm.envAddress(key) returns (address addr) {
            require(addr != address(0), string.concat(key, " is zero address"));
            return addr;
        } catch {
            revert(string.concat(key, ERR_INVALID_ENV));
        }
    }

    /// @notice    Loads unsigned integer from the .env
    /// @param key The .env variable key
    /// @return    'The' parsed uint256 value
    function getEnvUint(string memory key) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 val) {
            require(val > 0, string.concat(key, " must be > 0"));
            return val;
        } catch {
            revert(string.concat(key, ERR_INVALID_ENV));
        }
    }

    /// @notice    Loads non-empty string from .env
    /// @param key The .env variable key
    /// @return    'The' parsed string value
    function getEnvString(string memory key) internal view returns (string memory) {
        try vm.envString(key) returns (string memory val) {
            require(bytes(val).length > 0, string.concat(key, " is empty"));
            return val;
        } catch {
            revert(string.concat(key, ERR_INVALID_ENV));
        }
    }
}
