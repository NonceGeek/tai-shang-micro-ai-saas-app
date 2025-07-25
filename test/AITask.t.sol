// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AITask} from "../src/AITask.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IAITask} from "../src/interfaces/IAITask.sol";

contract AITaskTest is Test {
    AITask public proxy;

    address public owner;
    address public creator;
    address public agent;
    address public backend;
    address public user1;
    address public user2;

    uint256 public ownerPrivateKey;
    uint256 public creatorPrivateKey;
    uint256 public agentPrivateKey;
    uint256 public backendPrivateKey;
    uint256 public user1PrivateKey;
    uint256 public user2PrivateKey;

    // 测试常量
    uint256 public constant TASK_BOUNTY = 1 ether;
    uint256 public constant TASK_DEPOSIT = 0.1 ether;
    string public constant TASK_DESCRIPTION = "Test AI task";
    string public constant RESULT_HASH = "QmTestHash123";

    function setUp() public {
        // 生成测试账户
        ownerPrivateKey = 0xA11CE;
        creatorPrivateKey = 0xB0B;
        agentPrivateKey = 0xC0DE;
        backendPrivateKey = 0xDEAD;
        user1PrivateKey = 0xFACE;
        user2PrivateKey = 0xCAFE;

        owner = vm.addr(ownerPrivateKey);
        creator = vm.addr(creatorPrivateKey);
        agent = vm.addr(agentPrivateKey);
        backend = vm.addr(backendPrivateKey);
        user1 = vm.addr(user1PrivateKey);
        user2 = vm.addr(user2PrivateKey);

        // 给测试账户一些ETH
        vm.deal(owner, 100 ether);
        vm.deal(creator, 100 ether);
        vm.deal(agent, 100 ether);
        vm.deal(backend, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // 部署合约（使用Upgrades库）
        vm.startPrank(owner);
        bytes memory initData = abi.encodeWithSelector(AITask.initialize.selector, backend);
        proxy = AITask(payable(Upgrades.deployUUPSProxy("AITask.sol:AITask", initData)));
        vm.stopPrank();
    }

    // ==================== 基础功能测试 ====================

    function test_Initialization() public {
        assertEq(proxy.owner(), owner);
        assertEq(proxy.getTaskCount(), 0);
        assertFalse(proxy.paused());
    }

    function test_DefaultConfig() public {
        assertEq(proxy.calculateRequiredDeposit(1 ether), 0.1 ether); // 10%
        assertEq(proxy.calculatePenalty(1 ether), 0.5 ether); // 50%
    }

    // ==================== 任务创建测试 ====================

    function test_CreateTask() public {
        vm.startPrank(creator);

        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);

        assertEq(taskId, 1);
        assertEq(proxy.getTaskCount(), 1);

        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(task.creator, creator);
        assertEq(task.bounty, TASK_BOUNTY);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Open));
        assertEq(task.description, TASK_DESCRIPTION);

        vm.stopPrank();
    }

    function test_CreateTaskWithInvalidBounty() public {
        vm.startPrank(creator);

        uint256 deadline = block.timestamp + 7 days;

        // 测试最小赏金
        vm.expectRevert("Bounty too low");
        proxy.createTask{value: 0.001 ether}(TASK_DESCRIPTION, deadline);

        // 测试最大赏金
        vm.expectRevert("Bounty too high");
        proxy.createTask{value: 200 ether}(TASK_DESCRIPTION, deadline);

        vm.stopPrank();
    }

    function test_CreateTaskWithInvalidDeadline() public {
        vm.startPrank(creator);

        uint256 pastDeadline = block.timestamp - 1;

        vm.expectRevert("Invalid deadline");
        proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, pastDeadline);

        vm.stopPrank();
    }

    function test_CreateTaskWithEmptyDescription() public {
        vm.startPrank(creator);

        uint256 deadline = block.timestamp + 7 days;

        vm.expectRevert("Description cannot be empty");
        proxy.createTask{value: TASK_BOUNTY}("", deadline);

        vm.stopPrank();
    }

    // ==================== 任务接单测试 ====================

    function test_AcceptTask() public {
        // 创建任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        // 接受任务
        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);

        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(task.agent, agent);
        assertEq(task.deposit, TASK_DEPOSIT);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Assigned));
        assertGt(task.assignedAt, 0);

        vm.stopPrank();
    }

    function test_AcceptTaskWithInsufficientDeposit() public {
        // 创建任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        // 尝试用不足的押金接受任务
        vm.startPrank(agent);
        vm.expectRevert("Insufficient deposit");
        proxy.acceptTask{value: 0.05 ether}(taskId);
        vm.stopPrank();
    }

    function test_AcceptOwnTask() public {
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);

        vm.expectRevert("Creator cannot accept own task");
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);

        vm.stopPrank();
    }

    function test_AcceptNonExistentTask() public {
        vm.startPrank(agent);
        vm.expectRevert("Task does not exist");
        proxy.acceptTask{value: TASK_DEPOSIT}(999);
        vm.stopPrank();
    }

    // ==================== 任务完成测试 ====================

    function test_CompleteTask() public {
        // 创建并接受任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        proxy.submitResult(taskId, RESULT_HASH);
        vm.stopPrank();

        // 确认任务完成
        vm.startPrank(creator);
        uint256 creatorBalanceBefore = creator.balance;
        proxy.confirmTask(taskId);

        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Completed));

        // 检查余额变化
        uint256 creatorBalanceAfter = creator.balance;
        // 创建者应该没有收到钱（因为确认时钱给了代理）
        assertEq(creatorBalanceAfter, creatorBalanceBefore);

        vm.stopPrank();
    }

    function test_CompleteTaskWithoutResult() public {
        // 创建并接受任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        vm.stopPrank();

        // 尝试确认没有结果的任务
        vm.startPrank(creator);
        vm.expectRevert("No result submitted");
        proxy.confirmTask(taskId);
        vm.stopPrank();
    }

    function test_CompleteTaskByNonCreator() public {
        // 创建并接受任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        proxy.submitResult(taskId, RESULT_HASH);
        vm.stopPrank();

        // 非创建者尝试确认
        vm.startPrank(user1);
        vm.expectRevert("Only task creator");
        proxy.confirmTask(taskId);
        vm.stopPrank();
    }

    // ==================== 任务拒绝测试 ====================

    function test_RejectTask() public {
        // 创建并接受任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        vm.stopPrank();

        // 拒绝任务
        vm.startPrank(creator);
        uint256 creatorBalanceBefore = creator.balance;
        proxy.rejectTask(taskId);

        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Rejected));

        // 检查创建者收到退款
        uint256 creatorBalanceAfter = creator.balance;
        assertGt(creatorBalanceAfter, creatorBalanceBefore);

        vm.stopPrank();
    }

    // ==================== 任务过期测试 ====================

    function test_ReclaimExpiredTask() public {
        // 创建任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 1; // 1秒后过期
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        // 等待过期
        vm.warp(block.timestamp + 2);

        // 回收过期任务
        vm.startPrank(creator);
        uint256 creatorBalanceBefore = creator.balance;
        proxy.reclaimExpiredTaskBounty(taskId);

        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Expired));

        // 检查创建者收到退款
        uint256 creatorBalanceAfter = creator.balance;
        assertGt(creatorBalanceAfter, creatorBalanceBefore);

        vm.stopPrank();
    }

    function test_ReclaimNonExpiredTask() public {
        // 创建任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        // 尝试回收未过期的任务
        vm.startPrank(creator);
        vm.expectRevert("Task not expired yet");
        proxy.reclaimExpiredTaskBounty(taskId);
        vm.stopPrank();
    }

    // ==================== 后端功能测试 ====================

    function test_HandleTimeout() public {
        // 创建并接受任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        vm.stopPrank();

        // 等待超时
        vm.warp(block.timestamp + 4 days); // 超过3天完成期限

        // 后端处理超时
        vm.startPrank(backend);
        proxy.handleTimeout(taskId);

        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.TimedOut));
        vm.stopPrank();
    }

    function test_HandleTimeoutByNonBackend() public {
        // 创建并接受任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        vm.stopPrank();

        // 等待超时
        vm.warp(block.timestamp + 4 days);

        // 非后端尝试处理超时
        vm.startPrank(user1);
        vm.expectRevert("Only backend");
        proxy.handleTimeout(taskId);
        vm.stopPrank();
    }

    // ==================== 管理功能测试 ====================

    function test_SetConfig() public {
        vm.startPrank(owner);

        uint256 newDepositRate = 2000; // 20%
        uint256 newPenaltyRate = 6000; // 60%
        uint256 newTaskExpiry = 14 days;
        uint256 newCompletionDeadline = 5 days;

        proxy.setConfig(newDepositRate, newPenaltyRate, newTaskExpiry, newCompletionDeadline);

        assertEq(proxy.calculateRequiredDeposit(1 ether), 0.2 ether);
        assertEq(proxy.calculatePenalty(1 ether), 0.6 ether);

        vm.stopPrank();
    }

    function test_SetConfigByNonOwner() public {
        vm.startPrank(user1);

        vm.expectRevert();
        proxy.setConfig(2000, 6000, 14 days, 5 days);

        vm.stopPrank();
    }

    function test_SetPlatformFee() public {
        vm.startPrank(owner);

        uint256 newPlatformFee = 500; // 5%
        proxy.setPlatformFee(newPlatformFee);

        vm.stopPrank();
    }

    function test_WithdrawPlatformFees() public {
        // 创建并完成一个任务以产生平台费用
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        proxy.submitResult(taskId, RESULT_HASH);
        vm.stopPrank();

        vm.startPrank(creator);
        proxy.confirmTask(taskId);
        vm.stopPrank();

        // 提取平台费用
        vm.startPrank(owner);
        uint256 ownerBalanceBefore = owner.balance;
        proxy.withdrawPlatformFees();
        uint256 ownerBalanceAfter = owner.balance;

        assertGt(ownerBalanceAfter, ownerBalanceBefore);
        vm.stopPrank();
    }

    // ==================== 紧急功能测试 ====================

    function test_EmergencyPause() public {
        vm.startPrank(owner);
        proxy.emergencyPause();
        assertTrue(proxy.paused());
        vm.stopPrank();
    }

    function test_EmergencyUnpause() public {
        vm.startPrank(owner);
        proxy.emergencyPause();
        proxy.emergencyUnpause();
        assertFalse(proxy.paused());
        vm.stopPrank();
    }

    function test_CreateTaskWhenPaused() public {
        vm.startPrank(owner);
        proxy.emergencyPause();
        vm.stopPrank();

        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        vm.expectRevert("Contract is paused");
        proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();
    }

    // ==================== 查询功能测试 ====================

    function test_GetTasksByCreator() public {
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        uint256[] memory creatorTasks = proxy.getTasksByCreator(creator);
        assertEq(creatorTasks.length, 2);
        assertEq(creatorTasks[0], taskId1);
        assertEq(creatorTasks[1], taskId2);
    }

    function test_GetTasksByAgent() public {
        // 创建任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        // 接受任务
        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        vm.stopPrank();

        uint256[] memory agentTasks = proxy.getTasksByAgent(agent);
        assertEq(agentTasks.length, 1);
        assertEq(agentTasks[0], taskId);
    }

    function test_GetOpenTasks() public {
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        uint256[] memory openTasks = proxy.getOpenTasks();
        assertEq(openTasks.length, 2);
        assertEq(openTasks[0], taskId1);
        assertEq(openTasks[1], taskId2);
    }

    // ==================== 边界条件测试 ====================

    function test_MultipleTasks() public {
        // 创建多个任务
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId1 = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        uint256 taskId2 = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        uint256 taskId3 = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        assertEq(proxy.getTaskCount(), 3);
        assertEq(taskId1, 1);
        assertEq(taskId2, 2);
        assertEq(taskId3, 3);
    }

    function test_TaskLifecycle() public {
        // 完整的任务生命周期测试
        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        uint256 taskId = proxy.createTask{value: TASK_BOUNTY}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();

        // 检查初始状态
        IAITask.Task memory task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Open));

        // 接受任务
        vm.startPrank(agent);
        proxy.acceptTask{value: TASK_DEPOSIT}(taskId);
        vm.stopPrank();

        task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Assigned));

        // 提交结果
        vm.startPrank(agent);
        proxy.submitResult(taskId, RESULT_HASH);
        vm.stopPrank();

        // 确认完成
        vm.startPrank(creator);
        proxy.confirmTask(taskId);
        vm.stopPrank();

        task = proxy.getTask(taskId);
        assertEq(uint256(task.status), uint256(IAITask.TaskStatus.Completed));
    }

    // ==================== 失败测试 ====================

    function testFail_NonExistentTask() public {
        proxy.getTask(999);
    }

    function testFail_InvalidTaskId() public {
        proxy.getTask(0);
    }

    // ==================== 模糊测试 ====================

    function testFuzz_CreateTaskWithValidBounty(uint256 bounty) public {
        vm.assume(bounty >= 0.01 ether && bounty <= 100 ether);

        vm.startPrank(creator);
        uint256 deadline = block.timestamp + 7 days;
        proxy.createTask{value: bounty}(TASK_DESCRIPTION, deadline);
        vm.stopPrank();
    }

    function testFuzz_CalculateDeposit(uint256 bounty) public {
        vm.assume(bounty >= 0.01 ether && bounty <= 100 ether);

        uint256 deposit = proxy.calculateRequiredDeposit(bounty);
        assertEq(deposit, (bounty * 1000) / 10000); // 10%
    }
}
