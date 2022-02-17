每个纪元奖励列表
|纪元|token奖励数量|LP总数量|1LP=N token | user质押LP数量 | 用户token奖励数量| 用户token奖励锁定数量|  用户token奖励解锁数量| 
|-|-|-|-|-|-|-|-|
| 1 | 2 | 10 | 2/10=0.2 | 3 | 3*(0.2)=0.6 | 0.6*95%=0.57 | 0.6*5%=0.03 |
| 2 | 1 | 10 | 1/10=0.1 | 3 | 3*(0.1)=0.3 | 0.3*93%=0.279 | 3*7%=0.021 |

假设用户在第2个纪元领取奖励
|LP总数量| 1LP=N token|user质押LP数量 |用户总的奖励数 |用户锁定奖励数|用户解锁奖励数
|-|-|-|-|-|-|-|
| 10| 2/10+1/10=0.3 | 3 | 3*0.3=0.9 | 0.9*93%=0.837 | 0.9*7%=0.063|
**说明：随着奖励的产生，1LP=多少token的单价是在不断累计的**

用户此次领取后会记录用户领取的奖励这里是 user.rewardDebt=0.9 以及领取奖励区块 user.rewardDebtAtBlock=block.muber 
等到下次用户领取奖励时，还是会计算总的奖励然后减去用户已领取的奖励（user.rewardDebt），剩余的就是从上次领取奖励后当当前块用户获得的奖励了
