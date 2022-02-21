```
// token 初始化参数
    constructor(
      string memory _name, 
      string memory _symbol,
      uint256 cap_, // token数量上限
      uint256 _manualMintLimit, // 可以手动铸造的token上限
      uint256 _lockFromBlock, // 锁定token线性解锁开始的块，
      uint256 _lockToBlock // 锁定token线性解锁结束的块，
    ) 
```
    constructor(
        JewelToken _govToken,//token 合约地址
        address _devaddr,   //开发者地址，结算奖励会给一定的token以及提现收取手续费LP地址
        address _liquidityaddr, //流动性地址，结算奖励会给一定的token
        address _comfundaddr,  //社区基金地址，结算奖励会给一定的token
        address _founderaddr, //创始人地址，结算奖励会给一定的token
        uint256 _rewardPerBlock, //每块奖励
        uint256 _startBlock,     //开始快
        uint256 _halvingAfterBlock, //多少块后减半，即多少块一个纪元
        uint256 _userDepFee,   //存lp的时候 current.globalAmount +_amount.mul(userDepFee) / (100); ，目前是0
        uint256 _devDepFee,     // 目前是0
        uint256[] memory _rewardMultiplier,//奖励乘数
        uint256[] memory _blockDeltaStartStage, // [0,1,1771,43201,129601,216001,604801,1209601] 根据用户提现的块在start和End之按不同的比例收取LP手续费
        uint256[] memory _blockDeltaEndStage, //  1770,43200,129600,216000,604800,1209600
        uint256[] memory _userFeeStage, //用户实际提现比例  //  75,92,96,98,99,995,9975,9999
        uint256[] memory _devFeeStage  //用户提现给开发者手续费比例  // 25,8,4,2,1,5,25,1
    ) 