// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IAITask.sol";

/**
 * @title AITaskStorage
 * @dev AI任务管理合约的存储层
 * @notice 使用存储槽避免升级时的存储冲突
 */
abstract contract AITaskStorage {
    // 存储槽常量 - 避免升级时的存储冲突
    bytes32 constant MAIN_STORAGE_SLOT = keccak256("AITask.main.storage");
    bytes32 constant CONFIG_STORAGE_SLOT = keccak256("AITask.config.storage");
    bytes32 constant MAPPING_STORAGE_SLOT = keccak256("AITask.mapping.storage");

    // 主要存储结构
    struct MainStorage {
        uint256 nextTaskId;
        uint256 totalTasks;
        uint256 activeTasks;
        uint256 completedTasks;
        uint256 platformFeesCollected;
        bool paused;
        address backend;
    }

    // 配置存储结构
    struct ConfigStorage {
        uint256 depositRate; // 押金比例 (基点, 例如 1000 = 10%)
        uint256 penaltyRate; // 惩罚比例 (基点, 例如 5000 = 50%)
        uint256 taskExpiry; // 任务过期时间 (秒)
        uint256 completionDeadline; // 完成截止时间 (秒)
        uint256 platformFee; // 平台费用 (基点, 例如 250 = 2.5%)
        uint256 minBounty; // 最小赏金
        uint256 maxBounty; // 最大赏金
    }

    // 映射存储结构
    struct MappingStorage {
        mapping(uint256 => IAITask.Task) tasks;
        mapping(address => uint256[]) creatorTasks;
        mapping(address => uint256[]) agentTasks;
        mapping(uint256 => uint256) taskToCreatorIndex;
        mapping(uint256 => uint256) taskToAgentIndex;
        uint256[] openTasks;
        mapping(uint256 => uint256) taskToOpenIndex;
        mapping(address => uint256) agentActiveTaskCount;
        mapping(address => uint256) agentCompletedTaskCount;
        mapping(address => uint256) agentPenaltyCount;
        mapping(address => bool) blacklistedAgents;
    }

    // 获取存储槽的函数
    function _getMainStorage() internal pure returns (MainStorage storage $) {
        assembly {
            $.slot := 0x1234567890123456789012345678901234567890123456789012345678901234
        }
    }

    function _getConfigStorage() internal pure returns (ConfigStorage storage $) {
        assembly {
            $.slot := 0x2345678901234567890123456789012345678901234567890123456789012345
        }
    }

    function _getMappingStorage() internal pure returns (MappingStorage storage $) {
        assembly {
            $.slot := 0x3456789012345678901234567890123456789012345678901234567890123456
        }
    }

    // 存储初始化函数
    function _initializeStorage() internal {
        MainStorage storage mainStorage = _getMainStorage();
        ConfigStorage storage configStorage = _getConfigStorage();

        // 初始化主要存储
        if (mainStorage.nextTaskId == 0) {
            mainStorage.nextTaskId = 1;
        }

        // 初始化配置存储
        if (configStorage.depositRate == 0) {
            configStorage.depositRate = 1000; // 10%
            configStorage.penaltyRate = 5000; // 50%
            configStorage.taskExpiry = 7 days; // 7天
            configStorage.completionDeadline = 3 days; // 3天
            configStorage.platformFee = 250; // 2.5%
            configStorage.minBounty = 0.01 ether; // 最小赏金
            configStorage.maxBounty = 100 ether; // 最大赏金
        }
    }

    // 辅助函数
    function _addTaskToCreator(address creator, uint256 taskId) internal {
        MappingStorage storage mappingStorage = _getMappingStorage();
        mappingStorage.creatorTasks[creator].push(taskId);
        mappingStorage.taskToCreatorIndex[taskId] = mappingStorage.creatorTasks[creator].length - 1;
    }

    function _addTaskToAgent(address agent, uint256 taskId) internal {
        MappingStorage storage mappingStorage = _getMappingStorage();
        mappingStorage.agentTasks[agent].push(taskId);
        mappingStorage.taskToAgentIndex[taskId] = mappingStorage.agentTasks[agent].length - 1;
    }

    function _addToOpenTasks(uint256 taskId) internal {
        MappingStorage storage mappingStorage = _getMappingStorage();
        mappingStorage.openTasks.push(taskId);
        mappingStorage.taskToOpenIndex[taskId] = mappingStorage.openTasks.length - 1;
    }

    function _removeFromOpenTasks(uint256 taskId) internal {
        MappingStorage storage mappingStorage = _getMappingStorage();
        uint256 index = mappingStorage.taskToOpenIndex[taskId];
        uint256 lastIndex = mappingStorage.openTasks.length - 1;

        if (index != lastIndex) {
            uint256 lastTaskId = mappingStorage.openTasks[lastIndex];
            mappingStorage.openTasks[index] = lastTaskId;
            mappingStorage.taskToOpenIndex[lastTaskId] = index;
        }

        mappingStorage.openTasks.pop();
        delete mappingStorage.taskToOpenIndex[taskId];
    }

    // 查询函数
    function _getTask(uint256 taskId) internal view returns (IAITask.Task storage) {
        return _getMappingStorage().tasks[taskId];
    }

    function _taskExists(uint256 taskId) internal view returns (bool) {
        return _getMappingStorage().tasks[taskId].creator != address(0);
    }

    // 状态检查函数
    function _isTaskExpired(uint256 taskId) internal view returns (bool) {
        IAITask.Task storage task = _getTask(taskId);
        return
            task.status == IAITask.TaskStatus.Open && block.timestamp > task.createdAt + _getConfigStorage().taskExpiry;
    }

    function _isTaskTimedOut(uint256 taskId) internal view returns (bool) {
        IAITask.Task storage task = _getTask(taskId);
        return task.status == IAITask.TaskStatus.Assigned
            && block.timestamp > task.assignedAt + _getConfigStorage().completionDeadline;
    }

    // 计算函数
    function _calculateRequiredDeposit(uint256 bounty) internal view returns (uint256) {
        return (bounty * _getConfigStorage().depositRate) / 10000;
    }

    function _calculatePenalty(uint256 deposit) internal view returns (uint256) {
        return (deposit * _getConfigStorage().penaltyRate) / 10000;
    }

    function _calculatePlatformFee(uint256 bounty) internal view returns (uint256) {
        return (bounty * _getConfigStorage().platformFee) / 10000;
    }

    // 修饰符
    modifier taskExists(uint256 taskId) {
        require(_taskExists(taskId), "Task does not exist");
        _;
    }

    modifier onlyTaskCreator(uint256 taskId) {
        require(_getTask(taskId).creator == msg.sender, "Only task creator");
        _;
    }

    modifier onlyTaskAgent(uint256 taskId) {
        require(_getTask(taskId).agent == msg.sender, "Only task agent");
        _;
    }

    modifier onlyBackend() {
        require(msg.sender == _getMainStorage().backend, "Only backend");
        _;
    }

    modifier validBounty(uint256 bounty) {
        ConfigStorage storage config = _getConfigStorage();
        require(bounty >= config.minBounty, "Bounty too low");
        require(bounty <= config.maxBounty, "Bounty too high");
        _;
    }

    modifier notBlacklisted(address agent) {
        require(!_getMappingStorage().blacklistedAgents[agent], "Agent is blacklisted");
        _;
    }
}
