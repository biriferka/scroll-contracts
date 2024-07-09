// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {console} from "forge-std/Script.sol";
import {stdToml} from "forge-std/StdToml.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {CONFIG_CONTRACTS_PATH, DEFAULT_DEPLOYMENT_SALT, DETERMINISTIC_DEPLOYMENT_PROXY_ADDR} from "./Constants.sol";
import {Configuration} from "./Configuration.sol";

/// @notice DeterminsticDeployment provides utilities for deterministic contract deployments.
abstract contract DeterminsticDeployment is Configuration {
    using stdToml for string;

    /*********
     * Types *
     *********/

    enum ScriptMode {
        None,
        LogAddresses,
        WriteConfig,
        VerifyConfig
    }

    /*******************
     * State variables *
     *******************/

    ScriptMode private mode;
    string private saltPrefix;
    bool private skipDeploy;

    /***************
     * Constructor *
     ***************/

    constructor() {
        mode = ScriptMode.None;
        skipDeploy = false;

        // salt prefix used for deterministic deployments
        if (bytes(DEPLOYMENT_SALT).length != 0) {
            saltPrefix = DEPLOYMENT_SALT;
        } else {
            saltPrefix = DEFAULT_DEPLOYMENT_SALT;
        }

        // sanity check: make sure DeterministicDeploymentProxy exists
        if (DETERMINISTIC_DEPLOYMENT_PROXY_ADDR.code.length == 0) {
            revert(
                string(
                    abi.encodePacked(
                        "[ERROR] DeterministicDeploymentProxy (",
                        vm.toString(DETERMINISTIC_DEPLOYMENT_PROXY_ADDR),
                        ") is not available"
                    )
                )
            );
        }
    }

    /**********************
     * Internal interface *
     **********************/

    function setScriptMode(ScriptMode scriptMode) internal {
        mode = scriptMode;
    }

    function setScriptMode(string memory scriptMode) internal {
        if (keccak256(bytes(scriptMode)) == keccak256(bytes("log-addresses"))) {
            mode = ScriptMode.WriteConfig;
        } else if (keccak256(bytes(scriptMode)) == keccak256(bytes("write-config"))) {
            mode = ScriptMode.WriteConfig;
        } else if (keccak256(bytes(scriptMode)) == keccak256(bytes("verify-config"))) {
            mode = ScriptMode.VerifyConfig;
        } else {
            mode = ScriptMode.None;
        }
    }

    function skipDeployment() internal {
        skipDeploy = true;
    }

    function deploy(string memory name, bytes memory codeWithArgs) internal returns (address) {
        return _deploy(name, codeWithArgs);
    }

    function deploy(
        string memory name,
        bytes memory code,
        bytes memory args
    ) internal returns (address) {
        return _deploy(name, abi.encodePacked(code, args));
    }

    function predict(string memory name, bytes memory codeWithArgs) internal view returns (address) {
        return _predict(name, codeWithArgs);
    }

    function predict(
        string memory name,
        bytes memory code,
        bytes memory args
    ) internal view returns (address) {
        return _predict(name, abi.encodePacked(code, args));
    }

    function upgrade(
        address proxyAdminAddr,
        address proxyAddr,
        address implAddr
    ) internal {
        if (!skipDeploy) {
            ProxyAdmin(notnull(proxyAdminAddr)).upgrade(
                ITransparentUpgradeableProxy(notnull(proxyAddr)),
                notnull(implAddr)
            );
        }
    }

    /*********************
     * Private functions *
     *********************/

    function _getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(saltPrefix, name));
    }

    function _deploy(string memory name, bytes memory codeWithArgs) private returns (address) {
        // check override (mainly used with predeploys)
        address addr = tryGetOverride(name);

        if (addr != address(0)) {
            _label(name, addr);
            return addr;
        }

        // predict determinstic deployment address
        addr = _predict(name, codeWithArgs);
        _label(name, addr);

        if (skipDeploy) {
            return addr;
        }

        // revert if the contract is already deployed
        if (addr.code.length > 0) {
            revert(
                string(abi.encodePacked("[ERROR] contract ", name, " (", vm.toString(addr), ") is already deployed"))
            );
        }

        // deploy contract
        bytes32 salt = _getSalt(name);
        bytes memory data = abi.encodePacked(salt, codeWithArgs);
        (bool success, ) = DETERMINISTIC_DEPLOYMENT_PROXY_ADDR.call(data);
        require(success, "call failed");
        require(addr.code.length != 0, "deployment address mismatch");

        return addr;
    }

    function _predict(string memory name, bytes memory codeWithArgs) private view returns (address) {
        bytes32 salt = _getSalt(name);

        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                DETERMINISTIC_DEPLOYMENT_PROXY_ADDR,
                                salt,
                                keccak256(codeWithArgs)
                            )
                        )
                    )
                )
            );
    }

    function _label(string memory name, address addr) internal {
        vm.label(addr, name);

        if (mode == ScriptMode.None) {
            return;
        }

        if (mode == ScriptMode.LogAddresses) {
            console.log(string(abi.encodePacked(name, "_ADDR=", vm.toString(address(addr)))));
            return;
        }

        string memory tomlPath = string(abi.encodePacked(".", name, "_ADDR"));

        if (mode == ScriptMode.WriteConfig) {
            vm.writeToml(vm.toString(addr), CONFIG_CONTRACTS_PATH, tomlPath);
            return;
        }

        if (mode == ScriptMode.VerifyConfig) {
            address expectedAddr = contractsCfg.readAddress(tomlPath);

            if (addr != expectedAddr) {
                revert(
                    string(
                        abi.encodePacked(
                            "[ERROR] unexpected address for ",
                            name,
                            ", expected = ",
                            vm.toString(expectedAddr),
                            " (from toml config), got = ",
                            vm.toString(addr)
                        )
                    )
                );
            }
        }
    }
}