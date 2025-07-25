// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAITask
 * @dev AI任务管理合约接口
 */
interface IAITask {
    // 枚举定义
    enum TaskStatus {
        Open, // 0 - 任务已发布，等待接单
        Assigned, // 1 - 任务已被接单
        Completed, // 2 - 任务已完成
        Rejected, // 3 - 任务被拒绝
        Expired, // 4 - 任务已过期（无人接单）
        TimedOut // 5 - 任务超时（接单后未完成）

    }

    // 任务结构体
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

    // 事件定义
    event TaskCreated(
        uint256 indexed taskId, address indexed creator, uint256 bounty, uint256 deadline, string description
    );

    event TaskAssigned(uint256 indexed taskId, address indexed agent, uint256 deposit, uint256 assignedAt);

    event TaskCompleted(
        uint256 indexed taskId, address indexed creator, address indexed agent, uint256 bounty, uint256 deposit
    );

    event TaskRejected(uint256 indexed taskId, address indexed creator, address indexed agent, uint256 penalty);

    event TaskTimeout(uint256 indexed taskId, address indexed agent, uint256 penalty);

    event TaskExpired(uint256 indexed taskId, address indexed creator, uint256 bounty);

    event TaskResultSubmitted(uint256 indexed taskId, address indexed agent, string resultHash);

    // 配置更新事件
    event ConfigUpdated(uint256 depositRate, uint256 penaltyRate, uint256 taskExpiry, uint256 completionDeadline);

    event PlatformFeeUpdated(uint256 platformFee);
    event BackendUpdated(address indexed oldBackend, address indexed newBackend);

    // 用户功能
    function createTask(string calldata description, uint256 deadline) external payable returns (uint256 taskId);

    function confirmTask(uint256 taskId) external;

    function rejectTask(uint256 taskId) external;

    function reclaimExpiredTaskBounty(uint256 taskId) external;

    // Agent功能
    function acceptTask(uint256 taskId) external payable;

    function submitResult(uint256 taskId, string calldata resultHash) external;

    // 后端功能
    function handleTimeout(uint256 taskId) external;

    function handleExpiredTasks(uint256[] calldata taskIds) external;

    // 查询功能
    function getTask(uint256 taskId) external view returns (Task memory);

    function getTasksByCreator(address creator) external view returns (uint256[] memory);

    function getTasksByAgent(address agent) external view returns (uint256[] memory);

    function getOpenTasks() external view returns (uint256[] memory);

    function getTaskCount() external view returns (uint256);

    function isTaskExpired(uint256 taskId) external view returns (bool);

    function isTaskTimedOut(uint256 taskId) external view returns (bool);

    function calculateRequiredDeposit(uint256 bounty) external view returns (uint256);

    function calculatePenalty(uint256 deposit) external view returns (uint256);

    // 配置功能
    function setConfig(uint256 _depositRate, uint256 _penaltyRate, uint256 _taskExpiry, uint256 _completionDeadline)
        external;

    function setPlatformFee(uint256 _platformFee) external;

    function setBackend(address _backend) external;

    function withdrawPlatformFees() external;

    // 紧急功能
    function emergencyPause() external;

    function emergencyUnpause() external;

    function emergencyWithdraw(uint256 taskId) external;
}
