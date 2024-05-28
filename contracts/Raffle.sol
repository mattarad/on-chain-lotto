// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view and pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle Contract
 * @author Matt Cannon / Tutorial done by Patrick Collins and Cyfrin.io
 * @notice this contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughETHSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    /** Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // @dev price required to be paid to enter lottory
    uint256 private immutable i_entranceFee;
    // @dev duration of lottory in seconds
    uint256 private immutable i_interval;

    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callBackGasLimit;

    VRFCoordinatorV2Interface immutable i_vrfCoordinator;

    // @dev array of players that entered lottery, eligable to win lottery
    address payable[] private s_players;
    address private s_recentWinner;

    RaffleState private s_raffleState;

    // @dev when the current round started, updated w/ each round
    uint256 private s_lastTimestamp;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed player);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callBackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) revert Raffle__NotEnoughETHSent();
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * to see if it's time to perform an upkeep
     * the following should be true for this to return true:
     *  1. the time interval has passed between raffle runs
     *  2. the raffle is in the OPEN state
     *  3. the contract has ETH (aka players)
     *  4/ (Implicit) the subscription is funded with LINK
     */
    function checkUpkeep(
        bytes memory /*checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasPlayers = s_players.length > 0 && address(this).balance > 0
            ? true
            : false;
        upkeepNeeded = (timeHasPassed && isOpen && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // Checks -> Effects -> interactions
    function performUpkeep(bytes calldata /* performData */) external {
        // check if the lottory round is over
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded)
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        s_raffleState = RaffleState.CALCULATING;

        /* uint256 requestId = */
        i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callBackGasLimit,
            NUM_WORDS
        );
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;

        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;
        emit PickedWinner(winner);

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) revert Raffle__TransferFailed();
    }

    /** Getter Functions */
    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }
}
