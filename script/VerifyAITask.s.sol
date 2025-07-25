// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AITask} from "../src/AITask.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract VerifyAITask is Script {
    AITask public proxy;

    function setUp() public {
        // 从环境变量获取代理合约地址
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        proxy = AITask(payable(proxyAddress));
    }

    function run() public {
        console.log("=== AITask Contract Verification ===");
        console.log("Proxy address:", address(proxy));

        // 验证代理合约
        console.log("\n--- Proxy Verification ---");
        console.log("Proxy address:", address(proxy));

        // 检查合约状态
        console.log("\n--- Contract State ---");
        console.log("Owner:", proxy.owner());
        console.log("Total tasks:", proxy.getTaskCount());
        console.log("Paused:", proxy.paused());

        // 检查配置
        console.log("\n--- Configuration ---");
        console.log("Required deposit for 1 ETH:", proxy.calculateRequiredDeposit(1 ether));
        console.log("Penalty for 0.1 ETH deposit:", proxy.calculatePenalty(0.1 ether));

        // 检查开放任务
        console.log("\n--- Open Tasks ---");
        uint256[] memory openTasks = proxy.getOpenTasks();
        console.log("Number of open tasks:", openTasks.length);
        for (uint256 i = 0; i < openTasks.length && i < 5; i++) {
            console.log("Open task ID:", openTasks[i]);
        }

        console.log("\n=== Verification Complete ===");
    }
}
