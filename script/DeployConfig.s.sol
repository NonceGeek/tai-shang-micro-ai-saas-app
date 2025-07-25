// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

contract DeployConfig is Script {
    // 网络配置
    struct NetworkConfig {
        string name;
        uint256 chainId;
        string rpcUrl;
        address backend;
        uint256 deployerPrivateKey;
    }

    // 默认配置
    NetworkConfig public localConfig;
    NetworkConfig public sepoliaConfig;
    NetworkConfig public mainnetConfig;

    function setUp() public {
        // 本地网络配置
        localConfig = NetworkConfig({
            name: "local",
            chainId: 31337,
            rpcUrl: "http://localhost:8545",
            backend: address(0x1234567890123456789012345678901234567890),
            deployerPrivateKey: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        });

        // Sepolia测试网配置
        sepoliaConfig = NetworkConfig({
            name: "sepolia",
            chainId: 11155111,
            rpcUrl: vm.envString("SEPOLIA_RPC_URL"),
            backend: vm.envAddress("SEPOLIA_BACKEND_ADDRESS"),
            deployerPrivateKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });

        // 主网配置
        mainnetConfig = NetworkConfig({
            name: "mainnet",
            chainId: 1,
            rpcUrl: vm.envString("MAINNET_RPC_URL"),
            backend: vm.envAddress("MAINNET_BACKEND_ADDRESS"),
            deployerPrivateKey: vm.envUint("MAINNET_PRIVATE_KEY")
        });
    }

    function getConfig(string memory network) public view returns (NetworkConfig memory) {
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("local"))) {
            return localConfig;
        } else if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("sepolia"))) {
            return sepoliaConfig;
        } else if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("mainnet"))) {
            return mainnetConfig;
        } else {
            revert("Unsupported network");
        }
    }

    function printConfig(string memory network) public view {
        NetworkConfig memory config = getConfig(network);
        console.log("=== Network Configuration ===");
        console.log("Network:", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("RPC URL:", config.rpcUrl);
        console.log("Backend Address:", config.backend);
        console.log("Deployer Address:", vm.addr(config.deployerPrivateKey));
        console.log("=============================");
    }
}
