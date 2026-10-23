// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Edge cases and failure paths for MADToken: zero, one wei, the full supply, self-transfers,
/// unexpected callers, and every revert with its exact error data.
contract MADTokenEdgesTest is Test {
    uint256 constant SUPPLY = 1_000_000_000e18;

    MADToken token;
    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new MADToken();
    }

    // ---------------------------------------------------------------- constructor & metadata

    function test_constantSupplyMatchesTotal() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
        assertEq(SUPPLY, 1_000_000_000 * 10 ** uint256(token.decimals()));
    }

    function test_constructorMintsOnlyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_eachDeploymentMintsToItsOwnDeployer() public {
        vm.prank(alice);
        MADToken other = new MADToken();
        assertEq(other.balanceOf(alice), SUPPLY);
        assertEq(other.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_constructorSetsNoAllowances() public view {
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.allowance(deployer, deployer), 0);
    }

    // ---------------------------------------------------------------- transfer

    function test_transferZeroSucceedsAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferOneWei() public {
        vm.prank(deployer);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_transferWholeSupply() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferOneMoreThanBalanceReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        token.transfer(alice, SUPPLY + 1);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(MADToken.InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_transferAfterSpendingRevertsOnRemainder() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.startPrank(alice);
        token.transfer(bob, 7);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, alice, 3, 4));
        token.transfer(bob, 4);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(bob), 7);
    }

    function test_selfTransferKeepsBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_selfTransferOverBalanceReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        token.transfer(deployer, SUPPLY + 1);
    }

    function test_transferZeroToZeroAddressReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_transferToTokenContractIsAllowedAndStuck() public {
        // The token has no rescue function; tokens sent to it are held there for good. Not a defect
        // of an ERC-20, but the behaviour is pinned so a later change to it is noticed.
        vm.prank(deployer);
        token.transfer(address(token), 5);
        assertEq(token.balanceOf(address(token)), 5);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_failedTransferLeavesStateUntouched() public {
        vm.prank(deployer);
        token.transfer(alice, 100);
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeCall(MADToken.transfer, (bob, 101)));
        assertFalse(ok);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    // ---------------------------------------------------------------- approve

    function test_approveEmitsAndOverwrites() public {
        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, bob, 100);
        assertTrue(token.approve(bob, 100));
        assertEq(token.allowance(alice, bob), 100);

        token.approve(bob, 5);
        assertEq(token.allowance(alice, bob), 5);

        token.approve(bob, 0);
        assertEq(token.allowance(alice, bob), 0);
        vm.stopPrank();
    }

    function test_approveDoesNotRequireBalance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    function test_approveSelf() public {
        vm.prank(alice);
        token.approve(alice, 1);
        assertEq(token.allowance(alice, alice), 1);
    }

    function test_approveZeroSpenderWithZeroValueReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
    }

    function test_approvalsAreDirectional() public {
        vm.prank(alice);
        token.approve(bob, 10);
        assertEq(token.allowance(bob, alice), 0);
        assertEq(token.allowance(alice, carol), 0);
    }

    // ---------------------------------------------------------------- transferFrom

    function test_transferFromWithoutAllowanceReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ownerCannotTransferFromSelfWithoutAllowance() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_transferFromZeroWithoutAllowanceSucceeds() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, bob, 0);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 0));
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromExactAllowanceZeroesIt() public {
        vm.prank(deployer);
        token.approve(alice, 1000);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1000);
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.balanceOf(bob), 1000);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromAllowanceAboveBalanceRevertsOnBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(bob, 100);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, alice, 10, 11));
        token.transferFrom(alice, carol, 11);
        // The revert rolls back the allowance decrement too.
        assertEq(token.allowance(alice, bob), 100);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_transferFromToZeroAddressRevertsAndKeepsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 50);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 10);
        assertEq(token.allowance(deployer, alice), 50);
    }

    function test_infiniteAllowanceMovesWholeSupplyAndStaysInfinite() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, SUPPLY);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(deployer, alice), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, deployer, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_allowanceOneBelowMaxIsDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, alice), type(uint256).max - 2);
    }

    function test_transferFromOnlySpendsCallersAllowance() public {
        vm.startPrank(deployer);
        token.approve(alice, 10);
        token.approve(bob, 20);
        vm.stopPrank();

        vm.prank(alice);
        token.transferFrom(deployer, carol, 10);
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.allowance(deployer, bob), 20);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, carol, 1);
    }

    function test_transferFromSelfToSelf() public {
        vm.prank(deployer);
        token.approve(deployer, 100);
        vm.prank(deployer);
        token.transferFrom(deployer, deployer, 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, deployer), 0);
    }

    function test_transferFromDoesNotEmitApproval() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(deployer, bob, 4);
        assertEq(vm.getRecordedLogs().length, 1, "only Transfer is emitted");
    }

    function test_frontRunApproveChangeIsBoundedByOldPlusNew() public {
        // Classic approve race: the spender can spend the old allowance and then the new one, never more.
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.prank(alice);
        token.transferFrom(deployer, alice, 100);
        vm.prank(deployer);
        token.approve(alice, 50);
        vm.prank(alice);
        token.transferFrom(deployer, alice, 50);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(alice), 150);
    }

    // ---------------------------------------------------------------- no privileged surface

    function test_noAdminOrSupplyChangingEntryPoints() public {
        string[14] memory sigs = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "unpause()",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "blacklist(address)",
            "freeze(address)",
            "setMinter(address)",
            "increaseAllowance(address,uint256)",
            "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"
        ];
        vm.prank(deployer);
        token.transfer(alice, 1e18);
        for (uint256 i; i < sigs.length; ++i) {
            bytes memory data = abi.encodeWithSignature(sigs[i], alice, 1e18);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, sigs[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 1e18);
    }

    function test_rejectsEtherAndUnknownCalldata() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_nonPayableFunctionsRejectValue() public {
        vm.deal(deployer, 1 ether);
        vm.prank(deployer);
        (bool ok,) = address(token).call{value: 1}(abi.encodeCall(MADToken.transfer, (alice, 1)));
        assertFalse(ok);
        assertEq(token.balanceOf(alice), 0);
    }

    // ---------------------------------------------------------------- stateless fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferMovesExactly(address to, uint256 seedAmount, uint256 amount) public {
        to = _nonZero(to);
        vm.assume(to != alice);
        seedAmount = bound(seedAmount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, seedAmount);

        amount = bound(amount, 0, seedAmount);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(alice);
        token.transfer(to, amount);
        assertEq(token.balanceOf(alice), seedAmount - amount);
        assertEq(token.balanceOf(to), toBefore + amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferAboveBalanceReverts(uint256 seedAmount, uint256 amount) public {
        seedAmount = bound(seedAmount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, seedAmount);
        amount = bound(amount, seedAmount + 1, type(uint256).max);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, alice, seedAmount, amount));
        token.transfer(bob, amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromSpendsExactly(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, type(uint256).max - 1);
        amount = bound(amount, 0, allowed < SUPPLY ? allowed : SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        token.transferFrom(deployer, bob, amount);
        assertEq(token.allowance(deployer, alice), allowed - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromAboveAllowanceReverts(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, SUPPLY);
        amount = bound(amount, allowed + 1, type(uint256).max);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, alice, allowed, amount));
        token.transferFrom(deployer, bob, amount);
        assertEq(token.allowance(deployer, alice), allowed);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactValue(address owner, address spender, uint256 value) public {
        spender = _nonZero(spender);
        vm.prank(owner);
        token.approve(spender, value);
        assertEq(token.allowance(owner, spender), value);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotMoveAnotherHolder(address stranger, uint256 amount) public {
        vm.assume(stranger != deployer);
        amount = bound(amount, 1, SUPPLY);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, stranger, 0, amount));
        token.transferFrom(deployer, stranger, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function _nonZero(address a) private pure returns (address) {
        return a == address(0) ? address(1) : a;
    }
}
