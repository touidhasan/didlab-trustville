// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {CertificateRegistry} from "../src/CertificateRegistry.sol";
import {CropInsurance} from "../src/CropInsurance.sol";
import {EventTickets} from "../src/EventTickets.sol";
import {GrainLoans} from "../src/GrainLoans.sol";
import {GrainToken} from "../src/GrainToken.sol";
import {ProductRegistry} from "../src/ProductRegistry.sol";
import {PropertyDeeds} from "../src/PropertyDeeds.sol";
import {RainOracle} from "../src/RainOracle.sol";
import {RentEscrow} from "../src/RentEscrow.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {SealedAuction} from "../src/SealedAuction.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownCharity} from "../src/TownCharity.sol";
import {TownEscrow} from "../src/TownEscrow.sol";
import {TownGovernor} from "../src/TownGovernor.sol";
import {TownNoticeBoard} from "../src/TownNoticeBoard.sol";
import {TownSwap} from "../src/TownSwap.sol";
import {TownTimelock} from "../src/TownTimelock.sol";
import {TownToken} from "../src/TownToken.sol";
import {TownTreasury} from "../src/TownTreasury.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";
import {VoteToken} from "../src/VoteToken.sol";

/// Build the whole town in one go — every contract, wired, on a fresh chain.
///
/// For a local town (the usual case — no faucet, no permissions, instant blocks):
///
///   anvil &
///   cd contracts
///   forge script script/DeployAll.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
///     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
///   cd .. && npm run sync-abi
///   VITE_CHAIN_ID=31337 VITE_RPC_URL=http://127.0.0.1:8545 npm run dev
///
/// `scripts/local-town.sh` does all of that for you.
///
/// The deployer is also the town admin here, which is what makes a one-command town
/// possible: the same account can deploy a contract and immediately grant it the right to
/// stamp passports. That is NOT how the public deployment works — there the deployer ends
/// up holding nothing and every grant is a separate, admin-signed step. See the README.
///
/// Set TOWN_ADMIN to somebody else and this script deploys with that account as admin and
/// prints the grants it could not make, rather than pretending it did.
contract DeployAll is Script {
    struct Town {
        address registry;
        address passport;
        address token;
        address bank;
        address notices;
        address products;
        address escrow;
        address auction;
        address certificates;
        address tickets;
        address deeds;
        address leases;
        address votes;
        address timelock;
        address governor;
        address treasury;
        address charity;
        address oracle;
        address insurer;
        address grain;
        address swap;
        address loans;
    }

    bytes32 constant STAMPER = keccak256("STAMPER_ROLE");

    string private _path;
    bool private _selfAdmin;

    function run() external {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        address admin = vm.envOr("TOWN_ADMIN", deployer);
        _selfAdmin = admin == deployer;

        // Split into phases because one function holding twenty-two contract handles runs
        // the EVM out of stack slots. A memory struct is passed by reference between
        // internal calls, so each phase fills in the same town.
        Town memory t;
        _town(t, admin);
        _marketAndCollege(t, admin);
        _housing(t, admin);
        _council(t, admin, deployer);
        _charityInsurerDefi(t, admin);
        _grants(t);

        vm.stopBroadcast();

        _write(t);
        _report(t, admin, deployer);
    }

    /* ---------------------------------------------------------------- D1: the town */

    function _town(Town memory t, address admin) private {
        ResidentRegistry registry = new ResidentRegistry(admin);
        TrustvillePassport passport = new TrustvillePassport(admin, registry);
        TownToken token = new TownToken(admin, 10_000_000 ether);
        TownBank bank = new TownBank(admin, registry, token, passport, 1000 ether);

        if (_selfAdmin) {
            token.grantRole(token.MINTER_ROLE(), address(bank));
            passport.grantRole(STAMPER, address(bank));
        }

        t.registry = address(registry);
        t.passport = address(passport);
        t.token = address(token);
        t.bank = address(bank);
        t.notices = address(new TownNoticeBoard());
    }

    /* ------------------------------------------------------- D2: market and college */

    function _marketAndCollege(Town memory t, address admin) private {
        ResidentRegistry registry = ResidentRegistry(t.registry);
        TrustvillePassport passport = TrustvillePassport(t.passport);
        IERC20 token = IERC20(t.token);

        t.products = address(new ProductRegistry(registry, passport));
        t.escrow = address(new TownEscrow(admin, token, passport));
        t.auction = address(new SealedAuction(token, passport));
        t.certificates = address(new CertificateRegistry(registry, passport));
        t.tickets = address(new EventTickets(token, registry, passport));
    }

    /* ------------------------------------------------------------------ D3: housing */

    function _housing(Town memory t, address admin) private {
        TrustvillePassport passport = TrustvillePassport(t.passport);
        PropertyDeeds deeds = new PropertyDeeds(admin, ResidentRegistry(t.registry), passport);
        t.deeds = address(deeds);
        t.leases =
            address(new RentEscrow(admin, IERC20(t.token), IERC721(address(deeds)), passport));
        t.votes = address(new VoteToken(IERC20(t.token)));
    }

    /* ----------------------------------------------------------------- D3b: council */

    function _council(Town memory t, address admin, address deployer) private {
        address[] memory none = new address[](0);
        TownTimelock timelock = new TownTimelock(120, none, none, deployer);
        TownGovernor governor = new TownGovernor(IVotes(t.votes), timelock, 60, 600, 0);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        address[] memory owners = new address[](1);
        owners[0] = admin;

        t.timelock = address(timelock);
        t.governor = address(governor);
        t.treasury = address(new TownTreasury(owners, 1, TrustvillePassport(t.passport)));
    }

    /* ----------------------------------------------- D4: charity, insurer, exchange */

    function _charityInsurerDefi(Town memory t, address admin) private {
        TrustvillePassport passport = TrustvillePassport(t.passport);
        IERC20 token = IERC20(t.token);

        t.charity = address(new TownCharity(token, admin, passport));

        RainOracle oracle = new RainOracle(admin, 600, 3);
        t.oracle = address(oracle);
        t.insurer = address(new CropInsurance(token, oracle, admin, 5, 1000, passport));

        GrainToken grain = new GrainToken(admin, ResidentRegistry(t.registry), 600);
        TownSwap swap = new TownSwap(token, IERC20(address(grain)), passport);
        t.grain = address(grain);
        t.swap = address(swap);
        t.loans =
            address(new GrainLoans(token, IERC20(address(grain)), swap, admin, 1000, passport));
    }

    /* ------------------------------------------------------- the stamping grants */

    function _grants(Town memory t) private {
        if (!_selfAdmin) return;
        TrustvillePassport passport = TrustvillePassport(t.passport);
        address[12] memory stampers = [
            t.products,
            t.escrow,
            t.auction,
            t.certificates,
            t.tickets,
            t.deeds,
            t.leases,
            t.treasury,
            t.charity,
            t.insurer,
            t.swap,
            t.loans
        ];
        for (uint256 i; i < stampers.length; i++) passport.grantRole(STAMPER, stampers[i]);
    }

    /* --------------------------------------------------------------------- output */

    function _write(Town memory t) private {
        _path = string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        if (!vm.exists(_path)) {
            vm.writeFile(
                _path,
                string.concat(
                    '{\n  "chainId": ',
                    vm.toString(block.chainid),
                    ',\n  "network": "local",\n  "updated": null,\n  "contracts": {}\n}\n'
                )
            );
        }
        _rec("ResidentRegistry", t.registry);
        _rec("TrustvillePassport", t.passport);
        _rec("TownToken", t.token);
        _rec("TownBank", t.bank);
        _rec("TownNoticeBoard", t.notices);
        _rec("ProductRegistry", t.products);
        _rec("TownEscrow", t.escrow);
        _rec("SealedAuction", t.auction);
        _rec("CertificateRegistry", t.certificates);
        _rec("EventTickets", t.tickets);
        _rec("PropertyDeeds", t.deeds);
        _rec("RentEscrow", t.leases);
        _rec("VoteToken", t.votes);
        _rec("TownTimelock", t.timelock);
        _rec("TownGovernor", t.governor);
        _rec("TownTreasury", t.treasury);
        _rec("TownCharity", t.charity);
        _rec("RainOracle", t.oracle);
        _rec("CropInsurance", t.insurer);
        _rec("GrainToken", t.grain);
        _rec("TownSwap", t.swap);
        _rec("GrainLoans", t.loans);
        vm.writeJson(vm.toString(block.timestamp), _path, ".updated");
    }

    function _rec(string memory name, address addr) private {
        vm.writeJson(vm.toString(addr), _path, string.concat(".contracts.", name));
        console.log(name, addr);
    }

    function _report(Town memory t, address admin, address deployer) private view {
        console.log("");
        console.log("22 contracts on chain", block.chainid);
        console.log("admin:", admin);
        if (_selfAdmin) {
            console.log("");
            console.log("The deployer is the admin, so every stamping grant is already done.");
            console.log("Next: cd .. && npm run sync-abi, then run the site against this chain.");
        } else {
            console.log("");
            console.log("TOWN_ADMIN is not the deployer, so the grants below have NOT been made.");
            console.log("Until they are, the town works but awards no passport stamps:");
            console.log("  passport.grantRole(STAMPER_ROLE, x) for each of:");
            console.log("   ", t.products, t.escrow, t.auction);
            console.log("   ", t.certificates, t.tickets, t.deeds);
            console.log("   ", t.leases, t.treasury, t.charity);
            console.log("   ", t.insurer, t.swap, t.loans);
            console.log("  token.grantRole(MINTER_ROLE,", address(t.bank), ")");
            console.log("  passport.grantRole(STAMPER_ROLE,", address(t.bank), ")");
        }
        console.log("");
        console.log("Deployer:", deployer);
    }
}
