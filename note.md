

# 安装依赖

```
npm i @openzeppelin/contracts@3.4 
npm install @openzeppelin/contracts-upgradeable

```

# 部署JewelToken合约和MasterGarden合约步骤
1. 部署JewelToken合约
2. 根据部署完的JewelToken合约地址来部署MasterGarden合约
3. 调用JewelToken合约的transferOwnership(garden_address)将owner转移给garden，这样garden才可以mint()新币来分发奖励
4. 当奖励分发完成再调用Garden的reclaimTokenOwnership(original_token_owner_address)返还权限


# DefiKingdoms Contracts

UniswapV2Factory - 0x9014B937069918bd319f80e8B3BB4A2cf6FAA5F7
one1jq2tjdcxnyvt6vvlsr5t8w629nm04f0hfepala

UniswapV2Router02 - 0x24ad62502d1C652Cc7684081169D04896aC20f30
one1yjkky5pdr3jje3mggzq3d8gy394vyresl69pgt

JewelToken 0x72Cb10C6bfA5624dD07Ef608027E366bd690048F
one1wt93p34l543ym5r77cyqyl3kd0tfqpy0eyd6n0

Bank - 0xA9cE83507D872C5e1273E745aBcfDa849DAA654F
one1488gx5rasuk9uynnuaz6hn76sjw65e206pmljg

Banker - 0x3685Ec75Ea531424Bbe67dB11e07013ABeB95f1e
one1x6z7ca022v2zfwlx0kc3upcp82ltjhc7ucgz82

MasterGardener - 0xDB30643c71aC9e2122cA0341ED77d09D5f99F924
one1mvcxg0r34j0zzgk2qdq76a7sn40en7fy7lytq4

Airdrop - 0xa678d193fEcC677e137a00FEFb43a9ccffA53210
one15eudryl7e3nhuym6qrl0ksafenl62vsszleqj2

Profiles - 0xabD4741948374b1f5DD5Dd7599AC1f85A34cAcDD
one14028gx2gxa937hw4m46entqlsk35etxaln7glh



1 如果用户在4 个 Epoch后退出，则收取0.01%的费用
2 如果用户在2 个 Epoch之后但 4 个 Epoch 之前退出，则收取0.25%的费用
3 如果用户在5 天之后但在 2 个 Epoch 之前退出，则收取0.5%的费用
4 如果用户在5 天内提款，则收取1%的费用。
5 如果用户在3 天内提款，则收取2%的费用。
6 如果用户在24 小时内提款，则收取4%的费用。
7 如果用户在1 小时内提款，则收取8%的费用。
8 如果用户在同一区块内退出，则收取25%的罚金。



JEWEL 代币的硬上限为 500,000,000(5亿) 个代币。
预铸10,000,000（1千万） JEWEL代币将按如下方式预先铸造和分配：
5,000,000（5百万） JEWEL ：用于资助游戏的未来发展。随着功能的完成，这些令牌将被锁定并在设定的时间表内释放。
2,000,000（2百万） JEWEL ：分配给项目推广，包括营销、空投等。这些代币也有时间锁定，在未来几年慢慢释放，以确保始终有资金可用于营销游戏并获得新玩家和投资者。
2,000,000（2百万） JEWEL ：分配给初始流动性。这些代币将与ONE代币匹配形成初始流动性池，不会被提取或出售。	
1,000,000（1百万） JEWEL ：根据创始团队的发布工作分配奖金和时间。其中一半将在发布时授予，另一半将随着时间的推移授予。


我们在这里做一些花哨的数学。 基本上，在任何时间点，授予用户但待分配的 JEWEL 数量为：
待定奖励 = (user.amount * pool.accGovTokenPerShare) - user.rewardDebt

每当用户将 LP 代币存入或提取到池中时。 这是发生的事情：
1. 池的`accGovTokenPerShare`（和`lastRewardBlock`）得到更新。
2. 用户收到发送到他/她地址的待定奖励。
3. 用户的“amount”得到更新。
4. 用户的`rewardDebt`得到更新。