// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Owned} from "solmate/auth/Owned.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

/**
 * @title AITaskSolmate
 * @notice 轻量级版本，减少合约大小
 */
contract AITaskSolmate is Owned, ReentrancyGuard {
    using SafeTransferLib for address payable;
    using SafeCastLib for uint256;

    // ==================== 枚举 ====================

    enum TaskStatus {
        Open,
        Assigned,
        Completed,
        Rejected,
        Expired,
        TimedOut
    }

    // ==================== 存储结构 ====================

    struct Task {
        uint256 taskId;
        address creator;
        address agent;
        uint256 bounty;
        uint256 deposit;
        uint256 createdAt;
        uint256 deadline;
        uint256 assignedAt;
        TaskStatus status;
        string description;
        string resultHash;
    }

    struct Config {
        uint256 depositRate; // 押金比例 (基点, 例如 1000 = 10%)
        uint256 penaltyRate; // 惩罚比例 (基点, 例如 5000 = 50%)
        uint256 taskExpiry; // 任务过期时间 (秒)
        uint256 completionDeadline; // 完成截止时间 (秒)
        uint256 platformFee; // 平台费用 (基点, 例如 250 = 2.5%)
        uint256 minBounty; // 最小赏金
        uint256 maxBounty; // 最大赏金
    }

    // ==================== 状态变量 ====================

    uint256 public nextTaskId = 1;
    uint256 public totalTasks;
    uint256 public activeTasks;
    uint256 public completedTasks;
    uint256 public platformFeesCollected;
    bool public paused;
    address public backend;

    Config public config;

    mapping(uint256 => Task) public tasks;
    mapping(address => uint256[]) public creatorTasks;
    mapping(address => uint256[]) public agentTasks;
    mapping(uint256 => uint256) public taskToCreatorIndex;
    mapping(uint256 => uint256) public taskToAgentIndex;
    uint256[] public openTasks;
    mapping(uint256 => uint256) public taskToOpenIndex;
    mapping(address => uint256) public agentActiveTaskCount;
    mapping(address => uint256) public agentCompletedTaskCount;
    mapping(address => uint256) public agentPenaltyCount;
    mapping(address => bool) public blacklistedAgents;

    // ==================== 事件 ====================

    event TaskCreated(
        uint256 indexed taskId, address indexed creator, uint256 bounty, uint256 deadline, string description
    );
    event TaskAccepted(uint256 indexed taskId, address indexed agent, uint256 deposit);
    event TaskCompleted(uint256 indexed taskId, address indexed agent, uint256 bounty, uint256 platformFee);
    event TaskRejected(uint256 indexed taskId, address indexed agent, uint256 refund);
    event TaskReclaimed(uint256 indexed taskId, address indexed creator, uint256 bounty);
    event TaskExpired(uint256 indexed taskId, address indexed creator, uint256 bounty);
    event TaskTimeout(uint256 indexed taskId, address indexed agent, uint256 penalty);
    event TaskResultSubmitted(uint256 indexed taskId, address indexed agent, string resultHash);
    event ConfigUpdated(uint256 depositRate, uint256 penaltyRate, uint256 taskExpiry, uint256 completionDeadline);
    event PlatformFeeUpdated(uint256 platformFee);
    event BackendUpdated(address indexed oldBackend, address indexed newBackend);
    event AgentBlacklisted(address indexed agent);
    event AgentUnblacklisted(address indexed agent);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    // ==================== 修饰符 ====================

    modifier taskExists(uint256 taskId) {
        require(tasks[taskId].creator != address(0), "Task does not exist");
        _;
    }

    modifier onlyTaskCreator(uint256 taskId) {
        require(tasks[taskId].creator == msg.sender, "Only task creator");
        _;
    }

    modifier onlyTaskAgent(uint256 taskId) {
        require(tasks[taskId].agent == msg.sender, "Only task agent");
        _;
    }

    modifier onlyBackend() {
        require(msg.sender == backend, "Only backend");
        _;
    }

    modifier validBounty(uint256 bounty) {
        require(bounty >= config.minBounty, "Bounty too low");
        require(bounty <= config.maxBounty, "Bounty too high");
        _;
    }

    modifier notBlacklisted(address agent) {
        require(!blacklistedAgents[agent], "Agent is blacklisted");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    // ==================== 构造函数 ====================

    constructor(address _backend) Owned(msg.sender) {
        backend = _backend;

        // 初始化默认配置
        config.depositRate = 1000; // 10%
        config.penaltyRate = 5000; // 50%
        config.taskExpiry = 7 days; // 7天
        config.completionDeadline = 3 days; // 3天
        config.platformFee = 250; // 2.5%
        config.minBounty = 0.01 ether; // 最小赏金
        config.maxBounty = 100 ether; // 最大赏金
    }

    // ==================== 核心功能 ====================

    /**
     * @dev 创建任务
     * @param description 任务描述
     * @param deadline 截止时间
     */
    function createTask(string calldata description, uint256 deadline)
        external
        payable
        nonReentrant
        whenNotPaused
        validBounty(msg.value)
        returns (uint256 taskId)
    {
        require(bytes(description).length > 0, "Description cannot be empty");
        require(deadline > block.timestamp, "Invalid deadline");
        require(deadline <= block.timestamp + 365 days, "Deadline too far");

        taskId = nextTaskId++;
        Task storage task = tasks[taskId];

        task.taskId = taskId;
        task.creator = msg.sender;
        task.bounty = msg.value;
        task.createdAt = block.timestamp;
        task.deadline = deadline;
        task.status = TaskStatus.Open;
        task.description = description;

        // 添加到创建者的任务列表
        creatorTasks[msg.sender].push(taskId);
        taskToCreatorIndex[taskId] = creatorTasks[msg.sender].length - 1;

        // 添加到开放任务列表
        openTasks.push(taskId);
        taskToOpenIndex[taskId] = openTasks.length - 1;

        totalTasks++;
        activeTasks++;

        emit TaskCreated(taskId, msg.sender, msg.value, deadline, description);
    }

    /**
     * @dev 接受任务
     * @param taskId 任务ID
     */
    function acceptTask(uint256 taskId)
        external
        payable
        nonReentrant
        whenNotPaused
        taskExists(taskId)
        notBlacklisted(msg.sender)
    {
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Open, "Task not available");
        require(block.timestamp <= task.deadline, "Task expired");
        require(msg.sender != task.creator, "Creator cannot accept own task");

        uint256 requiredDeposit = (task.bounty * config.depositRate) / 10000;
        require(msg.value == requiredDeposit, "Incorrect deposit amount");

        task.agent = msg.sender;
        task.deposit = msg.value;
        task.assignedAt = block.timestamp;
        task.status = TaskStatus.Assigned;

        // 添加到代理的任务列表
        agentTasks[msg.sender].push(taskId);
        taskToAgentIndex[taskId] = agentTasks[msg.sender].length - 1;

        // 从开放任务列表中移除
        _removeFromOpenTasks(taskId);

        agentActiveTaskCount[msg.sender]++;

        emit TaskAccepted(taskId, msg.sender, msg.value);
    }

    /**
     * @dev 确认任务完成
     * @param taskId 任务ID
     */
    function confirmTask(uint256 taskId)
        external
        nonReentrant
        whenNotPaused
        taskExists(taskId)
        onlyTaskCreator(taskId)
    {
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Assigned, "Task not assigned");
        require(bytes(task.resultHash).length > 0, "No result submitted");

        uint256 platformFee = (task.bounty * config.platformFee) / 10000;
        uint256 agentPayment = task.bounty - platformFee;

        // 支付给代理
        payable(task.agent).safeTransferETH(agentPayment);

        // 退还押金给代理
        payable(task.agent).safeTransferETH(task.deposit);

        // 平台费用
        platformFeesCollected += platformFee;

        // 更新状态
        task.status = TaskStatus.Completed;
        activeTasks--;
        completedTasks++;

        // 更新代理统计
        agentActiveTaskCount[task.agent]--;
        agentCompletedTaskCount[task.agent]++;

        emit TaskCompleted(taskId, task.agent, agentPayment, platformFee);
    }

    /**
     * @dev 拒绝任务结果
     * @param taskId 任务ID
     */
    function rejectTask(uint256 taskId)
        external
        nonReentrant
        whenNotPaused
        taskExists(taskId)
        onlyTaskCreator(taskId)
    {
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Assigned, "Task not assigned");
        require(bytes(task.resultHash).length > 0, "No result submitted");

        // 退还押金给代理
        payable(task.agent).safeTransferETH(task.deposit);

        // 重置任务状态
        task.agent = address(0);
        task.deposit = 0;
        task.assignedAt = 0;
        task.status = TaskStatus.Open;
        task.resultHash = "";

        // 从代理的任务列表中移除
        _removeFromAgentTasks(taskId);

        // 重新添加到开放任务列表
        openTasks.push(taskId);
        taskToOpenIndex[taskId] = openTasks.length - 1;

        agentActiveTaskCount[task.agent]--;

        emit TaskRejected(taskId, task.agent, task.deposit);
    }

    /**
     * @dev 提交任务结果
     * @param taskId 任务ID
     * @param resultHash 结果哈希
     */
    function submitResult(uint256 taskId, string calldata resultHash)
        external
        nonReentrant
        whenNotPaused
        taskExists(taskId)
        onlyTaskAgent(taskId)
    {
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Assigned, "Task not assigned");
        require(!_isTaskTimedOut(taskId), "Task timed out");
        require(bytes(resultHash).length > 0, "Result hash cannot be empty");

        task.resultHash = resultHash;

        emit TaskResultSubmitted(taskId, msg.sender, resultHash);
    }

    /**
     * @dev 回收过期任务
     * @param taskId 任务ID
     */
    function reclaimExpiredTask(uint256 taskId)
        external
        nonReentrant
        whenNotPaused
        taskExists(taskId)
        onlyTaskCreator(taskId)
    {
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Open, "Task not open");
        require(_isTaskExpired(taskId), "Task not expired");

        task.status = TaskStatus.Expired;
        activeTasks--;

        // 从开放任务列表中移除
        _removeFromOpenTasks(taskId);

        // 退还赏金给创建者
        payable(task.creator).safeTransferETH(task.bounty);

        emit TaskReclaimed(taskId, task.creator, task.bounty);
    }

    // ==================== 后端功能 ====================

    /**
     * @dev 处理超时任务
     * @param taskId 任务ID
     */
    function handleTimeout(uint256 taskId) external nonReentrant whenNotPaused onlyBackend taskExists(taskId) {
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Assigned, "Task not assigned");
        require(_isTaskTimedOut(taskId), "Task not timed out");

        // 更新任务状态
        task.status = TaskStatus.TimedOut;
        activeTasks--;

        // 更新代理统计
        agentActiveTaskCount[task.agent]--;
        agentPenaltyCount[task.agent]++;

        // 计算惩罚
        uint256 penalty = (task.deposit * config.penaltyRate) / 10000;
        uint256 refund = task.deposit - penalty;

        // 退还部分押金给代理
        if (refund > 0) {
            payable(task.agent).safeTransferETH(refund);
        }

        // 退还赏金给创建者
        payable(task.creator).safeTransferETH(task.bounty);

        // 惩罚金加入平台费用
        platformFeesCollected += penalty;

        emit TaskTimeout(taskId, task.agent, penalty);
    }

    /**
     * @dev 批量处理过期任务
     * @param taskIds 任务ID数组
     */
    function handleExpiredTasks(uint256[] calldata taskIds) external nonReentrant whenNotPaused onlyBackend {
        for (uint256 i = 0; i < taskIds.length; i++) {
            uint256 taskId = taskIds[i];
            if (tasks[taskId].creator != address(0) && _isTaskExpired(taskId)) {
                Task storage task = tasks[taskId];
                if (task.status == TaskStatus.Open) {
                    task.status = TaskStatus.Expired;
                    activeTasks--;
                    _removeFromOpenTasks(taskId);

                    emit TaskExpired(taskId, task.creator, task.bounty);
                }
            }
        }
    }

    // ==================== 查询功能 ====================

    function getTask(uint256 taskId) external view returns (Task memory) {
        require(tasks[taskId].creator != address(0), "Task does not exist");
        return tasks[taskId];
    }

    function getTasksByCreator(address creator) external view returns (uint256[] memory) {
        return creatorTasks[creator];
    }

    function getTasksByAgent(address agent) external view returns (uint256[] memory) {
        return agentTasks[agent];
    }

    function getOpenTasks() external view returns (uint256[] memory) {
        return openTasks;
    }

    function getTaskCount() external view returns (uint256) {
        return totalTasks;
    }

    function isTaskExpired(uint256 taskId) external view returns (bool) {
        return tasks[taskId].creator != address(0) && _isTaskExpired(taskId);
    }

    function isTaskTimedOut(uint256 taskId) external view returns (bool) {
        return tasks[taskId].creator != address(0) && _isTaskTimedOut(taskId);
    }

    function calculateRequiredDeposit(uint256 bounty) external view returns (uint256) {
        return (bounty * config.depositRate) / 10000;
    }

    function calculatePenalty(uint256 deposit) external view returns (uint256) {
        return (deposit * config.penaltyRate) / 10000;
    }

    function maxBounty() public view returns (uint256) {
        return config.maxBounty;
    }

    // ==================== 管理功能 ====================

    function setConfig(uint256 _depositRate, uint256 _penaltyRate, uint256 _taskExpiry, uint256 _completionDeadline)
        external
        onlyOwner
    {
        require(_depositRate <= 5000, "Deposit rate too high"); // 最大50%
        require(_penaltyRate <= 10000, "Penalty rate too high"); // 最大100%
        require(_taskExpiry >= 1 hours, "Task expiry too short");
        require(_completionDeadline >= 1 hours, "Completion deadline too short");

        config.depositRate = _depositRate;
        config.penaltyRate = _penaltyRate;
        config.taskExpiry = _taskExpiry;
        config.completionDeadline = _completionDeadline;

        emit ConfigUpdated(_depositRate, _penaltyRate, _taskExpiry, _completionDeadline);
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= 1000, "Platform fee too high"); // 最大10%
        config.platformFee = _platformFee;
        emit PlatformFeeUpdated(_platformFee);
    }

    function setBackend(address _backend) external onlyOwner {
        require(_backend != address(0), "Invalid backend address");
        address oldBackend = backend;
        backend = _backend;
        emit BackendUpdated(oldBackend, _backend);
    }

    function withdrawPlatformFees() external onlyOwner {
        uint256 fees = platformFeesCollected;
        require(fees > 0, "No fees to withdraw");

        platformFeesCollected = 0;
        payable(owner).safeTransferETH(fees);
    }

    function blacklistAgent(address agent) external onlyOwner {
        require(agent != address(0), "Invalid agent address");
        blacklistedAgents[agent] = true;
        emit AgentBlacklisted(agent);
    }

    function unblacklistAgent(address agent) external onlyOwner {
        require(agent != address(0), "Invalid agent address");
        blacklistedAgents[agent] = false;
        emit AgentUnblacklisted(agent);
    }

    // ==================== 紧急功能 ====================

    function emergencyPause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function emergencyUnpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function emergencyWithdraw(uint256 taskId) external onlyOwner whenPaused taskExists(taskId) {
        Task storage task = tasks[taskId];

        if (task.status == TaskStatus.Open) {
            // 退还赏金给创建者
            payable(task.creator).safeTransferETH(task.bounty);
        } else if (task.status == TaskStatus.Assigned) {
            // 退还赏金给创建者，押金给代理
            payable(task.creator).safeTransferETH(task.bounty);
            payable(task.agent).safeTransferETH(task.deposit);
        }

        task.status = TaskStatus.Expired;
    }

    // ==================== 内部函数 ====================

    function _removeFromOpenTasks(uint256 taskId) internal {
        if (openTasks.length == 0) return;

        uint256 index = taskToOpenIndex[taskId];
        uint256 lastIndex = openTasks.length - 1;

        // 防御性检查
        if (index > lastIndex || openTasks[index] != taskId) return;

        if (index != lastIndex) {
            uint256 lastTaskId = openTasks[lastIndex];
            openTasks[index] = lastTaskId;
            taskToOpenIndex[lastTaskId] = index;
        }
        openTasks.pop();
        delete taskToOpenIndex[taskId];
    }

    function _removeFromAgentTasks(uint256 taskId) internal {
        address agent = tasks[taskId].agent;
        uint256[] storage agentTaskList = agentTasks[agent];
        uint256 index = taskToAgentIndex[taskId];
        uint256 lastIndex = agentTaskList.length - 1;

        if (index != lastIndex) {
            uint256 lastTaskId = agentTaskList[lastIndex];
            agentTaskList[index] = lastTaskId;
            taskToAgentIndex[lastTaskId] = index;
        }
        agentTaskList.pop();
        delete taskToAgentIndex[taskId];
    }

    function _isTaskExpired(uint256 taskId) internal view returns (bool) {
        Task storage task = tasks[taskId];
        return task.status == TaskStatus.Open && block.timestamp > task.createdAt + config.taskExpiry;
    }

    function _isTaskTimedOut(uint256 taskId) internal view returns (bool) {
        Task storage task = tasks[taskId];
        return task.status == TaskStatus.Assigned && block.timestamp > task.assignedAt + config.completionDeadline;
    }

    // ==================== 接收ETH ====================

    receive() external payable {
        revert("Direct payments not allowed");
    }

    fallback() external payable {
        revert("Function not found");
    }
}
