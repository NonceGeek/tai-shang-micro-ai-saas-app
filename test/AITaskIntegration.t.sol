// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AITask} from "../src/AITask.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IAITask} from "../src/interfaces/IAITask.sol";

contract AITaskIntegrationTest is Test {
    AITask public proxy;

    address public owner;
    address public creator1;
    address public creator2;
    address public agent1;
    address public agent2;
    address public backend;
    address public user1;
    address public user2;

    uint256 public ownerPrivateKey;
    uint256 public creator1PrivateKey;
    uint256 public creator2PrivateKey;
    uint256 public agent1PrivateKey;
    uint256 public agent2PrivateKey;
    uint256 public backendPrivateKey;
    uint256 public user1PrivateKey;
    uint256 public user2PrivateKey;

    // 测试常量
    uint256 public constant TASK_BOUNTY_1 = 1 ether;
    uint256 public constant TASK_BOUNTY_2 = 2 ether;
    uint256 public constant TASK_DEPOSIT_1 = 0.1 ether;
    uint256 public constant TASK_DEPOSIT_2 = 0.2 ether;
    string public constant TASK_DESCRIPTION_1 = "Test AI task 1";
    string public constant TASK_DESCRIPTION_2 = "Test AI task 2";
    string public constant RESULT_HASH_1 = "QmTestHash123";
    string public constant RESULT_HASH_2 = "QmTestHash456";

    function setUp() public {
        // 生成测试账户
        ownerPrivateKey = 0xA11CE;
        creator1PrivateKey = 0xB0B1;
        creator2PrivateKey = 0xB0B2;
        agent1PrivateKey = 0xC0DE1;
        agent2PrivateKey = 0xC0DE2;
        backendPrivateKey = 0xDEAD;
        user1PrivateKey = 0xFACE1;
        user2PrivateKey = 0xFACE2;

        owner = vm.addr(ownerPrivateKey);
        creator1 = vm.addr(creator1PrivateKey);
        creator2 = vm.addr(creator2PrivateKey);
        agent1 = vm.addr(agent1PrivateKey);
        agent2 = vm.addr(agent2PrivateKey);
        backend = vm.addr(backendPrivateKey);
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);

        // 给测试账户一些ETH
        vm.deal(owner, 1000 ether);
        vm.deal(creator1, 100 ether);
        vm.deal(creator2, 100 ether);
        vm.deal(agent1, 100 ether);
        vm.deal(agent2, 100 ether);
        vm.deal(backend, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // 部署合约（使用Upgrades库）
        vm.startPrank(owner);
        bytes memory initData = abi.encodeWithSelector(AITask.initialize.selector, backend);
        proxy = AITask(payable(Upgrades.deployUUPSProxy("AITask.sol:AITask", initData)));
        vm.stopPrank();
    }

    // ==================== 复杂业务场景测试 ====================

    function test_MultipleCreatorsAndAgents() public {
        // 创建者1创建任务1
        vm.startPrank(creator1);
        uint256 deadline1 = block.timestamp + 7 days;
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline1);
        vm.stopPrank();

        // 创建者2创建任务2
        vm.startPrank(creator2);
        uint256 deadline2 = block.timestamp + 7 days;
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY_2}(TASK_DESCRIPTION_2, deadline2);
        vm.stopPrank();

        // 代理1接受任务1
        vm.startPrank(agent1);
        proxy.acceptTask{value: TASK_DEPOSIT_1}(taskId1);
        vm.stopPrank();

        // 代理2接受任务2
        vm.startPrank(agent2);
        proxy.acceptTask{value: TASK_DEPOSIT_2}(taskId2);
        vm.stopPrank();

        // 验证任务状态
        IAITask.Task memory task1 = proxy.getTask(taskId1);
        IAITask.Task memory task2 = proxy.getTask(taskId2);

        assertEq(task1.creator, creator1);
        assertEq(task1.agent, agent1);
        assertEq(uint256(task1.status), uint256(IAITask.TaskStatus.Assigned));

        assertEq(task2.creator, creator2);
        assertEq(task2.agent, agent2);
        assertEq(uint256(task2.status), uint256(IAITask.TaskStatus.Assigned));

        // 验证开放任务列表
        uint256[] memory openTasks = proxy.getOpenTasks();
        assertEq(openTasks.length, 0); // 所有任务都被接受了

        // 验证创建者的任务列表
        uint256[] memory creator1Tasks = proxy.getTasksByCreator(creator1);
        uint256[] memory creator2Tasks = proxy.getTasksByCreator(creator2);
        assertEq(creator1Tasks.length, 1);
        assertEq(creator2Tasks.length, 1);
        assertEq(creator1Tasks[0], taskId1);
        assertEq(creator2Tasks[0], taskId2);

        // 验证代理的任务列表
        uint256[] memory agent1Tasks = proxy.getTasksByAgent(agent1);
        uint256[] memory agent2Tasks = proxy.getTasksByAgent(agent2);
        assertEq(agent1Tasks.length, 1);
        assertEq(agent2Tasks.length, 1);
        assertEq(agent1Tasks[0], taskId1);
        assertEq(agent2Tasks[0], taskId2);
    }

    function test_AgentWithMultipleTasks() public {
        // 创建者1创建多个任务
        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline);
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY_2}(TASK_DESCRIPTION_2, deadline);
        vm.stopPrank();

        // 代理1接受两个任务
        vm.startPrank(agent1);
        proxy.acceptTask{value: TASK_DEPOSIT_1}(taskId1);
        proxy.acceptTask{value: TASK_DEPOSIT_2}(taskId2);
        vm.stopPrank();

        // 验证代理的任务列表
        uint256[] memory agent1Tasks = proxy.getTasksByAgent(agent1);
        assertEq(agent1Tasks.length, 2);
        assertEq(agent1Tasks[0], taskId1);
        assertEq(agent1Tasks[1], taskId2);

        // 提交结果
        vm.startPrank(agent1);
        proxy.submitResult(taskId1, RESULT_HASH_1);
        proxy.submitResult(taskId2, RESULT_HASH_2);
        vm.stopPrank();

        // 确认任务1完成
        vm.startPrank(creator1);
        proxy.confirmTask(taskId1);
        vm.stopPrank();

        // 验证任务1状态
        IAITask.Task memory task1 = proxy.getTask(taskId1);
        assertEq(uint256(task1.status), uint256(IAITask.TaskStatus.Completed));

        // 验证任务2仍然处于已分配状态
        IAITask.Task memory task2 = proxy.getTask(taskId2);
        assertEq(uint256(task2.status), uint256(IAITask.TaskStatus.Assigned));
    }

    function test_TaskExpiryAndReclaim() public {
        // 创建多个任务，设置不同的过期时间
        vm.startPrank(creator1);
        uint256 deadline1 = block.timestamp + 1; // 1秒后过期
        uint256 deadline2 = block.timestamp + 7 days; // 7天后过期
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline1);
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY_2}(TASK_DESCRIPTION_2, deadline2);
        vm.stopPrank();

        // 等待任务1过期
        vm.warp(block.timestamp + 2);

        // 回收过期任务1
        vm.startPrank(creator1);
        uint256 creator1BalanceBefore = creator1.balance;
        proxy.reclaimExpiredTaskBounty(taskId1);
        uint256 creator1BalanceAfter = creator1.balance;
        vm.stopPrank();

        // 验证任务1状态和余额变化
        IAITask.Task memory task1 = proxy.getTask(taskId1);
        assertEq(uint256(task1.status), uint256(IAITask.TaskStatus.Expired));
        assertGt(creator1BalanceAfter, creator1BalanceBefore);

        // 验证任务2仍然开放
        IAITask.Task memory task2 = proxy.getTask(taskId2);
        assertEq(uint256(task2.status), uint256(IAITask.TaskStatus.Open));

        // 验证开放任务列表
        uint256[] memory openTasks = proxy.getOpenTasks();
        assertEq(openTasks.length, 1);
        assertEq(openTasks[0], taskId2);
    }

    function test_BackendBatchProcessing() public {
        // 创建多个任务，设置不同的过期时间
        vm.startPrank(creator1);
        uint256 deadline1 = block.timestamp + 1; // 1秒后过期
        uint256 deadline2 = block.timestamp + 1; // 1秒后过期
        uint256 deadline3 = block.timestamp + 7 days; // 7天后过期
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline1);
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_2, deadline2);
        uint256 taskId3 = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline3);
        vm.stopPrank();

        // 等待任务1和2过期
        vm.warp(block.timestamp + 2);

        // 后端批量处理过期任务
        vm.startPrank(backend);
        uint256[] memory taskIds = new uint256[](3);
        taskIds[0] = taskId1;
        taskIds[1] = taskId2;
        taskIds[2] = taskId3;
        proxy.handleExpiredTasks(taskIds);
        vm.stopPrank();

        // 验证任务状态
        IAITask.Task memory task1 = proxy.getTask(taskId1);
        IAITask.Task memory task2 = proxy.getTask(taskId2);
        IAITask.Task memory task3 = proxy.getTask(taskId3);

        assertEq(uint256(task1.status), uint256(IAITask.TaskStatus.Expired));
        assertEq(uint256(task2.status), uint256(IAITask.TaskStatus.Expired));
        assertEq(uint256(task3.status), uint256(IAITask.TaskStatus.Open)); // 未过期

        // 验证开放任务列表
        uint256[] memory openTasks = proxy.getOpenTasks();
        assertEq(openTasks.length, 1);
        assertEq(openTasks[0], taskId3);
    }

    function test_PlatformFeeAccumulation() public {
        // 创建并完成多个任务以累积平台费用
        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline);
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY_2}(TASK_DESCRIPTION_2, deadline);
        vm.stopPrank();

        // 代理接受并完成任务
        vm.startPrank(agent1);
        proxy.acceptTask{value: TASK_DEPOSIT_1}(taskId1);
        proxy.submitResult(taskId1, RESULT_HASH_1);
        vm.stopPrank();

        vm.startPrank(agent2);
        proxy.acceptTask{value: TASK_DEPOSIT_2}(taskId2);
        proxy.submitResult(taskId2, RESULT_HASH_2);
        vm.stopPrank();

        // 确认任务完成
        vm.startPrank(creator1);
        proxy.confirmTask(taskId1);
        proxy.confirmTask(taskId2);
        vm.stopPrank();

        // 计算预期的平台费用
        uint256 expectedFee1 = (TASK_BOUNTY_1 * 250) / 10000; // 2.5%
        uint256 expectedFee2 = (TASK_BOUNTY_2 * 250) / 10000; // 2.5%
        uint256 totalExpectedFee = expectedFee1 + expectedFee2;

        // 提取平台费用
        vm.startPrank(owner);
        uint256 ownerBalanceBefore = owner.balance;
        proxy.withdrawPlatformFees();
        uint256 ownerBalanceAfter = owner.balance;
        vm.stopPrank();

        // 验证提取的金额
        uint256 actualFee = ownerBalanceAfter - ownerBalanceBefore;
        assertEq(actualFee, totalExpectedFee);
    }

    function test_ConfigChanges() public {
        // 测试配置变更对现有任务的影响
        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline);
        vm.stopPrank();

        // 更改配置
        vm.startPrank(owner);
        proxy.setConfig(2000, 6000, 14 days, 5 days); // 20% 押金, 60% 惩罚
        proxy.setPlatformFee(500); // 5% 平台费用
        vm.stopPrank();

        // 验证新配置对新任务的影响
        uint256 newDeposit = proxy.calculateRequiredDeposit(TASK_BOUNTY_1);
        uint256 newPenalty = proxy.calculatePenalty(TASK_DEPOSIT_1);

        assertEq(newDeposit, (TASK_BOUNTY_1 * 2000) / 10000); // 20%
        assertEq(newPenalty, (TASK_DEPOSIT_1 * 6000) / 10000); // 60%

        // 代理接受任务（使用新配置的押金）
        vm.startPrank(agent1);
        proxy.acceptTask{value: newDeposit}(taskId);
        vm.stopPrank();

        // 验证任务状态
        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(task.agent, agent1);
        assertEq(task.deposit, newDeposit);
    }

    function test_EmergencyScenarios() public {
        // 创建并接受任务
        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline);
        vm.stopPrank();

        vm.startPrank(agent1);
        proxy.acceptTask{value: TASK_DEPOSIT_1}(taskId);
        vm.stopPrank();

        // 紧急暂停
        vm.startPrank(owner);
        proxy.emergencyPause();
        vm.stopPrank();

        // 验证暂停状态
        assertTrue(proxy.paused());

        // 尝试正常操作（应该失败）
        vm.startPrank(agent1);
        vm.expectRevert("Contract is paused");
        proxy.submitResult(taskId, RESULT_HASH_1);
        vm.stopPrank();

        // 紧急提取
        vm.startPrank(owner);
        uint256 creatorBalanceBefore = creator1.balance;
        uint256 agentBalanceBefore = agent1.balance;
        proxy.emergencyWithdraw(taskId);
        uint256 creatorBalanceAfter = creator1.balance;
        uint256 agentBalanceAfter = agent1.balance;
        vm.stopPrank();

        // 验证余额变化
        assertGt(creatorBalanceAfter, creatorBalanceBefore); // 创建者收到赏金
        assertGt(agentBalanceAfter, agentBalanceBefore); // 代理收到押金

        // 验证任务状态
        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Expired));

        // 恢复合约
        vm.startPrank(owner);
        proxy.emergencyUnpause();
        vm.stopPrank();

        assertFalse(proxy.paused());
    }

    function test_ConcurrentTaskOperations() public {
        // 创建多个任务
        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline);
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY_2}(TASK_DESCRIPTION_2, deadline);
        vm.stopPrank();

        // 代理1接受任务1
        vm.startPrank(agent1);
        proxy.acceptTask{value: TASK_DEPOSIT_1}(taskId1);
        vm.stopPrank();

        // 代理2尝试接受已被接受的任务1（应该失败）
        vm.startPrank(agent2);
        vm.expectRevert("Task not available");
        proxy.acceptTask{value: TASK_DEPOSIT_1}(taskId1);
        vm.stopPrank();

        // 代理2接受任务2
        vm.startPrank(agent2);
        proxy.acceptTask{value: TASK_DEPOSIT_2}(taskId2);
        vm.stopPrank();

        // 验证任务状态
        IAITask.Task memory task1 = proxy.getTask(taskId1);
        IAITask.Task memory task2 = proxy.getTask(taskId2);

        assertEq(task1.agent, agent1);
        assertEq(task2.agent, agent2);
        assertEq(uint256(task1.status), uint256(IAITask.TaskStatus.Assigned));
        assertEq(uint256(task2.status), uint256(IAITask.TaskStatus.Assigned));

        // 验证开放任务列表为空
        uint256[] memory openTasks = proxy.getOpenTasks();
        assertEq(openTasks.length, 0);
    }

    function test_TaskTimeoutHandling() public {
        // 创建并接受任务
        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline);
        vm.stopPrank();

        vm.startPrank(agent1);
        proxy.acceptTask{value: TASK_DEPOSIT_1}(taskId);
        vm.stopPrank();

        // 等待超时
        vm.warp(block.timestamp + 4 days); // 超过3天完成期限

        // 后端处理超时
        vm.startPrank(backend);
        uint256 creatorBalanceBefore = creator1.balance;
        uint256 agentBalanceBefore = agent1.balance;
        proxy.handleTimeout(taskId);
        uint256 creatorBalanceAfter = creator1.balance;
        uint256 agentBalanceAfter = agent1.balance;
        vm.stopPrank();

        // 验证任务状态
        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.TimedOut));

        // 验证余额变化
        assertGt(creatorBalanceAfter, creatorBalanceBefore); // 创建者收到赏金退款
        assertLt(agentBalanceAfter, agentBalanceBefore); // 代理被扣除部分押金
    }

    function test_InvalidOperations() public {
        // 测试各种无效操作
        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY_1}(TASK_DESCRIPTION_1, deadline);
        vm.stopPrank();

        // 非代理尝试提交结果
        vm.startPrank(user1);
        vm.expectRevert("Only task agent");
        proxy.submitResult(taskId, RESULT_HASH_1);
        vm.stopPrank();

        // 非创建者尝试确认任务
        vm.startPrank(user1);
        vm.expectRevert("Only task creator");
        proxy.confirmTask(taskId);
        vm.stopPrank();

        // 非创建者尝试拒绝任务
        vm.startPrank(user1);
        vm.expectRevert("Only task creator");
        proxy.rejectTask(taskId);
        vm.stopPrank();

        // 非创建者尝试回收过期任务
        vm.startPrank(user1);
        vm.expectRevert("Only task creator");
        proxy.reclaimExpiredTaskBounty(taskId);
        vm.stopPrank();

        // 非后端尝试处理超时
        vm.startPrank(user1);
        vm.expectRevert("Only backend");
        proxy.handleTimeout(taskId);
        vm.stopPrank();
    }

    // ==================== 性能测试 ====================

    function test_MassiveTaskCreation() public {
        // 测试大量任务创建的性能
        uint256 numTasks = 100;

        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;

        for (uint256 i = 0; i < numTasks; i++) {
            string memory description = string(abi.encodePacked("Task ", vm.toString(i)));
            proxy.createTask{value: TASK_BOUNTY_1}(description, deadline);
        }
        vm.stopPrank();

        // 验证任务数量
        assertEq(proxy.getTaskCount(), numTasks);

        // 验证开放任务列表
        uint256[] memory openTasks = proxy.getOpenTasks();
        assertEq(openTasks.length, numTasks);
    }

    function test_MassiveTaskAcceptance() public {
        // 创建大量任务
        uint256 numTasks = 50;

        vm.startPrank(creator1);
        uint256 deadline = block.timestamp + 7 days;

        for (uint256 i = 0; i < numTasks; i++) {
            string memory description = string(abi.encodePacked("Task ", vm.toString(i)));
            proxy.createTask{value: TASK_BOUNTY_1}(description, deadline);
        }
        vm.stopPrank();

        // 多个代理接受任务
        for (uint256 i = 0; i < numTasks; i++) {
            address currentAgent = i % 2 == 0 ? agent1 : agent2;
            vm.startPrank(currentAgent);
            proxy.acceptTask{value: TASK_DEPOSIT_1}(i + 1);
            vm.stopPrank();
        }

        // 验证所有任务都被接受
        uint256[] memory openTasks = proxy.getOpenTasks();
        assertEq(openTasks.length, 0);

        // 验证代理的任务列表
        uint256[] memory agent1Tasks = proxy.getTasksByAgent(agent1);
        uint256[] memory agent2Tasks = proxy.getTasksByAgent(agent2);
        assertEq(agent1Tasks.length + agent2Tasks.length, numTasks);
    }
}
