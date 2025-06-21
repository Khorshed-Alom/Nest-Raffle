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
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @dev To get a random number, you need to import `VRFConsumerBaseV2Plus` and `VRFV2PlusClient`.
 * - Inherit from `VRFConsumerBaseV2Plus`.
 * - When we need random number, we have to send values to `RandomWordsRequest` struct to get random number.
 * - When random number in vrf is ready to give us, it will call fulfillRandomWords and gives the random number.
 * @notice We need to do somethis in the `fulfillRandomWords` what we want.
 * @notice We also need to call a function to send values to `RandomWordsRequest` struct when needed, automatically.
 * --
 * @dev chainlink `checkUpkeep` and `performUpkeep` function do the automatic calling job.
 * - Chainlink keepers kee calling `checkUpkeep` function, it returns a bool. So, we have to decide when to return true or false.
 * - When we return true by our logic, chainlink keepers then call right after `performUpkeep` function.
 * - `performUpkeep` will handle rest of the job.
 *
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // Errors
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    // Type Declaration
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // State Variables
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    /**
     * @dev This is number of block confirmations Chainlink should wait before responding. More confirmations = more secure
     */
    uint32 private constant NUM_WORDS = 1;
    /**
     * @dev Number of how many random number we want
     */
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; //The duration of lottery in seconds
    bytes32 private immutable i_keyHash;
    /**
     * @dev Key of which gas lane we want to use
     */
    uint256 private immutable i_subscriptionId;
    /**
     * @dev It is the Chainlink subscription ID, LINK tokens or Native ETH
     */
    uint32 private immutable i_callbackGasLimit;
    /**
     * @dev This is gas limit that Chainlink can use when calling fulfillRandomWords. too low = callback fails, too high = waste of money
     */
    address payable[] private s_players;
    /**
     * @dev address must be store as payable if it receive eth later
     */
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState; //storage variable

    // Event
    event RaffleEntered(address indexed players);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    // VRFConsumerBaseV2Plus needs a address fron chainlink just like price feed address
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint32 callbackGasLimit,
        uint256 subscriptionId
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_callbackGasLimit = callbackGasLimit;
        i_subscriptionId = subscriptionId;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        //require (msg.value >= i_entranceFee, "not enough ETH sent"); not very gas efficient
        // require (msg.value >= i_entranceFee, Raffle__notEnoughEthSent()); work with specific compiler version
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    // Wshen should pick the winner?
    /**
     * @dev this is the function that chainlink nodes will call to see if the lottery is ready to have a winner picked.
     * 2. The lottery has open.
     * 3. The cntract has ETH
     * 4. Implicitly, Your subscription has LINK. (chatgpt says not true)
     * 5. Players are intered to the lottery.
     * @param - ignored
     * @return upkeepNeeded - if true it's time to restart the lottery.
     * @return - ingored
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        // check if enough time has passed
        (bool upKeepNeeded,) = checkUpkeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                /**
                 * @dev _argsToBytes() converting into bytes
                 */
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });
        /**
         * @dev fasle = Pay using LINK token, true = pay in native ETH (like Sepolia ETH)
         */
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId); // Mock vrf is also emiting requistId.
    }

    // CEI: Checks, Effect, Iteractions Pattern
    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal override {
        // Checks

        // Effect (Internal contract state)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        s_players = new address payable[](0);
        emit WinnerPicked(s_recentWinner);

        // Iteractions (External contract state)
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // Getter Function
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayers(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
