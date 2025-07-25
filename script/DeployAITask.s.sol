// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AITask} from "../src/AITask.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployAITask is Script {
    AITask public proxy;
    address public backend;

    function setUp() public {
        // 从环境变量获取后端地址，如果没有设置则使用部署者地址
        backend = vm.envOr("BACKEND_ADDRESS", address(this));
    }

    function run() public {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.envAddress("DEV_ADDRESS");

        console.log("Deploying AITask contract using OpenZeppelin Upgrades...");
        console.log("Deployer:", deployer);
        console.log("Backend:", backend);

        vm.startBroadcast(deployer);

        // 使用OpenZeppelin Upgrades部署UUPS代理
        bytes memory initData = abi.encodeWithSelector(AITask.initialize.selector, backend);

        proxy = AITask(payable(Upgrades.deployUUPSProxy("AITask.sol:AITask", initData)));

        console.log("Proxy deployed at:", address(proxy));

        // 验证部署
        console.log("Total tasks:", proxy.getTaskCount());
        console.log("Owner:", proxy.owner());

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        console.log("Proxy address:", address(proxy));
    }
}
