//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Raffle} from "src/Raffle.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {HelperConfig, CodeConstant} from "script/HelperConfig.s.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {VRFCoordinatorV2_5Mock} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {RejectingReceiver} from "test/Unit/TestHelper.t.sol";

contract RaffleTest is Test, CodeConstant {
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
        callbackGasLimit = config.callbackGasLimit;
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
        /**
         * @dev First three true false given to define indexed, if any of first three element is indexed in evemt then true otherwise false.
         * - the forth true false is given to define if other element exist or not.
         * @notice We need to copy past the events in here (top).
         */
        vm.expectEmit(true, false, false, false, address(raffle));
        /**
         * @dev first three true false given to define if  any of first
         */
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
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector); // selecting the custom error
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        //arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //act 
        (bool upKeepNeed, ) = raffle.checkUpkeep("");

        //assert 
        assert(!upKeepNeed);
    }

    function testCheckUpKeepReturnsFalseIfIRaffleisntOpen() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); 
        vm.roll(block.number + 1); 
        raffle.performUpkeep("");

        //act 
        (bool upKeepNeed, ) = raffle.checkUpkeep("");

        //assert 
        assert(!upKeepNeed);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // act
        (bool upKeepNeed, ) = raffle.checkUpkeep("");

        //assert 
        assert(!upKeepNeed);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); 
        vm.roll(block.number + 1); 

        // act
        (bool upKeepNeed, ) = raffle.checkUpkeep("");

        //assert 
        assert(upKeepNeed);
    }

    function testPerformUpKeepCanOnlyRunWhenChecUpKeepReturnsTrue() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); 
        vm.roll(block.number + 1); 

        // act / assert
        raffle.performUpkeep("");
    }

    function testPerformUpKeepRevertIfCheeckUpKeepReturnsFalse() public {
        // arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = 1;

        //act / assert
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpKeepNotNeeded.selector, currentBalance, numPlayers, rState)
        ); // selecting the custom error
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); 
        vm.roll(block.number + 1);
        _;
    }
    // get emited events data.
    function testPerformUpKeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /** @dev entries[0] is from vrf and topic[0] is reserved for somethis else. 
        * - then our requestId comes in entries[1] and topic[1].
        */
        bytes32 requestId = entries[1].topics[1]; 

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);

    }

    modifier skipFork() {
        if(block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }
    function testFulfillRandomWordsPerformUpkeepCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public skipFork raffleEntered {
        // arrange / act / assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPickaAWinnerResetAndSendMoney() public skipFork raffleEntered {
        // arrange 
        uint256 additionalEntrance = 3; // 4 total
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < additionalEntrance + startingIndex; i++) {
            address newPlayer = address(uint160(i)); // same as address(i)
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp =  raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act 
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; 
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
        
        // assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 price = entranceFee * (additionalEntrance + 1 /**@note Prank PLAYER is 1*/);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0 /**OPEN*/);
        assert(winnerBalance == winnerStartingBalance + price);
        assert(endingTimeStamp > startingTimeStamp);
    }

    function testRaffleRevertsIfWinnerCantReceive() public skipFork {
        // Arrange 
        RejectingReceiver badReceiver = new RejectingReceiver();
        vm.deal(address(badReceiver), 1 ether);

        vm.prank(address(badReceiver));
        raffle.enterRaffle{value: 1 ether}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];

        // Assert
        //vm.expectRevert(Raffle.Raffle__TransferFailed.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
        assertEq(address(badReceiver).balance, 0);
    }

}
