// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AITask} from "../src/AITask.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeAITask is Script {
    AITask public proxy;

    function setUp() public {
        // 从环境变量获取代理合约地址
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        proxy = AITask(payable(proxyAddress));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Upgrading AITask contract using OpenZeppelin Upgrades...");
        console.log("Deployer:", deployer);
        console.log("Proxy address:", address(proxy));

        vm.startBroadcast(deployerPrivateKey);

        // 使用OpenZeppelin Upgrades升级UUPS代理
        Upgrades.upgradeProxy(
            address(proxy),
            "AITask.sol:AITask",
            "" // 空的升级数据
        );

        console.log("Proxy upgraded successfully");

        // 验证升级
        console.log("Total tasks after upgrade:", proxy.getTaskCount());
        console.log("Owner after upgrade:", proxy.owner());

        vm.stopBroadcast();

        console.log("Upgrade completed successfully!");
    }
}
