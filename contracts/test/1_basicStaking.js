// const { BN, constants, expectEvent, expectRevert, time } = require('openzeppelin-test-helpers');
const { BN, time } = require('openzeppelin-test-helpers');
var jsonfile = require('jsonfile');
var contractList = jsonfile.readFileSync('./contracts.json');

const VoterProxy = artifacts.require("VoterProxy");
const Booster = artifacts.require("Booster");
const ProxyFactory = artifacts.require("ProxyFactory");
const TokenFactory = artifacts.require("TokenFactory");
const RewardFactory = artifacts.require("RewardFactory");
const DepositToken = artifacts.require("DepositToken");
const ConvexRewardPool = artifacts.require("ConvexRewardPool");
const IERC20 = artifacts.require("IERC20");
const ERC20 = artifacts.require("ERC20");


const unlockAccount = async (address) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "evm_unlockUnknownAccount",
        params: [address],
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        return resolve(result);
      }
    );
  });
};


const getChainContracts = () => {
  let NETWORK = config.network;//process.env.NETWORK;
  console.log("network: " +NETWORK);
  var contracts = {};

  if(NETWORK == "debugArb"){
    contracts = contractList.arbitrum;
  }

  console.log("using crv: " +contracts.curve.crv);
  return contracts;
}

const advanceTime = async (secondsElaspse) => {
  await time.increase(secondsElaspse);
  await time.advanceBlock();
  console.log("\n  >>>>  advance time " +(secondsElaspse/86400) +" days  >>>>\n");
}
const day = 86400;

