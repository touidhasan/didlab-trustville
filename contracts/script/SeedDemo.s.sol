// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EventTickets} from "../src/EventTickets.sol";
import {ProductRegistry} from "../src/ProductRegistry.sol";
import {PropertyDeeds} from "../src/PropertyDeeds.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {SealedAuction} from "../src/SealedAuction.sol";
import {TownCharity} from "../src/TownCharity.sol";
import {TownNoticeBoard} from "../src/TownNoticeBoard.sol";

/// Give every stop something to show before class starts.
///
///   cd contracts
///   DEPLOYER=$(cast wallet address --account didlab-deployer)
///   forge script script/SeedDemo.s.sol --rpc-url didlab --account didlab-deployer \
///     --sender "$DEPLOYER" --legacy --slow --broadcast
///
/// Run it the day before class. The windows are measured from when it runs:
///
///   COMMIT_HOURS   the auction takes sealed bids for this long     default 48
///   REVEAL_HOURS   then bids are revealed for this long            default 24
///   EVENT_DAYS     the town meeting starts this many days out      default 14
///   CHARITY_DAYS   the campaign raises money for this long         default 21
///
/// Everything it creates is signed by the account that runs it, which must be a resident
/// (the script registers it if registration is open). Running it twice creates everything
/// twice; nothing breaks, the town just gets busier.
///
/// What it leaves alone, on purpose: anything that needs a second person (an escrow order, a
/// lease, a certificate — the issuer cannot be the holder) and anything that needs a role
/// (the Council's treasury, the Insurer's oracle). Those are better done live in class,
/// between two students, where the second party is the point.
contract SeedDemo is Script {
    function run() external {
        string memory path = string.concat(
            vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json"
        );
        string memory json = vm.readFile(path);

        ResidentRegistry residents =
            ResidentRegistry(vm.parseJsonAddress(json, ".contracts.ResidentRegistry"));
        TownNoticeBoard board =
            TownNoticeBoard(vm.parseJsonAddress(json, ".contracts.TownNoticeBoard"));
        ProductRegistry products =
            ProductRegistry(vm.parseJsonAddress(json, ".contracts.ProductRegistry"));
        SealedAuction auctions =
            SealedAuction(vm.parseJsonAddress(json, ".contracts.SealedAuction"));
        EventTickets tickets = EventTickets(vm.parseJsonAddress(json, ".contracts.EventTickets"));
        TownCharity charity = TownCharity(vm.parseJsonAddress(json, ".contracts.TownCharity"));
        PropertyDeeds deeds = PropertyDeeds(vm.parseJsonAddress(json, ".contracts.PropertyDeeds"));

        uint64 commitSecs = uint64(vm.envOr("COMMIT_HOURS", uint256(48))) * 1 hours;
        uint64 revealSecs = uint64(vm.envOr("REVEAL_HOURS", uint256(24))) * 1 hours;
        uint64 eventIn = uint64(vm.envOr("EVENT_DAYS", uint256(14))) * 1 days;
        uint64 charityFor = uint64(vm.envOr("CHARITY_DAYS", uint256(21))) * 1 days;

        vm.startBroadcast();
        (, address me,) = vm.readCallers();

        if (!residents.isResident(me)) {
            // Read the flag BEFORE deciding, and say why if it is closed: a revert from
            // register() would read as a broken script rather than a closed door.
            require(residents.openRegistration(), "not a resident, and registration is closed");
            residents.register(keccak256(abi.encodePacked("trustville demo resident ", me)));
        }

        uint256 notice = board.post(
            "Welcome to Trustville. Start with this warm-up, then walk the modules in order, 1 to 16."
        );

        uint256 product = products.register(
            "Heritage wheat, 25 kg sack",
            "Miller farm, north field",
            keccak256("demo: harvest record 2026")
        );

        uint256 auction = auctions.createAuction(
            "Demo: a sack of heritage wheat", product, commitSecs, revealSecs
        );

        uint256 meeting = tickets.createEvent(
            "Trustville town meeting", 5 ether, 100, uint64(block.timestamp) + eventIn
        );

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 100 ether;
        amounts[2] = 100 ether;
        string[] memory what = new string[](3);
        what[0] = "Posts and roof frame";
        what[1] = "Roof panels";
        what[2] = "Lighting and paint";
        uint256 campaign =
            charity.create("A shelter for the market stalls", 300 ether, charityFor, amounts, what);

        uint256 deed = deeds.register(
            "1 Market Square, Trustville", keccak256("demo: survey 1 Market Square")
        );

        vm.stopBroadcast();

        console.log("Seeded, signed by", me);
        console.log("  notice      #", notice);
        console.log("  product     #", product);
        console.log("  auction     #", auction);
        console.log("  event       #", meeting);
        console.log("  campaign    #", campaign);
        console.log("  deed        #", deed);
        console.log("");
        console.log("Auction takes sealed bids for (hours):", commitSecs / 1 hours);
        console.log("Town meeting starts in (days):", eventIn / 1 days);
    }
}
