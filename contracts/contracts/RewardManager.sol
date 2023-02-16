// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IBooster.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IRewardHook.sol";


/*
    Basic manager for extra rewards
    
    Use booster owner for operations for now. Can be replaced when weighting
    can be handled on chain
*/
contract RewardManager{

    address public immutable booster;

    address public owner;
    address public pendingowner;

    address public rewardHook;
    address public immutable cvx;

    event PoolWeight(address indexed rewardContract, address indexed pool, uint256 weight);
    event PoolWeights(address indexed rewardContract, address[] pool, uint256[] weight);
    event PoolRewardToken(address indexed pool, address token);
    event PoolRewardContract(address indexed pool, address indexed hook, address rcontract);
    event PoolRewardContractClear(address indexed pool, address indexed hook);
    event DefaultHookSet(address hook);
    event HookSet(address indexed pool, address hook);
    event AddDistributor(address indexed rewardContract, address indexed _distro, bool _valid);
    event TransferOwnership(address pendingOwner);
    event AcceptedOwnership(address newOwner);

    constructor(address _booster, address _cvx, address _hook) {
        booster = _booster;
        cvx = _cvx;
        rewardHook = _hook;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "!owner");
        _;
    }

    function transferOwnership(address _owner) external onlyOwner{
        pendingowner = _owner;
        emit TransferOwnership(_owner);
    }

    function acceptOwnership() external {
        require(pendingowner == msg.sender, "!pendingowner");
        owner = pendingowner;
        pendingowner = address(0);
        emit AcceptedOwnership(owner);
    }

    //set default pool hook
    function setPoolHook(address _hook) external onlyOwner{
        rewardHook = _hook;
        emit DefaultHookSet(_hook);
    }

    //add reward token type to a given pool
    function setPoolRewardToken(address _pool, address _rewardToken) external onlyOwner{
        IRewards(_pool).addExtraReward(_rewardToken);
        emit PoolRewardToken(_pool, _rewardToken);
    }

    //add contracts to pool's hook list
    function setPoolRewardContract(address _pool, address _hook, address _rewardContract) external onlyOwner{
        IRewardHook(_hook).addPoolReward(_pool, _rewardContract);
        emit PoolRewardContract(_pool, _hook, _rewardContract);
    }

    //clear all contracts for pool on given hook
    function clearPoolRewardContractList(address _pool, address _hook) external onlyOwner{
        IRewardHook(_hook).clearPoolRewardList(_pool);
        emit PoolRewardContractClear(_pool, _hook);
    }

    //set pool weight on a given extra reward contract
    function setPoolWeight(address _rewardContract, address _pool, uint256 _weight) external onlyOwner{
        IRewards(_rewardContract).setWeight(_pool, _weight);
        emit PoolWeight(_rewardContract, _pool, _weight);
    }

    //set pool weights on a given extra reward contracts
    function setPoolWeights(address _rewardContract, address[] calldata _pools, uint256[] calldata _weights) external onlyOwner{
        IRewards(_rewardContract).setWeights(_pools, _weights);
        emit PoolWeights(_rewardContract, _pools, _weights);
    }

    //update a pool's reward hook
    function setPoolRewardHook(address _pool, address _hook) external onlyOwner{
        IRewards(_pool).setRewardHook(_hook);
        emit HookSet(_pool, _hook);
    }

    //set a reward contract distributor
    function setRewardDistributor(address _rewardContract, address _distro, bool _isValid) external onlyOwner{
        IRewards(_rewardContract).setDistributor(_distro, _isValid);
    }

}