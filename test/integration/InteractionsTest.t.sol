// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {Raffle} from "../../contracts/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

// import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract DeployReffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    // uint256 entranceFee;
    // uint256 interval;
    // address vrfCoordinator;
    // bytes32 gasLane;
    // uint64 subscriptionId;
    // uint32 callbackGasLimit;
    // address link;
    // uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        // (
        //     entranceFee,
        //     interval,
        //     vrfCoordinator,
        //     gasLane,
        //     subscriptionId,
        //     callbackGasLimit,
        //     link,
        //     deployerKey
        // ) = helperConfig.activeNetworkConfig();
    }

    function testConstructorSetupEntranceFee() external view {
        (uint256 entranceFee, , , , , , , ) = helperConfig
            .activeNetworkConfig();
        assert(raffle.getEntranceFee() == entranceFee);
    }

    function testConstructorSetupInterval() external view {
        (, uint256 interval, , , , , , ) = helperConfig.activeNetworkConfig();
        assert(raffle.getInterval() == interval);
    }
}
