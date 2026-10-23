// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Drives MADToken with random transfers, approvals and transferFroms between a fixed set of
/// actors, and keeps a shadow ledger of what every balance and allowance should be.
contract MADHandler is Test {
    MADToken public immutable token;
    address[] public actors;

    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public calls;
    uint256 public successfulMoves;
    uint256 public unexpectedReverts;

    constructor(MADToken token_, address[] memory actors_, address holder) {
        token = token_;
        actors = actors_;
        expectedBalance[holder] = token_.TOTAL_SUPPLY();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount, bool overspend) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = token.balanceOf(from);
        if (overspend) {
            if (bal == type(uint256).max) return;
            amount = bound(amount, bal + 1, type(uint256).max);
            vm.prank(from);
            try token.transfer(to, amount) {
                unexpectedReverts++; // succeeded when it must not
            } catch {}
            return;
        }
        amount = bound(amount, 0, bal);
        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok) unexpectedReverts++;
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            successfulMoves++;
        } catch {
            unexpectedReverts++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value, bool infinite) external {
        calls++;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (infinite) value = type(uint256).max;
        else value = bound(value, 0, token.TOTAL_SUPPLY() * 2);
        vm.prank(owner);
        try token.approve(spender, value) returns (bool ok) {
            if (!ok) unexpectedReverts++;
            expectedAllowance[owner][spender] = value;
        } catch {
            unexpectedReverts++;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        calls++;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(from, spender);
        uint256 bal = token.balanceOf(from);
        uint256 cap = allowed < bal ? allowed : bal;
        // Mostly valid amounts, sometimes one past the cap to exercise the failure paths.
        amount = bound(amount, 0, cap == type(uint256).max ? cap : cap + 1);
        bool shouldSucceed = amount <= cap;

        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!shouldSucceed || !ok) unexpectedReverts++;
            if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            successfulMoves++;
        } catch {
            if (shouldSucceed) unexpectedReverts++;
        }
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        calls++;
        address from = _actor(fromSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        try token.transfer(address(0), amount) {
            unexpectedReverts++;
        } catch {}
    }

    function approveZero(uint256 ownerSeed, uint256 value) external {
        calls++;
        vm.prank(_actor(ownerSeed));
        try token.approve(address(0), value) {
            unexpectedReverts++;
        } catch {}
    }
}

contract MADTokenInvariantTest is Test {
    MADToken token;
    MADHandler handler;
    address[] actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        actors.push(deployer);
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        vm.prank(deployer);
        token = new MADToken();
        handler = new MADHandler(token, actors, deployer);

        // Spread the supply through the handler so its ledger records it and every actor has funds.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, 100_000_000e18, false);
        }
        require(handler.unexpectedReverts() == 0, "distribution failed");

        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_balancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_allowancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_everyCallBehavedAsSpecified() public view {
        assertEq(handler.unexpectedReverts(), 0);
    }
}
