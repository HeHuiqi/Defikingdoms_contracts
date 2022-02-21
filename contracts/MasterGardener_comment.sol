// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./JewelToken.sol";
import "./Authorizable.sol";

// MasterGardener 是任何可用花园的主园丁。
//
// 请注意，它是可拥有的，并且拥有者拥有巨大的权力。所有权
// 一旦 JEWEL 足够，将转移到治理智能合约
// 分布式，社区可以自我管理。
//
contract MasterGardenerCopy is Ownable, Authorizable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // 每个用户的信息。
    struct UserInfo {
        uint256 amount; // 用户提供了多少 LP 代币。
        uint256 rewardDebt; // 奖励债务。=  user.amount.mul(pool.accGovTokenPerShare).div(1e12)
        uint256 rewardDebtAtBlock; // 用户最后一次领取奖励的区块数 第一次存钱时也会更新为当前快
        uint256 lastWithdrawBlock; // 用户取出的最后一个区块号。
        uint256 firstDepositBlock; // 用户第一次存款区块号。
        uint256 blockdelta; // 取款的时候 block.number - user.lastWithdrawBlock
        uint256 lastDepositBlock;//用户最后一个存款区块的区块号
        // 我们在这里做一些花哨的数学运算。基本上，在任何时间点，
        // 宝石数量
        // 授权给用户，但等待分发的是：
        //
        // 待定奖励 = (user.amount * pool.accGovTokenPerShare) - user.rewardDebt
        //
        // 每当用户将 LP 代币存入或提取到池中时。这是发生的事情：
        // 1. 池的 `accGovTokenPerShare`（和 `lastRewardBlock`）得到更新。
        // 2. 用户收到发送到他/她地址的待处理奖励。
        // 3. 用户的 `amount` 被更新。
        // 4. 用户的 `rewardDebt` 得到更新。
    }

    //用户全局信息
    struct UserGlobalInfo {
        uint256 globalAmount;   //全部金额
        mapping(address => uint256) referrals; // 推荐人存钱集合
        uint256 totalReferals;      //总推荐人数
        uint256 globalRefAmount; 
    }

    // 每个池的信息。
    struct PoolInfo {
        IERC20  lpToken; // LP代币合约地址。
        uint256 allocPoint; // 分配给这个池的分配点数。JEWEL 按块分配。
        uint256 lastRewardBlock; // JEWEL 分配发生的最后一个区块号。
        uint256 accGovTokenPerShare;  // 每股累计 JEWEL，乘以 1e12。见下文。
    }

    // 宝石令牌
    JewelToken public govToken;
    //一个 ETH/USDC 预言机（Chainlink）
    address public usdOracle;
    // 开发地址
    address public devaddr;
    // LP地址
    address public liquidityaddr;
    // 社区基金地址
    address public comfundaddr;
    // 创始人奖励
    address public founderaddr;
    // 每块创建的宝石。
    uint256 public REWARD_PER_BLOCK;
    // 早期珠宝制造商的奖金乘数。
    uint256[] public REWARD_MULTIPLIER; // 奖励乘数
    uint256[] public HALVING_AT_BLOCK; // 减半区块
    uint256[] public blockDeltaStartStage;//纪元的开始区块 [10,50,100...]
    uint256[] public blockDeltaEndStage;// 纪元的结束区块  [20,80,150...]
    uint256[] public userFeeStage;     //用户提取手续费 [25,8,4,2,1,5,25,10]
    uint256[] public devFeeStage;      //[25,8,4,2,1,5,25,10]
    uint256 public FINISH_BONUS_AT_BLOCK;
    uint256 public userDepFee;
    uint256 public devDepFee;

    // JEWEL 挖矿开始时的区块号。
    uint256 public START_BLOCK;
    
    //因此，例如，在 Epoch 1 期间获得的 Garden staking 奖励将是 5% 解锁，95% 锁定；
    //在 Epoch 2 期间将 7% 解锁，93% 锁定；
    //在 Epoch 3 期间将解锁 9%，锁定 91%，依此类推，直到 Epoch 51 之后，新领取的 Garden 奖励将不再锁定质押奖励。    
    uint256[] public PERCENT_LOCK_BONUS_REWARD; // 锁定 xx% 的奖金比例 [95,93,91,89,87,85...]
    uint256 public PERCENT_FOR_DEV; // 开发者赏金比例
    uint256 public PERCENT_FOR_LP; // LP基金比例
    uint256 public PERCENT_FOR_COM; // 社区基金比例
    uint256 public PERCENT_FOR_FOUNDERS; // 创始人基金比例

    // 每个池的信息。
    PoolInfo[] public poolInfo;
    mapping(address => uint256) public poolId1; // poolId1 从 1 开始，与 poolInfo 一起使用前减去 1
    // 每个持有 LP 代币的用户的信息。pid => 用户地址 => 信息
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // 用户全局信息
    mapping(address => UserGlobalInfo) public userGlobalInfo;
    mapping(IERC20 => bool) public poolExistence;
    // 总分配点。必须是所有池中所有分配点的总和。
    uint256 public totalAllocPoint = 0;
    //事件存款
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    //事件取款
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    //事件紧急取款
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    //事件发送治理令牌奖励
    event SendGovernanceTokenReward(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 lockAmount
    );
    //防止重复添加    
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "MasterGardener::nonDuplicated: duplicated");
        _;
    }

    constructor(
        JewelToken _govToken,//代币
        address _devaddr,   //开发者
        address _liquidityaddr, //流动性地址
        address _comfundaddr,  //社区基金地址
        address _founderaddr, //创始人地址
        uint256 _rewardPerBlock, //每块奖励
        uint256 _startBlock,     //开始快
        uint256 _halvingAfterBlock, //多少块后减半
        uint256 _userDepFee,   //存lp的时候 current.globalAmount +_amount.mul(userDepFee).div(100);
        uint256 _devDepFee,
        uint256[] memory _rewardMultiplier,//奖励乘数
        uint256[] memory _blockDeltaStartStage, //纪元的开始区块 [10,50,100...]
        uint256[] memory _blockDeltaEndStage,//纪元的结束区块  [20,80,150...]
        uint256[] memory _userFeeStage, //用户手续费  //[25,8,4,2,1,5,25,10]
        uint256[] memory _devFeeStage  //开发手续费   //[25,8,4,2,1,5,25,10]
    ) public {
        govToken = _govToken;
        devaddr = _devaddr;
        liquidityaddr = _liquidityaddr;
        comfundaddr = _comfundaddr;
        founderaddr = _founderaddr;
        REWARD_PER_BLOCK = _rewardPerBlock;
        START_BLOCK = _startBlock;
        userDepFee = _userDepFee;
        devDepFee = _devDepFee;
        REWARD_MULTIPLIER = _rewardMultiplier;
        blockDeltaStartStage = _blockDeltaStartStage;
        blockDeltaEndStage = _blockDeltaEndStage;
        userFeeStage = _userFeeStage;
        devFeeStage = _devFeeStage;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            //减半
            uint256 halvingAtBlock = _halvingAfterBlock.mul(i+1).add(_startBlock).add(1);
            HALVING_AT_BLOCK.push(halvingAtBlock);
        }
        //在多少块后解锁 比如一共50个纪元 只有十个奖励乘数  在第10个纪元就可以全部解锁了
        FINISH_BONUS_AT_BLOCK = _halvingAfterBlock
            .mul(REWARD_MULTIPLIER.length - 1)
            .add(_startBlock);
        HALVING_AT_BLOCK.push(uint256(-1));
    }

    // 获取池子的长度
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

     // 添加一个新的 lp 到池中。只能由所有者调用。
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(
            poolId1[address(_lpToken)] == 0,
            "MasterGardener::add: lp is already in pool"
        );
        //是否需要更新池子
        if (_withUpdate) {
            massUpdatePools();
        }
        // 该池子添加的区块号
        uint256 lastRewardBlock =
            block.number > START_BLOCK ? block.number : START_BLOCK;
        // 增加总量
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        // 池子+1 你添加的池子的编号 更新池子会用到
        poolId1[address(_lpToken)] = poolInfo.length + 1;
        // 标记已经加过 防止重复添加
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,   //lp token address
                allocPoint: _allocPoint,  //数量
                lastRewardBlock: lastRewardBlock,//该池子添加的区块号
                accGovTokenPerShare: 0    //更新池子的时候更新该数值
            })
        );
    }

    // 更新给定池的 JEWEL 分配点。只能由所有者调用。
    /**
      _pid    poolId1[address(_lpToken)] 获取
     */
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        //更新下自己添加的池子的数量
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

     // 更新所有池的奖励变量
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // 将给定池的奖励变量更新为最新的。
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        //当前快小于等于添加池子的 奖励快 不更新
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        // 池子没有钱 就不需要更新
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 GovTokenForDev;
        uint256 GovTokenForFarmer;
        uint256 GovTokenForLP;
        uint256 GovTokenForCom;
        uint256 GovTokenForFounders;
        (
            GovTokenForDev,//用于开发
            GovTokenForFarmer,//用于农夫
            GovTokenForLP,// 用于LP
            GovTokenForCom, // 用于基金
            GovTokenForFounders// 用于创始人
        ) = getPoolReward(pool.lastRewardBlock, block.number, pool.allocPoint);

        // 为农民铸造一些新的 JEWEL 代币并将它们存储在 MasterGardener 中。
        govToken.mint(address(this), GovTokenForFarmer);
        //更新accGovTokenPerShare值
        pool.accGovTokenPerShare = pool.accGovTokenPerShare.add(
            GovTokenForFarmer.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
        if (GovTokenForDev > 0) {
            govToken.mint(address(devaddr), GovTokenForDev);
            //开发基金在开始奖金期间锁定了 xx%。之后，锁定的资金会在 3 年内每个区块线性流失。
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                govToken.lock(address(devaddr), GovTokenForDev.mul(75).div(100));
            }
        }
        if (GovTokenForLP > 0) {
            govToken.mint(liquidityaddr, GovTokenForLP);
            //LP + 合伙基金随着时间的推移只有 xx% 被锁定，因为大部分资金都需要在早期用于激励和上市。在红利期结束后，锁定的金额将在每个区块线性下降。
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                govToken.lock(address(liquidityaddr), GovTokenForLP.mul(45).div(100));
            }
        }
        if (GovTokenForCom > 0) {
            govToken.mint(comfundaddr, GovTokenForCom);
            //社区基金在红利期间锁定了xx%，然后线性滴出。
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                govToken.lock(address(comfundaddr), GovTokenForCom.mul(85).div(100));
            }
        }
        if (GovTokenForFounders > 0) {
            govToken.mint(founderaddr, GovTokenForFounders);
            //创始人奖励在奖金期间锁定了 xx% 的资金，然后线性滴落。
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                govToken.lock(address(founderaddr), GovTokenForFounders.mul(95).div(100));
            }
        }
    }

    // |--------------------------------------|
    //  [20, 30, 40, 50, 60, 70, 80, 99999999]
    //  返回给定 _from 到 _to 块的奖励乘数。.
    /**
        uint256 _from,  //pool.lastRewardBlock
        uint256 _to,    //block.number
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 result = 0;
        if (_from < START_BLOCK) return 0;
        // HALVING_AT_BLOCK  减半区块
        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];
            if (i > REWARD_MULTIPLIER.length-1) return 0;

            if (_to <= endBlock) {
                uint256 m = _to.sub(_from).mul(REWARD_MULTIPLIER[i]);
                return result.add(m);
            }

            if (_from < endBlock) {
                uint256 m = endBlock.sub(_from).mul(REWARD_MULTIPLIER[i]);
                _from = endBlock;
                result = result.add(m);
            }
        }

        return result;
    }

    //获取锁定百分比   
    function getLockPercentage(uint256 _from, uint256 _to) public view returns (uint256) {
        uint256 result = 0;
        if (_from < START_BLOCK) return 100;

        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];
            if (i > PERCENT_LOCK_BONUS_REWARD.length-1) return 0;

            if (_to <= endBlock) {
                return PERCENT_LOCK_BONUS_REWARD[i];
            }
        }

        return result;
    }

    // 获取这个池子各个角色的奖励
    function getPoolReward(
        uint256 _from,  //pool.lastRewardBlock
        uint256 _to,    //block.number
        uint256 _allocPoint //pool.allocPoint
    )
        public
        view
        returns (
            uint256 forDev, //用于开发
            uint256 forFarmer, //用于农夫
            uint256 forLP,    // 用于LP
            uint256 forCom,    // 用于基金
            uint256 forFounders // 用于创始人
        )
    {
        //获取奖励乘数
        uint256 multiplier = getMultiplier(_from, _to);
        //获取占比的区块奖励
        uint256 amount =
            multiplier.mul(REWARD_PER_BLOCK).mul(_allocPoint).div(
                totalAllocPoint
            );

        //代币总供应量的 -  已经挖出来的币   
        uint256 GovernanceTokenCanMint = govToken.cap().sub(govToken.totalSupply());

        if (GovernanceTokenCanMint < amount) {
            // 如果在上限之前没有足够的治理代币可以铸造，
            // 只需将所有可能的代币都交给农夫。
            forDev = 0;
            forFarmer = GovernanceTokenCanMint;
            forLP = 0;
            forCom = 0;
            forFounders = 0;
        } else {
           // 否则，给农民他们的全部金额，也给一些
            // dev、LP、com 和创始人钱包的额外内容。
            forDev = amount.mul(PERCENT_FOR_DEV).div(100);
            forFarmer = amount;
            forLP = amount.mul(PERCENT_FOR_LP).div(100);
            forCom = amount.mul(PERCENT_FOR_COM).div(100);
            forFounders = amount.mul(PERCENT_FOR_FOUNDERS).div(100);
        }
    }

    // 查看待领取的奖励
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accGovTokenPerShare = pool.accGovTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 GovTokenForFarmer;
            (, GovTokenForFarmer, , , ) = getPoolReward(
                pool.lastRewardBlock,
                block.number,
                pool.allocPoint
            );
            accGovTokenPerShare = accGovTokenPerShare.add(
                GovTokenForFarmer.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accGovTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    function claimRewards(uint256[] memory _pids) public {
        for (uint256 i = 0; i < _pids.length; i++) {
          claimReward(_pids[i]);
        }
    }

    //领取池子奖励   
    function claimReward(uint256 _pid) public {
        updatePool(_pid);
        _harvest(_pid);
    }

    // 如果奖励来自奖励时间，则锁定奖励的百分比。
    function _harvest(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        // 仅当用户数量大于 0 时才收获。
        if (user.amount > 0) {
            // 计算待定奖励。这是用户的LP数量
            // 代币乘以池的 accGovTokenPerShare，减去
            // 用户的奖励债务。
            uint256 pending =
                user.amount.mul(pool.accGovTokenPerShare).div(1e12).sub(
                    user.rewardDebt
                );

           // 确保我们提供的代币不超过我们在
           // MasterGardener 合约。
            uint256 masterBal = govToken.balanceOf(address(this));

            if (pending > masterBal) {
                pending = masterBal;
            }

            if (pending > 0) {
                // 如果用户的代币余额为正数，则转账
                // 这些代币从 MasterGardener 到他们的钱包。
                govToken.transfer(msg.sender, pending);
                uint256 lockAmount = 0;
                if (user.rewardDebtAtBlock <= FINISH_BONUS_AT_BLOCK) {
                    // 如果我们在 FINISH_BONUS_AT_BLOCK 数字之前，我们需要
                    // 根据当前锁锁定其中一些令牌
                    // 他们刚刚收到的代币的百分比。
                    uint256 lockPercentage = getLockPercentage(block.number - 1, block.number);
                    lockAmount = pending.mul(lockPercentage).div(100);
                    //锁定用户奖励资产
                    govToken.lock(msg.sender, lockAmount);
                }

                // 将rewardDebtAtBlock 重置为用户的当前区块。
                user.rewardDebtAtBlock = block.number;

                emit SendGovernanceTokenReward(msg.sender, _pid, pending, lockAmount);
            }

             // 重新计算用户的rewardDebt。
            user.rewardDebt = user.amount.mul(pool.accGovTokenPerShare).div(1e12);
        }
    }

    //获取全局用户的数量
    function getGlobalAmount(address _user) public view returns (uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.globalAmount;
    }

    function getGlobalRefAmount(address _user) public view returns (uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.globalRefAmount;
    }

    function getTotalRefs(address _user) public view returns (uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.totalReferals;
    }

    function getRefValueOf(address _user, address _user2) public view returns (uint256) {
        UserGlobalInfo storage current = userGlobalInfo[_user];
        uint256 a = current.referrals[_user2];
        return a;
    }

    // 将 LP 代币存入 MasterGardener 用于 JEWEL 分配。
    //用户全局信息
    // struct UserGlobalInfo {
    //     uint256 globalAmount;   //全部金额
    //     mapping(address => uint256) referrals; //推荐人存钱集合
    //     uint256 totalReferals;      //总推荐人数
    //     uint256 globalRefAmount;    
    // }

    /**
       uint256 _pid,    池子id
       uint256 _amount, 存入金额
       address _ref     推荐人addrress
     */
    function deposit(uint256 _pid, uint256 _amount, address _ref) public nonReentrant {
        require(
            _amount > 0,
            "MasterGardener::deposit: amount must be greater than 0"
        );

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        UserInfo storage devr = userInfo[_pid][devaddr];
        UserGlobalInfo storage refer = userGlobalInfo[_ref];   //推荐人信息
        UserGlobalInfo storage current = userGlobalInfo[msg.sender]; //当前用户信息

        if (refer.referrals[msg.sender] > 0) {// 推荐的msg.sender存过钱
            refer.referrals[msg.sender] = refer.referrals[msg.sender] + _amount;
            refer.globalRefAmount = refer.globalRefAmount + _amount;
        } else {//推荐的msg.sender第一次存钱
            refer.referrals[msg.sender] = refer.referrals[msg.sender] + _amount;
            // 推荐数量+1
            refer.totalReferals = refer.totalReferals + 1;
            refer.globalRefAmount = refer.globalRefAmount + _amount;
        }

        current.globalAmount =current.globalAmount +_amount.mul(userDepFee).div(100);

        // 当用户存款时，我们需要提前更新池和收获，
        // 因为费率会改变。
        updatePool(_pid);
        _harvest(_pid);
        // 当前用户转账到池子
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        if (user.amount == 0) {
            user.rewardDebtAtBlock = block.number;
        }
        // 扣去万分之几的手续费
        user.amount = user.amount.add(
            _amount.sub(_amount.mul(userDepFee).div(10000))
        );
        user.rewardDebt = user.amount.mul(pool.accGovTokenPerShare).div(1e12);
        devr.amount = devr.amount.add(
            _amount.sub(_amount.mul(devDepFee).div(10000))
        );
        devr.rewardDebt = devr.amount.mul(pool.accGovTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
        if (user.firstDepositBlock > 0) {} else {
            user.firstDepositBlock = block.number;
        }
        user.lastDepositBlock = block.number;
    }

     // 从 MasterGardener 中提取 LP 代币。
    /**
       uint256 _pid,    池子id
       uint256 _amount, 存入金额
       address _ref     推荐人addrress
    */
    function withdraw(uint256 _pid, uint256 _amount, address _ref) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        UserGlobalInfo storage refer = userGlobalInfo[_ref];
        UserGlobalInfo storage current = userGlobalInfo[msg.sender];
        require(user.amount >= _amount, "MasterGardener::withdraw: not good");
        if (_ref != address(0)) {
            refer.referrals[msg.sender] = refer.referrals[msg.sender] - _amount;
            refer.globalRefAmount = refer.globalRefAmount - _amount;
        }
        current.globalAmount = current.globalAmount - _amount;

        updatePool(_pid);
        _harvest(_pid);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            if (user.lastWithdrawBlock > 0) {
                user.blockdelta = block.number - user.lastWithdrawBlock;
            } else {
                user.blockdelta = block.number - user.firstDepositBlock;
            }
            if (
                user.blockdelta == blockDeltaStartStage[0] ||
                block.number == user.lastDepositBlock
            ) {
                //在同一个区块中提取 LP 代币需要 25% 的费用，这是为了防止闪贷滥用
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[0]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[0]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[1] &&
                user.blockdelta <= blockDeltaEndStage[0]
            ) {
                  //如果用户在同一区块和 59 分钟之间存款和取款，则收取 8% 的费用。
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[1]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[1]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[2] &&
                user.blockdelta <= blockDeltaEndStage[1]
            ) {
                  //如果用户在 1 小时之后但在 1 天之前存款和取款，则收取 4% 的费用。
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[2]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[2]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[3] &&
                user.blockdelta <= blockDeltaEndStage[2]
            ) {
                 //如果用户在 1 天之后到 3 天之前存款和取款，则收取 2% 的费用。
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[3]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[3]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[4] &&
                user.blockdelta <= blockDeltaEndStage[3]
            ) {
                    //如果用户在 3 天后 5 天之前存款和取款，则收取 1% 的费用。
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[4]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[4]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[5] &&
                user.blockdelta <= blockDeltaEndStage[4]
            ) {
                 //如果用户在 5 天后但在 2 周之前提款，则用户存款和提款的费用为 0.5%。
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[5]).div(1000)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[5]).div(1000)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[6] &&
                user.blockdelta <= blockDeltaEndStage[5]
            ) {
                 //如果用户在 2 周后存款和取款，则收取 0.25% 的费用。
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[6]).div(10000)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[6]).div(10000)
                );
            } else if (user.blockdelta > blockDeltaStartStage[7]) {
                 //如果用户在 4 周后存款和取款，则收取 0.1% 的费用。
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[7]).div(10000)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[7]).div(10000)
                );
            }
            user.rewardDebt = user.amount.mul(pool.accGovTokenPerShare).div(1e12);
            emit Withdraw(msg.sender, _pid, _amount);
            user.lastWithdrawBlock = block.number;
        }
    }

    // 退出而不关心奖励。仅限紧急情况。这与相同的块取款具有相同的 25% 费用，以防止滥用此功能。
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        //从 Sushi 函数重新排序以防止重入风险
        uint256 amountToSend = user.amount.mul(75).div(100);
        uint256 devToSend = user.amount.mul(25).div(100);
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amountToSend);
        pool.lpToken.safeTransfer(address(devaddr), devToSend);
        emit EmergencyWithdraw(msg.sender, _pid, amountToSend);
    }

     // 安全的 GovToken 转移函数，以防四舍五入导致池中没有足够的 GovToken。
    function safeGovTokenTransfer(address _to, uint256 _amount) internal {
        uint256 govTokenBal = govToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > govTokenBal) {
            transferSuccess = govToken.transfer(_to, govTokenBal);
        } else {
            transferSuccess = govToken.transfer(_to, _amount);
        }
        require(transferSuccess, "MasterGardener::safeGovTokenTransfer: transfer failed");
    }

    // 用前一个开发者更新开发者地址。
    function dev(address _devaddr) public onlyAuthorized {
        devaddr = _devaddr;
    }

    // 更新完成奖励块
    function bonusFinishUpdate(uint256 _newFinish) public onlyAuthorized {
        FINISH_BONUS_AT_BLOCK = _newFinish;
    }

    // 更新区块减半
    function halvingUpdate(uint256[] memory _newHalving) public onlyAuthorized {
        HALVING_AT_BLOCK = _newHalving;
    }

   // 更新 Liquidityaddr
    function lpUpdate(address _newLP) public onlyAuthorized {
        liquidityaddr = _newLP;
    }

    // 更新comfundaddr
    function comUpdate(address _newCom) public onlyAuthorized {
        comfundaddr = _newCom;
    }

      // 更新创始人地址
    function founderUpdate(address _newFounder) public onlyAuthorized {
        founderaddr = _newFounder;
    }

     // 更新每块奖励
    function rewardUpdate(uint256 _newReward) public onlyAuthorized {
        REWARD_PER_BLOCK = _newReward;
    }

     // 更新奖励乘数数组
    function rewardMulUpdate(uint256[] memory _newMulReward) public onlyAuthorized {
        REWARD_MULTIPLIER = _newMulReward;
    }

    // 为普通用户更新 % lock
    function lockUpdate(uint256[] memory _newlock) public onlyAuthorized {
        PERCENT_LOCK_BONUS_REWARD = _newlock;
    }

    // 更新开发人员的 % 锁
    function lockdevUpdate(uint256 _newdevlock) public onlyAuthorized {
        PERCENT_FOR_DEV = _newdevlock;
    }

    // 更新 LP 的 % 锁
    function locklpUpdate(uint256 _newlplock) public onlyAuthorized {
        PERCENT_FOR_LP = _newlplock;
    }

    // 更新 COM 的 % 锁
    function lockcomUpdate(uint256 _newcomlock) public onlyAuthorized {
        PERCENT_FOR_COM = _newcomlock;
    }

    // 更新 Founders 的 % lock
    function lockfounderUpdate(uint256 _newfounderlock) public onlyAuthorized {
        PERCENT_FOR_FOUNDERS = _newfounderlock;
    }

    // 更新 START_BLOCK
    function starblockUpdate(uint256 _newstarblock) public onlyAuthorized {
        START_BLOCK = _newstarblock;
    }

    //获取最新的每块奖励
    function getNewRewardPerBlock(uint256 pid1) public view returns (uint256) {
        uint256 multiplier = getMultiplier(block.number - 1, block.number);
        if (pid1 == 0) {
            return multiplier.mul(REWARD_PER_BLOCK);
        } else {
            return
                multiplier
                    .mul(REWARD_PER_BLOCK)
                    .mul(poolInfo[pid1 - 1].allocPoint)
                    .div(totalAllocPoint);
        }
    }

    //获取2次操作的快间隔
    function userDelta(uint256 _pid) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.lastWithdrawBlock > 0) {
            uint256 estDelta = block.number - user.lastWithdrawBlock;
            return estDelta;
        } else {
            uint256 estDelta = block.number - user.firstDepositBlock;
            return estDelta;
        }
    }

    //修改最后一次提取区块号
    function reviseWithdraw(uint256 _pid, address _user, uint256 _block) public onlyAuthorized() {
        UserInfo storage user = userInfo[_pid][_user];
        user.lastWithdrawBlock = _block;
    }
     //修改第一次存钱区块号
    function reviseDeposit(uint256 _pid, address _user, uint256 _block) public onlyAuthorized() {
        UserInfo storage user = userInfo[_pid][_user];
        user.firstDepositBlock = _block;
    }
    // 设置开始区块
    function setStageStarts(uint256[] memory _blockStarts) public onlyAuthorized() {
        blockDeltaStartStage = _blockStarts;
    }
    // 设置结束区块
    function setStageEnds(uint256[] memory _blockEnds) public onlyAuthorized() {
        blockDeltaEndStage = _blockEnds;
    }
    // 设置用户手续费
    function setUserFeeStage(uint256[] memory _userFees) public onlyAuthorized() {
        userFeeStage = _userFees;
    }
    // 设置开发奖励手续费
    function setDevFeeStage(uint256[] memory _devFees) public onlyAuthorized() {
        devFeeStage = _devFees;
    }

    function setDevDepFee(uint256 _devDepFees) public onlyAuthorized() {
        devDepFee = _devDepFees;
    }

    function setUserDepFee(uint256 _usrDepFees) public onlyAuthorized() {
        userDepFee = _usrDepFees;
    }
    // 收回令牌所有权
    function reclaimTokenOwnership(address _newOwner) public onlyAuthorized() {
        govToken.transferOwnership(_newOwner);
    }
}
