// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../interfaces/IVoterProxy.sol";

interface IOperator{
    function isShutdown() external returns(bool);
}

interface IPlaceholder{
    function shutdownSystem(bool _isShutdown) external;
}

/*
Immutable voter proxy owner that enforces a used booster can not be used again
Allow arbitrary calls to other contracts, but limit how calls are made to VoterProxy

*/
contract VoterProxyOwner{

    address public constant voterproxy = address(0x989AEb4d175e16225E39E87d0D97A3360524AD80);
    address public immutable boosterPlaceholder;
    address public owner;
    address public pendingowner;
    bool public isSealed;

    mapping (address => bool) public usedOperators;
    mapping (address => address) public retireAccess;

    event TransferOwnership(address pendingOwner);
    event AcceptedOwnership(address newOwner);
    event OwnershipSealed();

    constructor(address _boosterPlaceholder) {
        //default to owner of voter proxy
        owner = IVoterProxy(voterproxy).owner();
        //check that placeholder has proper interface, can be in shutdown state from start
        require(IOperator(_boosterPlaceholder).isShutdown() == false, "no shutdown interface");
        boosterPlaceholder = _boosterPlaceholder;
        usedOperators[address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31)] = true;
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

    function sealOwnership() external onlyOwner{
        isSealed = true;
        emit OwnershipSealed();
    }

    function acceptPendingOwner() external onlyOwner{
        //transfer booster ownership to this owner
        IVoterProxy(voterproxy).acceptPendingOwner();
    }

    function setProxyOwner() external onlyOwner{
        //allow reverting ownership until sealed
        require(!isSealed, "ownership sealed");

        //transfer booster ownership to this owner
        IVoterProxy(voterproxy).setPendingOwner(owner);
    }

    function setRetireAccess(address _rmanager) external onlyOwner{
        //set access to call retireBooster
        retireAccess[IVoterProxy(voterproxy).operator()] = _rmanager;
    }

    function setPlaceholderState(bool _isShutdown) external onlyOwner{
        IPlaceholder(boosterPlaceholder).shutdownSystem(_isShutdown);
    }

    function setOperator(address _operator) external onlyOwner{
        require(_operator != address(0) && _operator != boosterPlaceholder,"!invalid address");
        require(!usedOperators[_operator],"used Op");
        require( !IOperator(_operator).isShutdown(), "already shutdown" );

        //set as used
        usedOperators[_operator] = true;

        //set proxy voter operator (aka booster)
        IVoterProxy(voterproxy).setOperator(_operator);
    }

    //if booster is in shutdown state, allow the associated address in retireAccess to call
    //this allows current booster/boosterOwner to remove itself as part of a shutdown sequence without giving it ownership
    //of the voter proxy owner
    function retireBooster() external{
        require(msg.sender == retireAccess[IVoterProxy(voterproxy).operator()], "!retireAccess");
        require( IOperator( IVoterProxy(voterproxy).operator() ).isShutdown(), "!shutdown" );


        //set proxy voter operator (aka booster) as placeholder
        IVoterProxy(voterproxy).setOperator(boosterPlaceholder);
    }

    
    //allow arbitrary calls to any contract other than the booster, as some contracts
    //may use ownership as voterproxy.owner() instead of local variable
    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external onlyOwner returns (bool, bytes memory) {
        require(_to != voterproxy, "!invalid target");

        (bool success, bytes memory result) = _to.call{value:_value}(_data);

        return (success, result);
    }

}