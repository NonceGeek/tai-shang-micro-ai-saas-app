// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin/proxy/utils/Initializable.sol";
import "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin/access/OwnableUpgradeable.sol";
import "openzeppelin/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin/utils/PausableUpgradeable.sol";
import "./interfaces/IAITask.sol";
import "./AITaskStorage.sol";

/**
 * @title AITask
 * @dev AI任务管理合约 - UUPS可升级版本
 * @notice 支持任务创建、接单、完成确认和资金管理
 */
contract AITask is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AITaskStorage,
    IAITask
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     * @param _backend 后端服务地址
     */
    function initialize(address _backend) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _initializeStorage();
        _getMainStorage().backend = _backend;
    }

    // ==================== 用户功能 ====================

    /**
     * @dev 创建新任务
     * @param description 任务描述
     * @param deadline 任务截止时间
     * @return taskId 任务ID
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

        MainStorage storage mainStorage = _getMainStorage();
        MappingStorage storage mappingStorage = _getMappingStorage();

        taskId = mainStorage.nextTaskId++;

        // 创建任务
        Task storage newTask = mappingStorage.tasks[taskId];
        newTask.taskId = taskId;
        newTask.creator = msg.sender;
        newTask.bounty = msg.value;
        newTask.createdAt = block.timestamp;
        newTask.deadline = deadline;
        newTask.status = TaskStatus.Open;
        newTask.description = description;

        // 更新统计和映射
        mainStorage.totalTasks++;
        mainStorage.activeTasks++;
        _addTaskToCreator(msg.sender, taskId);
        _addToOpenTasks(taskId);

        emit TaskCreated(taskId, msg.sender, msg.value, deadline, description);
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
        Task storage task = _getTask(taskId);
        require(task.status == TaskStatus.Assigned, "Task not assigned");
        require(bytes(task.resultHash).length > 0, "No result submitted");

        MainStorage storage mainStorage = _getMainStorage();
        MappingStorage storage mappingStorage = _getMappingStorage();

        // 更新任务状态
        task.status = TaskStatus.Completed;
        mainStorage.activeTasks--;
        mainStorage.completedTasks++;

        // 更新代理统计
        mappingStorage.agentActiveTaskCount[task.agent]--;
        mappingStorage.agentCompletedTaskCount[task.agent]++;

        // 计算费用
        uint256 platformFee = _calculatePlatformFee(task.bounty);
        uint256 agentReward = task.bounty - platformFee;

        // 转账
        mainStorage.platformFeesCollected += platformFee;

        // 退还押金 + 支付赏金
        uint256 totalPayment = task.deposit + agentReward;

        (bool success,) = payable(task.agent).call{value: totalPayment}("");
        require(success, "Payment failed");

        emit TaskCompleted(taskId, msg.sender, task.agent, agentReward, task.deposit);
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
        Task storage task = _getTask(taskId);
        require(task.status == TaskStatus.Assigned, "Task not assigned");

        MainStorage storage mainStorage = _getMainStorage();
        MappingStorage storage mappingStorage = _getMappingStorage();

        // 更新任务状态
        task.status = TaskStatus.Rejected;
        mainStorage.activeTasks--;

        // 更新代理统计
        mappingStorage.agentActiveTaskCount[task.agent]--;
        mappingStorage.agentPenaltyCount[task.agent]++;

        // 计算惩罚
        uint256 penalty = _calculatePenalty(task.deposit);
        uint256 refund = task.deposit - penalty;

        // 退还部分押金给代理
        if (refund > 0) {
            (bool success,) = payable(task.agent).call{value: refund}("");
            require(success, "Refund failed");
        }

        // 退还赏金给创建者
        (bool success,) = payable(task.creator).call{value: task.bounty}("");
        require(success, "Bounty refund failed");

        // 惩罚金加入平台费用
        mainStorage.platformFeesCollected += penalty;

        emit TaskRejected(taskId, msg.sender, task.agent, penalty);
    }

    /**
     * @dev 回收过期任务赏金
     * @param taskId 任务ID
     */
    function reclaimExpiredTaskBounty(uint256 taskId)
        external
        nonReentrant
        whenNotPaused
        taskExists(taskId)
        onlyTaskCreator(taskId)
    {
        Task storage task = _getTask(taskId);
        require(task.status == TaskStatus.Open, "Task not open");
        require(_isTaskExpired(taskId), "Task not expired yet");

        MainStorage storage mainStorage = _getMainStorage();

        // 更新任务状态
        task.status = TaskStatus.Expired;
        mainStorage.activeTasks--;

        // 从开放任务列表中移除
        _removeFromOpenTasks(taskId);

        // 退还赏金
        (bool success,) = payable(task.creator).call{value: task.bounty}("");
        require(success, "Bounty reclaim failed");

        emit TaskExpired(taskId, msg.sender, task.bounty);
    }

    // ==================== Agent功能 ====================

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
        Task storage task = _getTask(taskId);
        require(task.status == TaskStatus.Open, "Task not available");
        require(!_isTaskExpired(taskId), "Task expired");
        require(msg.sender != task.creator, "Creator cannot accept own task");

        uint256 requiredDeposit = _calculateRequiredDeposit(task.bounty);
        require(msg.value >= requiredDeposit, "Insufficient deposit");

        MappingStorage storage mappingStorage = _getMappingStorage();

        // 更新任务
        task.agent = msg.sender;
        task.deposit = msg.value;
        task.assignedAt = block.timestamp;
        task.status = TaskStatus.Assigned;

        // 更新映射和统计
        _addTaskToAgent(msg.sender, taskId);
        _removeFromOpenTasks(taskId);
        mappingStorage.agentActiveTaskCount[msg.sender]++;

        emit TaskAssigned(taskId, msg.sender, msg.value, block.timestamp);
    }

    /**
     * @dev 提交任务结果
     * @param taskId 任务ID
     * @param resultHash 结果哈希
     */
    function submitResult(uint256 taskId, string calldata resultHash)
        external
        whenNotPaused
        taskExists(taskId)
        onlyTaskAgent(taskId)
    {
        Task storage task = _getTask(taskId);
        require(task.status == TaskStatus.Assigned, "Task not assigned");
        require(!_isTaskTimedOut(taskId), "Task timed out");
        require(bytes(resultHash).length > 0, "Result hash cannot be empty");

        task.resultHash = resultHash;

        emit TaskResultSubmitted(taskId, msg.sender, resultHash);
    }

    // ==================== 后端功能 ====================

    /**
     * @dev 处理超时任务
     * @param taskId 任务ID
     */
    function handleTimeout(uint256 taskId) external nonReentrant whenNotPaused onlyBackend taskExists(taskId) {
        Task storage task = _getTask(taskId);
        require(task.status == TaskStatus.Assigned, "Task not assigned");
        require(_isTaskTimedOut(taskId), "Task not timed out");

        MainStorage storage mainStorage = _getMainStorage();
        MappingStorage storage mappingStorage = _getMappingStorage();

        // 更新任务状态
        task.status = TaskStatus.TimedOut;
        mainStorage.activeTasks--;

        // 更新代理统计
        mappingStorage.agentActiveTaskCount[task.agent]--;
        mappingStorage.agentPenaltyCount[task.agent]++;

        // 计算惩罚
        uint256 penalty = _calculatePenalty(task.deposit);
        uint256 refund = task.deposit - penalty;

        // 退还部分押金给代理
        if (refund > 0) {
            (bool success,) = payable(task.agent).call{value: refund}("");
            require(success, "Refund failed");
        }

        // 退还赏金给创建者
        (bool success,) = payable(task.creator).call{value: task.bounty}("");
        require(success, "Bounty refund failed");

        // 惩罚金加入平台费用
        mainStorage.platformFeesCollected += penalty;

        emit TaskTimeout(taskId, task.agent, penalty);
    }

    /**
     * @dev 批量处理过期任务
     * @param taskIds 任务ID数组
     */
    function handleExpiredTasks(uint256[] calldata taskIds) external nonReentrant whenNotPaused onlyBackend {
        for (uint256 i = 0; i < taskIds.length; i++) {
            uint256 taskId = taskIds[i];
            if (_taskExists(taskId) && _isTaskExpired(taskId)) {
                Task storage task = _getTask(taskId);
                if (task.status == TaskStatus.Open) {
                    task.status = TaskStatus.Expired;
                    _getMainStorage().activeTasks--;
                    _removeFromOpenTasks(taskId);

                    emit TaskExpired(taskId, task.creator, task.bounty);
                }
            }
        }
    }

    // ==================== 查询功能 ====================

    function getTask(uint256 taskId) external view returns (Task memory) {
        require(_taskExists(taskId), "Task does not exist");
        return _getTask(taskId);
    }

    function getTasksByCreator(address creator) external view returns (uint256[] memory) {
        return _getMappingStorage().creatorTasks[creator];
    }

    function getTasksByAgent(address agent) external view returns (uint256[] memory) {
        return _getMappingStorage().agentTasks[agent];
    }

    function getOpenTasks() external view returns (uint256[] memory) {
        return _getMappingStorage().openTasks;
    }

    function getTaskCount() external view returns (uint256) {
        return _getMainStorage().totalTasks;
    }

    function isTaskExpired(uint256 taskId) external view returns (bool) {
        return _taskExists(taskId) && _isTaskExpired(taskId);
    }

    function isTaskTimedOut(uint256 taskId) external view returns (bool) {
        return _taskExists(taskId) && _isTaskTimedOut(taskId);
    }

    function calculateRequiredDeposit(uint256 bounty) external view returns (uint256) {
        return _calculateRequiredDeposit(bounty);
    }

    function calculatePenalty(uint256 deposit) external view returns (uint256) {
        return _calculatePenalty(deposit);
    }

    function maxBounty() public view returns (uint256) {
        return _getConfigStorage().maxBounty;
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

        ConfigStorage storage config = _getConfigStorage();
        config.depositRate = _depositRate;
        config.penaltyRate = _penaltyRate;
        config.taskExpiry = _taskExpiry;
        config.completionDeadline = _completionDeadline;

        emit ConfigUpdated(_depositRate, _penaltyRate, _taskExpiry, _completionDeadline);
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= 1000, "Platform fee too high"); // 最大10%
        _getConfigStorage().platformFee = _platformFee;
        emit PlatformFeeUpdated(_platformFee);
    }

    function setBackend(address _backend) external onlyOwner {
        require(_backend != address(0), "Invalid backend address");
        address oldBackend = _getMainStorage().backend;
        _getMainStorage().backend = _backend;
        emit BackendUpdated(oldBackend, _backend);
    }

    function withdrawPlatformFees() external onlyOwner {
        uint256 fees = _getMainStorage().platformFeesCollected;
        require(fees > 0, "No fees to withdraw");

        _getMainStorage().platformFeesCollected = 0;

        (bool success,) = payable(owner()).call{value: fees}("");
        require(success, "Fee withdrawal failed");
    }

    // ==================== 紧急功能 ====================

    function emergencyPause() external onlyOwner {
        _pause();
    }

    function emergencyUnpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(uint256 taskId) external onlyOwner whenPaused taskExists(taskId) {
        Task storage task = _getTask(taskId);

        if (task.status == TaskStatus.Open) {
            // 退还赏金给创建者
            (bool success,) = payable(task.creator).call{value: task.bounty}("");
            require(success, "Emergency withdrawal failed");
        } else if (task.status == TaskStatus.Assigned) {
            // 退还赏金给创建者，押金给代理
            (bool success1,) = payable(task.creator).call{value: task.bounty}("");
            (bool success2,) = payable(task.agent).call{value: task.deposit}("");
            require(success1 && success2, "Emergency withdrawal failed");
        }

        task.status = TaskStatus.Expired;
    }

    // ==================== UUPS升级授权 ====================

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ==================== 接收ETH ====================

    receive() external payable {
        revert("Direct payments not allowed");
    }

    fallback() external payable {
        revert("Function not found");
    }
}
