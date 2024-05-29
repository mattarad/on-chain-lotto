// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {Raffle} from "../../contracts/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed player);

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange | Act | Assert
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughETHSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange | Act | Assert
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        // Arrange | Act | Assert
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + (interval / 2) + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        console.log(upkeepNeeded);
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        console.log(upkeepNeeded);
        assert(upkeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange | Act | Assert
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange | Act | Assert
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange | Act | Assert
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(rState == Raffle.RaffleState.CALCULATING);
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed {
        // Arrange | Act | Assert
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    /**
     * @dev tests below use multiple players for testing
     */

    function testFulfillRandomWordsPicksWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
    {
        uint160 numPlayers = 200;
        address[] memory resultPlayers = _createPlayers(numPlayers);
        address[] memory players = new address[](numPlayers + 1);
        players[0] = PLAYER;
        for (uint160 i = 1; i <= numPlayers; i++) {
            players[i] = resultPlayers[i - 1];
        }
        // test to ensure players was setup correctly
        assert(players[0] == PLAYER);
        assert(players[1] == resultPlayers[0]);
        assert(players[2] == resultPlayers[1]);
        assert(players[numPlayers / 2] == resultPlayers[(numPlayers / 2) - 1]);
        assert(players[numPlayers] == resultPlayers[numPlayers - 1]);

        uint256 previousTimestamp = raffle.getLastTimestamp();
        uint256 prizeShouldBe = (numPlayers + 1) * entranceFee;
        uint256 prize = address(raffle).balance;

        assert(prizeShouldBe == prize);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        address payable[] memory rafflePlayers = raffle.getPlayersArray();

        for (uint i; i < numPlayers + 1; i++) {
            assert(players[i] == rafflePlayers[i]);
        }

        // pretend to be chainlink vrf to get random number and pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        uint256 lastTimestamp = raffle.getLastTimestamp();
        // address winner = players[uint(????)];
        address winner = raffle.getRecentWinner();

        // make sure lastTimestamp was updated
        assert(lastTimestamp > previousTimestamp);

        // make sure Raffle State was updated to OPEN
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);

        // players array should be reset to 0
        assert(raffle.getLengthOfPlayers() == 0);

        // make sure winner was selected
        // assert(raffle.getRecentWinner() == winner);

        // check winner recieved prize
        uint256 winnerBalance = address(winner).balance;
        assert(winnerBalance > prize);
        assert(winnerBalance == prize + STARTING_BALANCE - entranceFee);
    }

    function testMultiplePlayersEnterRaffleGetPlayer() public {
        uint160 numPlayers = 25;
        address[] memory players = _createPlayers(numPlayers);
        for (uint160 i; i < numPlayers; i++) {
            address indexedPlayer = raffle.getPlayer(i);
            assert(indexedPlayer == players[i]);
        }
    }

    function testMultiplePlayersEnterRaffleGetPlayersArray() public {
        uint160 numPlayers = 25;
        address[] memory players = _createPlayers(numPlayers);

        address payable[] memory playersArray = raffle.getPlayersArray();
        for (uint160 i; i < numPlayers; i++) {
            assert(playersArray[i] == players[i]);
        }
    }

    function testContractBalanceAfterMultipleEntrances() public {
        uint160 numPlayers = 150;
        _createPlayers(numPlayers);
        uint256 numPlayersBal = uint256(numPlayers) * entranceFee;
        console.log("numPlayersBal:             ", numPlayersBal);
        console.log("address(raffle).balance:   ", address(raffle).balance);
        assert(numPlayersBal == address(raffle).balance);
    }

    function _createPlayers(
        uint160 numPlayers
    ) internal returns (address[] memory) {
        address[] memory players = new address[](numPlayers);
        for (uint160 i; i < numPlayers; i++) {
            hoax(address(i + 1), STARTING_BALANCE);
            players[i] = address(i + 1);
            raffle.enterRaffle{value: entranceFee}();
        }
        return players;
    }
}
