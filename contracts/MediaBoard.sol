//"SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interface/IMediaBoard.sol";
import "./MediaBoard.sol";
import "./AlbumNFT.sol";
import "hardhat/console.sol";

contract MediaBoard is Initializable, OwnableUpgradeable{

    struct AlbumData {
        address artist;
        // pool reward data
        uint rewardIndex;
        uint votes;
        mapping(address=>uint) userEarned;
        mapping(address=>uint) userIndex;
        mapping(address=>uint) userVotes;
    }

    struct RewardData {
        uint starts;
        uint interval;
        uint rewardIndex;
        uint votes;
        mapping(address=>uint) userEarned;
        mapping(address=>uint) userIndex;
        mapping(address=>uint) userVotes;
    }

    // constants
    uint private constant MULTIPLIER = 1e18;

    // PARAMS
    address public teamAddress;
    mapping(address=>AlbumData) public albumToData; // album => votes number
    address[] public albumsList;
    
    // daily rewards related
    uint public startTimeStamp; // the start timestamp of the periodic reward
    uint public interval; // the seconds of a reward period
    uint public currentSeqNumber; // the seq number of reward
    // uint public dailyRewardIndex;
    // uint public dailyRewardVotes; // number of votes
    mapping(uint=>RewardData) public seqToRewardData; // seq => reward data
    // mapping(address=>uint) public userDailyEarned;
    // mapping(address=>uint) public userDailyRewardIndex;
    // mapping(address=>uint) public userDailyBalance;

    // album rewards related
    mapping(address=>uint) public albumRewardsIndex; // pool address => pool reward index
    mapping(address=>uint) public albumRewardsBalance; // pool address => pool reward tokens
    mapping(address=>mapping(address=>uint)) public userAlbumRewardsEarned; // album => user => earn
    mapping(address=>mapping(address=>uint)) public userAlbumRewardIndex; // album => user => index
    mapping(address=>mapping(address=>uint)) public userAlbumVotes; // album => user => votes


    // EVENTS
    event NewAlbum(address owner, address album);
    event NewVote(address from, address to, uint amount);
    event ClaimAlbumRewards(address account, address album, uint reward);
    event ClaimDailyRewards(address account, uint reward);

    function initialize(address _team, uint _startTimeStamp, uint _interval) initializer public{
        teamAddress = address(_team);
        startTimeStamp = _startTimeStamp;
        interval = _interval;
        __Ownable_init(msg.sender);
    }

    function setInterval(uint _interval) external onlyOwner{
        require(_interval > 60 * 60 * 24);
        interval = _interval;
    }

    function setStartTimeStamp( uint _startTimeStamp) external onlyOwner{
        require(_startTimeStamp > 0);
        startTimeStamp = _startTimeStamp;
    }

    function newAlbum(string memory _name, string memory _symbol) external {
        TrackNFT album = new TrackNFT(_name, _symbol);
        albumsList.push(address(album));
        albumRewardsIndex[address(album)] = 0;
        albumRewardsBalance[address(album)] = 0;

        AlbumData storage data = albumToData[address(album)];
        data.artist = msg.sender;
        console.log("new album address", address(album));

        emit NewAlbum(msg.sender, address(album));
    }

    function vote(address _album) external payable {
        albumToData[_album].votes += 1;

        uint amount = calculateVotePrice(albumToData[_album].votes);
        require(msg.value >= amount, "balance insufficient");

        _distributeAmount(amount, _album);

        // refund?
        uint refund = msg.value - amount;
        if (refund > 0){
            (bool sent , ) = msg.sender.call{value : refund}("");
            require(sent, "Failed to refund to user");
        }

        TrackNFT(_album).mint(msg.sender, albumToData[_album].votes);

        emit NewVote(msg.sender, _album, amount);
    }

    
    function calculateDailyRewards(address _account) public view returns (uint){
        // RewardData memory reward = seqToRewardData[currentSeqNumber];
        uint votes = seqToRewardData[currentSeqNumber].userVotes[_account];
// console.log("calculate daily rewards", votes, dailyRewardIndex , userDailyRewardIndex[_account]);
        return (votes * (seqToRewardData[currentSeqNumber].rewardIndex - seqToRewardData[currentSeqNumber].userIndex[_account])) ;
    }

    function _updateDailyRewards(address _account, uint _seq) private {
        RewardData storage reward = seqToRewardData[_seq];
        reward.userEarned[_account] += calculateDailyRewards(_account);
        reward.userIndex[_account] = reward.rewardIndex;
        reward.userVotes[_account] += 1;
    }

    function _updateDailyRewardsIndex(uint _amount, uint _seq) private {
        RewardData storage reward = seqToRewardData[_seq];
        if (reward.votes > 0){
            // console.log("updateDailyRewardIndex",dailyRewardIndex,  _amount, dailyRewardVotes);
            reward.rewardIndex += (_amount ) / reward.votes;
        }
        reward.votes += 1;
    }

    function calculateAlbumRewards(address _account, address _album) public view returns (uint) {
        uint votes = userAlbumVotes[_album][_account];
        return (votes * (albumRewardsIndex[_album] - userAlbumRewardIndex[_album][_account])) ;
    }

    function _updateAlbumRewards(address _account, address _album) private {
        userAlbumRewardsEarned[_album][_account] += calculateAlbumRewards(_account, _album);
        userAlbumRewardIndex[_album][_account] = albumRewardsIndex[_album];
        userAlbumVotes[_album][_account] += 1;
    }

    function _updateAlbumRewardsIndex(uint _amount, address _album) private {
        if (albumRewardsBalance[_album] > 0){
            albumRewardsIndex[_album] += (_amount * MULTIPLIER) / albumRewardsBalance[_album];
        }
        albumRewardsBalance[_album] += 1;
    }

    function _distributeAmount(uint _amount, address _album) internal{
        ( , uint amount_mul_2) = Math.tryMul(_amount, 2);
        (, uint dailyPoolAmount) = Math.tryDiv(_amount, 2);
        (, uint albumPoolAmount) = Math.tryDiv(amount_mul_2, 5);
        (, uint teamAmount) = Math.tryDiv(_amount, 20);

        // 
        uint seq = (block.timestamp - startTimeStamp) / interval;
        require(seq >= currentSeqNumber, "invalid current seq number");
        // RewardData storage rewardData = seqToRewardData(seq);
        if (seq > currentSeqNumber){
            currentSeqNumber = seq;
            // emit NewRewardPool(seq);
        }

        // update daily rewards
        _updateDailyRewards(msg.sender, currentSeqNumber);
        _updateDailyRewardsIndex(dailyPoolAmount, currentSeqNumber);

        // update album rewards
        _updateAlbumRewards(msg.sender, _album);
        _updateAlbumRewardsIndex(albumPoolAmount, _album);

        // distribute to others
        console.log("send to artist", albumToData[_album].artist);
        console.log("send amount", _amount);
        (bool sent,) = albumToData[_album].artist.call{value: teamAmount}("");
        require(sent, "Failed to send token to artist");
        (sent, ) = teamAddress.call{value: teamAmount}("");
        require(sent, "Failed to send token to team");
    }

    function calculateVotePrice(uint _counter) public pure returns (uint price){
        return MULTIPLIER * _counter * (_counter + 1) / 40000;
    }

    function calculateAlbumVotePrice(address _album) public view returns (uint price){
        uint votes = albumToData[_album].votes;
        return MULTIPLIER * (votes + 1) * (votes + 2) / 40000;
    }


    function claimDailyRewards(uint _seq) public returns (uint){
        _updateDailyRewards(msg.sender, _seq);
        RewardData storage rewardData = seqToRewardData[_seq];
        uint reward = rewardData.userEarned[msg.sender];
        console.log("claim daily reward", reward);
        if (reward > 0) {
            rewardData.userEarned[msg.sender] = 0;
            (bool sent, ) = msg.sender.call{value: reward}("");
            require(sent, "Failed to send reward to user");
        }
        emit ClaimDailyRewards(msg.sender, reward);
        return reward;
    }

    function claimAlbumRewards(address _album) external returns (uint){
        _updateAlbumRewards(msg.sender, _album);
        uint reward = userAlbumRewardsEarned[_album][msg.sender];
        if (reward > 0) {
            userAlbumRewardsEarned[_album][msg.sender] = 0;
            (bool sent, ) = msg.sender.call{value: reward}("");
            require(sent, "Failed to send reward to user");
        }
        emit ClaimAlbumRewards(msg.sender, _album, reward);
        return reward;
    }

}