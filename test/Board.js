const {
  time,
  loadFixture,
} = require('@nomicfoundation/hardhat-toolbox/network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');
const { expect } = require('chai');
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const MULTIPLIER = 1000000000000000000;

let owner, alice, bob, cindy;

describe('Board', function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployBoardFixture() {
    const accounts = await hre.ethers.getSigners();
    owner = accounts[0];
    alice = accounts[1];
    bob = accounts[2];
    cindy = accounts[3];
    // console.log('owner ', owner.address);

    const teamAddress = owner.address;
    const Board = await hre.ethers.getContractFactory('MediaBoard');
    const startTime = await time.latest();
    const interval = 60 * 60 * 24;
    const board = await upgrades.deployProxy(Board, [
      teamAddress,
      startTime,
      interval,
    ]);
    await board.waitForDeployment();
    const proxy = await ethers.getContractAt(
      'MediaBoard',
      await board.getAddress()
    );

    await proxy.connect(alice).newAlbum('name', 'sym');
    const albumAddr = await proxy.albumsList(0);
    return { proxy, albumAddr };
  }

  function calcVotePrice(x) {
    return (x * (x + 1) * MULTIPLIER) / 40000;
  }
  async function vote(start, times, from, albumAddr, proxy) {
    for (let index = start; index < start + times; index++) {
      const votePrice = calcVotePrice(index);
      await proxy.connect(from).vote(albumAddr, {
        value: votePrice,
      });
    }
  }

  describe('check vote price', async function () {
    it('check vote price', async function () {
      const { proxy } = await loadFixture(deployBoardFixture);
      expect(await proxy.calculateVotePrice(1)).to.equals(calcVotePrice(1));
      expect(await proxy.calculateVotePrice(2)).to.equals(calcVotePrice(2));
    });
  });

  describe('Vote', async function () {
    it('create an album', async function () {
      const { proxy, albumAddress } = await loadFixture(deployBoardFixture);

      expect(await proxy.connect(alice).newAlbum('name', 'sym'))
        .to.emit(proxy, 'NewAlbum')
        .withArgs(anyValue);
    });

    it('vote an album', async function () {
      const { proxy, albumAddr } = await loadFixture(deployBoardFixture);

      // first vote
      await vote(1, 1, bob, albumAddr, proxy);
      const {
        artist,
        rewardIndex: albumRewardIndex,
        votes: albumVotes,
      } = await proxy.albumToData(albumAddr);
      expect(artist).to.equals(alice.address);
      expect(albumRewardIndex).to.equals(0);
      expect(albumVotes).to.equals(1);

      const { starts, interval, rewardIndex, votes } =
        await proxy.seqToRewardData(0);
      // console.log('rewarddata', starts, interval, rewardIndex, votes);
      expect(await proxy.calculateDailyRewards(bob.address)).to.equals(0);
      expect(rewardIndex).to.equals(0);
      expect(votes).to.equals(1);

      // second vote
      await vote(2, 1, cindy, albumAddr, proxy);
      const {
        artist2,
        rewardIndex: albumRewardIndex2,
        votes: albumVotes2,
      } = await proxy.albumToData(albumAddr);

      const { rewardIndex2, votes2 } = await proxy.seqToRewardData(0);

      const bobReward2 = (calcVotePrice(1) + calcVotePrice(2)) / 2;
      expect(await proxy.calculateDailyRewards(bob.address)).to.equals(
        bobReward2
      );
    });

    it.skip('claim daily reward', async function () {
      const { proxy } = await loadFixture(deployBoardFixture);

      expect(await proxy.connect(alice).newAlbum('name', 'sym'))
        .to.emit(proxy, 'NewAlbum')
        .withArgs(anyValue);
      const newAlbum = await proxy.albumsList(0);

      const votePrice = calcVotePrice(1);
      await proxy.connect(bob).vote(newAlbum, {
        value: votePrice,
      });
      expect(await proxy.userDailyRewardIndex(bob.address)).to.equals(0);
      expect(await proxy.userDailyEarned(bob.address)).to.equals(0);
      expect(await proxy.userDailyBalance(bob.address)).to.equals(1);
      expect(await proxy.dailyRewardIndex()).to.equals(0);
      expect(await proxy.dailyRewardVotes()).to.equals(0);

      const votePrice2 = calcVotePrice(2);
      await proxy.connect(cindy).vote(newAlbum, {
        value: votePrice2, //ethers.parseEther(votePrice.toString()),
      });
      console.log('bob index', await proxy.userDailyRewardIndex(bob.address));
      console.log('bob earned', await proxy.userDailyEarned(bob.address));
      console.log('bob balance', await proxy.userDailyBalance(bob.address));
      console.log('daily index', await proxy.dailyRewardIndex());
      console.log('daily reward votes', await proxy.dailyRewardVotes());
      console.log(
        'bob daily reward',
        await proxy.calculateDailyRewards(bob.address)
      );

      console.log(await proxy.userDailyEarned(cindy.address));
      console.log(await proxy.userDailyBalance(alice.address));
      console.log(await proxy.userDailyBalance(cindy.address));
    });
    it('claim album reward', async function () {});
  });
});
