// SPDX-License-Identifier: MIT

    pragma solidity 0.8.17;

    import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
    import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
    import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
    import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
    import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

    contract RewardPool is Initializable, OwnableUpgradeable, UUPSUpgradeable {
        using SafeMathUpgradeable for uint256;
        using SafeERC20Upgradeable for IERC20Upgradeable;

        // Info of each user.
        struct UserInfo {
            uint256 amount;
            uint256 rewardLPDebt;
        }

        // Info of each pool.
        struct PoolInfo {
            string amtype;
            IERC20Upgradeable lpToken;
            uint256 allocPoint;
            uint256 accLPPerShare;
            uint256 lastTotalLPReward;
        }

        // Info of each pool.
        PoolInfo[] public poolInfo;
        // total LP Staked
        mapping(uint256 => uint256) public totalLPStaked;
        uint256 public totalReward;
        uint256 lastRewardBalance;

        // Info of each user that stakes LP t
        mapping (uint256 => mapping (address => UserInfo)) public userInfo;
        // Total allocation poitns. Must be the sum of all allocation points in all pools.
        uint256 public totalAllocPoint;
        // withdraw status
        bool public withdrawStatus;

        event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
        event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
        event setAdmin(address oldAdminaddr, address newAdminaddr);
        event setWithdrawStatus(bool withdrawStatus);

        function initialize(
        ) initializer public {
            __Ownable_init();
            __UUPSUpgradeable_init();
        }

        function poolLength() external view returns (uint256) {
            return poolInfo.length;
        }

        // Add a new lp to the pool. Can only be called by the owner.
        // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
        function add(uint256 _allocPoint, string memory _type, IERC20Upgradeable _lptoken, bool _withUpdate) public onlyOwner {
            if (_withUpdate) {
                massUpdatePools();
            }
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
            totalLPStaked[poolInfo.length] = 0;
            poolInfo.push(PoolInfo({
                amtype: _type,
                lpToken: _lptoken,
                allocPoint: _allocPoint,
                accLPPerShare: 0,
                lastTotalLPReward: totalReward
            }));
        }

        // Update the given pool's ERC20 allocation point. Can only be called by the owner.
        function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
            if (_withUpdate) {
                massUpdatePools();
            }
            totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
            poolInfo[_pid].allocPoint = _allocPoint;
        }

        // View function to see pending ERC20s on frontend.
        function pendingERC20(uint256 _pid, address _user) external view returns (uint256) {
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][_user];

            uint256 accLPPerShare = pool.accLPPerShare;
            uint256 lpSupply = totalLPStaked[_pid];
            uint256 rewardBalance = pool.lpToken.balanceOf(address(this));
            uint256 _totalReward = totalReward;
            if (rewardBalance > lastRewardBalance) {
                _totalReward = _totalReward.add(rewardBalance.sub(lastRewardBalance));
            }
            if (_totalReward > pool.lastTotalLPReward && lpSupply != 0) {
                uint256 reward = _totalReward.sub(pool.lastTotalLPReward).mul(pool.allocPoint).div(totalAllocPoint);
                accLPPerShare = accLPPerShare.add(reward.mul(1e12).div(lpSupply));
            }
            return user.amount.mul(accLPPerShare).div(1e12).sub(user.rewardLPDebt);
        }

        // Update reward vairables for all pools. Be careful of gas spending!
        function massUpdatePools() public {
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                updatePool(pid);
            }
        }

        // Update reward variables of the given pool to be up-to-date.
        function updatePool(uint256 _pid) public {
            PoolInfo storage pool = poolInfo[_pid];

            uint256 rewardBalance = pool.lpToken.balanceOf(address(this));
            uint256 _totalReward = totalReward.add(rewardBalance.sub(lastRewardBalance));
            lastRewardBalance = rewardBalance;
            totalReward = _totalReward;

            uint256 lpSupply = totalLPStaked[_pid];
            if (lpSupply == 0) {
                pool.lastTotalLPReward = 0;
                return;
            }
            uint256 reward = _totalReward.sub(pool.lastTotalLPReward).mul(pool.allocPoint).div(totalAllocPoint);
            pool.accLPPerShare = pool.accLPPerShare.add(reward.mul(1e12).div(lpSupply));
            pool.lastTotalLPReward = _totalReward;
        }

        // Deposit LP tokens to MasterChef for ERC20 allocation.
        function deposit(uint256 _pid, address _user) public onlyOwner {
            uint256 _amount = 10**18;
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][_user];
            updatePool(_pid);
            if (user.amount > 0) {
                uint256 lpReward = user.amount.mul(pool.accLPPerShare).div(1e12).sub(user.rewardLPDebt);
                pool.lpToken.safeTransfer(_user, lpReward);
                lastRewardBalance = pool.lpToken.balanceOf(address(this));
            }
            totalLPStaked[_pid] = totalLPStaked[_pid].add(_amount);
            user.amount = user.amount.add(_amount);
            user.rewardLPDebt = user.amount.mul(pool.accLPPerShare).div(1e12);
            emit Deposit(_user, _pid, _amount);
        }

        // Withdraw LP tokens from MasterChef.
        function withdraw(uint256 _pid, address _user) public onlyOwner {
            require(withdrawStatus != true, "Withdraw not allowed");
            uint256 _amount = 10**18;
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][_user];
            require(user.amount >= _amount, "withdraw: not good");
            updatePool(_pid);
            if (user.amount > 0) {
                uint256 lpReward = user.amount.mul(pool.accLPPerShare).div(1e12).sub(user.rewardLPDebt);
                pool.lpToken.safeTransfer(_user, lpReward);
                lastRewardBalance = pool.lpToken.balanceOf(address(this));
            }
            totalLPStaked[_pid] = totalLPStaked[_pid].sub(_amount);
            user.amount = 0;
            user.rewardLPDebt = user.amount.mul(pool.accLPPerShare).div(1e12);
            emit Withdraw(_user, _pid, _amount);
        }

        function claim(uint256 _pid) public {
            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][msg.sender];
            updatePool(_pid);

            uint256 lpReward = user.amount.mul(pool.accLPPerShare).div(1e12).sub(user.rewardLPDebt);
            pool.lpToken.safeTransfer(msg.sender, lpReward);
            lastRewardBalance = pool.lpToken.balanceOf(address(this));

            user.rewardLPDebt = user.amount.mul(pool.accLPPerShare).div(1e12);
        }

        // Update withdraw status
        function updateWithdrawStatus(bool _status) public onlyOwner {
            require(withdrawStatus != _status, "Already same status");
            emit setWithdrawStatus(withdrawStatus);
            withdrawStatus = _status;
        }

        // Safe ERC20 transfer function to admin.
        function emergencyWithdrawRewardTokens(IERC20Upgradeable _token, address _to, uint256 _amount) public onlyOwner {
            require(_to != address(0), "Invalid to address");
            _token.safeTransfer(_to, _amount);
        }

        function _authorizeUpgrade(address newImplementation)
            internal
            onlyOwner
            override
        {}
    }