//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract RaffleTest is Test {
    HelperConfig public helperConfig;
    Raffle public raffle;

    address public PLAYER = makeAddr("player");
    uint256 public STARTING_PLAYER_BALANCE = 10 ether;


    event RaffleEntered(address indexed players);
    event WinnerPicked(address indexed winner);

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig(); // Unclear line
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit  = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); // Unclear line
    }

    function testRaffleRevertWhenYOUDontPayEnough() public {
        // arrange
        vm.prank(PLAYER);
        //act, assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecodsPlayerWhenTheyEnter() public {
        //arrange
        vm.prank(PLAYER);
        //act
        raffle.enterRaffle{value: entranceFee}();
        //assert
        address playerRecorded = raffle.getPlayers(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitEvewnt() public {
        //arrange
        vm.prank(PLAYER);
        //act
        /**@dev First three true false given to define indexed, if any of first three element is indexed in evemt then true otherwise false.
        * - the forth true false is given to define if other element exist or not.
        * @notice We need to copy past the events in here (top).
        */
        vm.expectEmit(true, false, false, false, address(raffle)); /**@dev first three true false given to define if  any of first */
        emit RaffleEntered(PLAYER);
        //asert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToInterRaffleWhileCalculating() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // Change block time
        vm.roll(block.number + 1); // change block number
        raffle.performUpkeep("");
        //act, assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();


    }
}