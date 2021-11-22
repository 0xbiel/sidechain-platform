// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IRewards.sol";
import "./interfaces/ITokenFactory.sol";
import "./interfaces/IStashFactory.sol";
import "./interfaces/IStash.sol";
import "./interfaces/IRewardFactory.sol";
import "./interfaces/IStaker.sol";
import "./interfaces/ITokenMinter.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract Booster{
    using SafeERC20 for IERC20;

    address public immutable crv;

    uint256 public crvIncentive = 1000; //incentive to crv stakers
    uint256 public cvxIncentive = 450; //incentive to native token stakers
    uint256 public platformFee = 0; //possible fee for arbitrary means
    uint256 public constant MaxFees = 2000;
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public owner;
    address public feeManager;
    address public poolManager;
    address public immutable staker;
    address public immutable minter;
    address public rewardFactory;
    address public tokenFactory;
    address public treasury;
    address public cvxRewards;
    address public cvxcrvRewards;

    bool public isShutdown;

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address mainRewards;
       // address stash;
        bool shutdown;
    }

    //index(pid) -> pool
    PoolInfo[] public poolInfo;
    mapping(address => bool) public gaugeMap;

    event Deposited(address indexed user, uint256 indexed poolid, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed poolid, uint256 amount);

    constructor(address _staker, address _minter, address _crv) {
        isShutdown = false;
        staker = _staker;
        owner = msg.sender;
        feeManager = msg.sender;
        poolManager = msg.sender;
        treasury = address(0);
        minter = _minter;
        crv = _crv;
    }


    /// SETTER SECTION ///

    function setOwner(address _owner) external {
        require(msg.sender == owner, "!auth");
        owner = _owner;
    }

    function setFeeManager(address _feeM) external {
        require(msg.sender == feeManager, "!auth");
        feeManager = _feeM;
    }

    function setPoolManager(address _poolM) external {
        require(msg.sender == poolManager, "!auth");
        poolManager = _poolM;
    }

    function setFactories(address _rfactory, address _tfactory) external {
        require(msg.sender == owner, "!auth");
        
        rewardFactory = _rfactory;
        tokenFactory = _tfactory;
    }

    function setRewardContracts(address _cvxcrvRewards, address _cvxRewards) external {
        require(msg.sender == owner, "!auth");
        
        cvxcrvRewards = _cvxcrvRewards;
        cvxRewards = _cvxRewards;
    }

    function setFees(uint256 _crvFees, uint256 _cvxFees, uint256 _platform) external{
        require(msg.sender==feeManager, "!auth");

        uint256 total = _crvFees + _cvxFees + _platform;
        require(total <= MaxFees, ">MaxFees");

        //values must be within certain ranges     
        if(_crvFees >= 1000 && _crvFees <= 1500
            && _cvxFees >= 300 && _cvxFees <= 800
            && _platform <= 500){
            crvIncentive = _crvFees;
            cvxIncentive = _cvxFees;
            platformFee = _platform;
        }
    }

    function setTreasury(address _treasury) external {
        require(msg.sender==feeManager, "!auth");
        treasury = _treasury;
    }

    /// END SETTER SECTION ///

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    //create a new pool
    function addPool(address _lptoken, address _gauge) external returns(bool){
        require(msg.sender==poolManager && !isShutdown, "!add");
        require(_gauge != address(0) && _lptoken != address(0),"!param");

        //the next pool's pid
        uint256 pid = poolInfo.length;

        //create a tokenized deposit
        address token = ITokenFactory(tokenFactory).CreateDepositToken(_lptoken);
        //create a reward contract for rewards
        address newRewardPool = IRewardFactory(rewardFactory).CreateMainRewards(_gauge,token,pid);

        //add the new pool
        poolInfo.push(
            PoolInfo({
                lptoken: _lptoken,
                token: token,
                gauge: _gauge,
                mainRewards: newRewardPool,
                // stash: stash,
                shutdown: false
            })
        );
        gaugeMap[_gauge] = true;

        //set gauge redirect
        setGaugeRedirect(_gauge, newRewardPool);

        return true;
    }

    //shutdown pool
    function shutdownPool(uint256 _pid) external returns(bool){
        require(msg.sender==poolManager, "!auth");
        PoolInfo storage pool = poolInfo[_pid];

        //withdraw from gauge
        try IStaker(staker).withdrawAll(pool.lptoken,pool.gauge){
        }catch{}

        pool.shutdown = true;
        gaugeMap[pool.gauge] = false;
        return true;
    }

    //shutdown this contract.
    //  unstake and pull all lp tokens to this address
    //  only allow withdrawals
    function shutdownSystem() external{
        require(msg.sender == owner, "!auth");
        isShutdown = true;

        for(uint i=0; i < poolInfo.length; i++){
            PoolInfo storage pool = poolInfo[i];
            if (pool.shutdown) continue;

            address token = pool.lptoken;
            address gauge = pool.gauge;

            //withdraw from gauge
            try IStaker(staker).withdrawAll(token,gauge){
                pool.shutdown = true;
            }catch{}
        }
    }


    //deposit lp tokens and stake
    function deposit(uint256 _pid, uint256 _amount, bool _stake) public returns(bool){
        require(!isShutdown,"shutdown");
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.shutdown == false, "pool is closed");

        //send to proxy to stake
        address lptoken = pool.lptoken;
        IERC20(lptoken).safeTransferFrom(msg.sender, staker, _amount);

        //stake
        address gauge = pool.gauge;
        require(gauge != address(0),"!gauge setting");
        IStaker(staker).deposit(lptoken,gauge);

        address token = pool.token;
        if(_stake){
            //mint here and send to rewards on user behalf
            ITokenMinter(token).mint(address(this),_amount);
            address rewardContract = pool.mainRewards;
            IERC20(token).safeApprove(rewardContract,0);
            IERC20(token).safeApprove(rewardContract,_amount);
            IRewards(rewardContract).stakeFor(msg.sender,_amount);
        }else{
            //add user balance directly
            ITokenMinter(token).mint(msg.sender,_amount);
        }

        
        emit Deposited(msg.sender, _pid, _amount);
        return true;
    }

    //deposit all lp tokens and stake
    function depositAll(uint256 _pid, bool _stake) external returns(bool){
        address lptoken = poolInfo[_pid].lptoken;
        uint256 balance = IERC20(lptoken).balanceOf(msg.sender);
        deposit(_pid,balance,_stake);
        return true;
    }

    //withdraw lp tokens
    function _withdraw(uint256 _pid, uint256 _amount, address _from, address _to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        address lptoken = pool.lptoken;
        address gauge = pool.gauge;

        //remove lp balance
        address token = pool.token;
        ITokenMinter(token).burn(_from,_amount);

        //pull from gauge if not shutdown
        // if shutdown tokens will be in this contract
        if (!pool.shutdown) {
            IStaker(staker).withdraw(lptoken,gauge, _amount);
        }

        //return lp tokens
        IERC20(lptoken).safeTransfer(_to, _amount);

        emit Withdrawn(_to, _pid, _amount);
    }

    //withdraw lp tokens
    function withdraw(uint256 _pid, uint256 _amount) public returns(bool){
        _withdraw(_pid,_amount,msg.sender,msg.sender);
        return true;
    }

    //withdraw all lp tokens
    function withdrawAll(uint256 _pid) public returns(bool){
        address token = poolInfo[_pid].token;
        uint256 userBal = IERC20(token).balanceOf(msg.sender);
        withdraw(_pid, userBal);
        return true;
    }

    //allow reward contracts to send here and withdraw to user
    function withdrawTo(uint256 _pid, uint256 _amount, address _to) external returns(bool){
        address rewardContract = poolInfo[_pid].mainRewards;
        require(msg.sender == rewardContract,"!auth");

        _withdraw(_pid,_amount,msg.sender,_to);
        return true;
    }

    function setGaugeRedirect(address _gauge, address _rewards) internal returns(bool){
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("set_rewards_receiver(address)")), _rewards);
        IStaker(staker).execute(_gauge,uint256(0),data);
        return true;
    }

    function calculatePlatformFees(uint256 _amount) external view returns(uint256){
        uint256 _fees = _amount * (crvIncentive+cvxIncentive+platformFee) / FEE_DENOMINATOR;
        return _fees;
    }

    //claim platform fees
    function earmarkRewards() external {
        //crv balance: any crv on this contract is considered part of fees
        uint256 crvBal = IERC20(crv).balanceOf(address(this));

        if (crvBal > 0) {
            //crv on this contract have already been reduced to fees only
            //so divide appropriately between the three fee types
            uint256 denominator = (crvIncentive+cvxIncentive+platformFee);
            uint256 _crvIncentive = crvBal * crvIncentive / denominator;
            uint256 _cvxIncentive = crvBal * cvxIncentive / denominator;
            
            //send treasury
            if(treasury != address(0) && treasury != address(this) && platformFee > 0){
                //only subtract after address condition check
                uint256 _platform = crvBal * platformFee / denominator;
                crvBal -= _platform;
                IERC20(crv).safeTransfer(treasury, _platform);
            }

            //remove incentives from balance
            crvBal -= _crvIncentive - _cvxIncentive;

            //send cvxcrv share of crv to reward contract
            IERC20(crv).safeTransfer(cvxcrvRewards, _crvIncentive);
            IRewards(cvxcrvRewards).queueNewRewards(_crvIncentive);

            //send cvx share of crv to reward contract
            IERC20(crv).safeTransfer(cvxRewards, _cvxIncentive);
            IRewards(cvxRewards).queueNewRewards(_cvxIncentive);
        }
    }

}