contract("Deploy Proxy", async accounts => {
  it("should deploy contracts", async () => {

    let deployer = "0x947B7742C403f20e5FaCcDAc5E092C943E7D0277";
    let multisig = "0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB";
    let addressZero = "0x0000000000000000000000000000000000000000"
    let voteproxy = "0x989AEb4d175e16225E39E87d0D97A3360524AD80";

    let userA = accounts[0];
    let userB = accounts[1];
    let userC = accounts[2];
    let userD = accounts[3];
    let userZ = "0xAAc0aa431c237C2C0B5f041c8e59B3f1a43aC78F";
    var userNames = {};
    userNames[userA] = "A";
    userNames[userB] = "B";
    userNames[userC] = "C";
    userNames[userD] = "D";
    userNames[userZ] = "Z";

    let chainContracts = getChainContracts();
    let crv = await IERC20.at(chainContracts.curve.crv);

    //send deployer eth
    await web3.eth.sendTransaction({from:userA, to:deployer, value:web3.utils.toWei("10.0", "ether") });
    console.log("sent eth to deployer");

    console.log("\n\n >>>> deploy system >>>>")

    //system
    var usingproxy;
    var found = false;
    while(!found){
      var newproxy = await VoterProxy.new(crv.address,{from:deployer});
      console.log("deployed proxy to " +newproxy.address);
      if(newproxy.address.toLowerCase() == voteproxy.toLowerCase()){
        found=true;
        usingproxy = newproxy;
        console.log("proxy deployed to proper address");
      }
    }

    console.log("using proxy: " +usingproxy.address);

    //deploy booster
    let booster = await Booster.new(usingproxy.address, crv.address,{from:deployer});
    console.log("booster at: " +booster.address);

    //set proxy operator
    await usingproxy.setOperator(booster.address,{from:deployer});
    console.log("set voterproxy operator");

    //deploy proxy factory
    let pfactory = await ProxyFactory.new({from:deployer});
    console.log("pfactory at: " +pfactory.address);

    //deploy factories
    let tokenFactory = await TokenFactory.new(booster.address, pfactory.address,{from:deployer});
    console.log("token factory at: " +tokenFactory.address);

    let tokenImp = await DepositToken.new(booster.address,{from:deployer});
    console.log("deposit token impl: " +tokenImp.address);
    await tokenFactory.setImplementation(tokenImp.address,{from:deployer});
    console.log("token impl set");

    let rewardFactory = await RewardFactory.new(booster.address, usingproxy.address, crv.address, pfactory.address,{from:deployer});
    console.log("reward factory at: " +rewardFactory.address);

    let rewardImp = await ConvexRewardPool.new({from:deployer});
    console.log("reward pool impl: " +rewardImp.address);
    await rewardFactory.setImplementation(rewardImp.address,{from:deployer});
    console.log("reward impl set");

    await booster.setFactories(rewardFactory.address, tokenFactory.address,{from:deployer});
    console.log("booster factories set");

    console.log("\n\n --- deployed ----")

    /////// set up pool

    console.log("\n\n >>>> add pool >>>>")
    //tricrypto
    let gauge = "0x555766f3da968ecBefa690Ffd49A2Ac02f47aa5f";
    let curvelp = await IERC20.at("0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2");
    let curvepool = "0x960ea3e3C7FB317332d990873d354E18d7645590";
    let curvePoolFactory = "0xabC000d88f23Bb45525E447528DBF656A9D55bf5";


    await booster.addPool(curvelp.address, gauge, curvePoolFactory,{from:deployer});
    console.log("pool added");
    var plength = await booster.poolLength();
    console.log("pool count: " +plength);

    var poolInfo = await booster.poolInfo(plength-1);
    console.log("pool info: " +JSON.stringify(poolInfo) );

    var curvelpCheck = await ERC20.at(poolInfo.lptoken);
    console.log("curve lp token: ")
    console.log("address: " +curvelpCheck.address);
    await curvelpCheck.name().then(a=>console.log("name = " +a))
    await curvelpCheck.symbol().then(a=>console.log("symbol = " +a))
    await curvelpCheck.decimals().then(a=>console.log("decimals = " +a))


    var depositTokenCheck = await ERC20.at(poolInfo.token);
    console.log("deposit token: ")
    console.log("address: " +depositTokenCheck.address);
    await depositTokenCheck.name().then(a=>console.log("name = " +a))
    await depositTokenCheck.symbol().then(a=>console.log("symbol = " +a))
    await depositTokenCheck.decimals().then(a=>console.log("decimals = " +a))


    var rpool = await ConvexRewardPool.at(poolInfo.rewards);
    console.log("rewards pool info: ");
    console.log("address: " +rpool.address);
    await rpool.curveGauge().then(a=>console.log("curveGauge = " +a));
    await rpool.convexStaker().then(a=>console.log("convexStaker = " +a));
    await rpool.convexBooster().then(a=>console.log("convexBooster = " +a));
    await rpool.convexToken().then(a=>console.log("convexToken = " +a));
    await rpool.convexPoolId().then(a=>console.log("convexPoolId = " +a));
    await rpool.totalSupply().then(a=>console.log("totalSupply = " +a));
    await rpool.rewardHook().then(a=>console.log("rewardHook = " +a));
    await rpool.crv().then(a=>console.log("crv = " +a));
    await rpool.rewardLength().then(a=>console.log("rewardLength = " +a));
    await rpool.rewards(0).then(a=>console.log("rewards(0) = " +JSON.stringify(a) ));

    console.log("\n\n --- pool initialized ----");

    ////  user staking

    console.log("\n\n >>>> simulate staking >>>>");
    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))

    //transfer lp tokens
    let lpHolder = "0x555766f3da968ecbefa690ffd49a2ac02f47aa5f";
    await unlockAccount(lpHolder);
    await curvelp.transfer(userA,web3.utils.toWei("100.0", "ether"),{from:lpHolder,gasPrice:0});
    console.log("lp tokens transfered");

    var lpbalance = await curvelp.balanceOf(userA);
    console.log("lp balance: " +lpbalance);

    await curvelp.approve(booster.address,web3.utils.toWei("1000000.0", "ether"), {from:userA} );
    console.log("approved lp to booster");

    await booster.depositAll(0, true, {from:userA});
    console.log("deposit and staked in booster");

    await rpool.balanceOf(userA).then(a=>console.log("balance in rewards: " +a))
    await rpool.totalSupply().then(a=>console.log("totalSupply = " +a));

    // await rpool.getReward(userA, {from:userA});
    // console.log("claimed");
    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))

    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));
    await advanceTime(day*3);
    await rpool.earned.call(userA).then(a=>console.log("earned: " +JSON.stringify(a) ));

    await rpool.getReward(userA, {from:userA});
    console.log("claimed");

    await crv.balanceOf(userA).then(a=>console.log("crv on wallet: " +a))

    return;
  });
});

