// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IdentityUnits} from "../src/IdentityUnits.sol";

/// @dev Models balances and allowances independently across three holders.
contract TokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    IdentityUnits public immutable token;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401)];
    uint256[3] public expectedBalances;
    mapping(uint256 owner => mapping(uint256 spender => uint256)) public expectedAllowances;

    constructor() {
        token = new IdentityUnits();
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        uint256 third = SUPPLY / 3;
        for (uint256 i; i < 3; ++i) {
            expectedBalances[i] = i == 2 ? SUPPLY - 2 * third : third;
            require(token.transfer(actors[i], expectedBalances[i]));
        }
    }

    function transfer(uint256 from, uint256 to, uint256 amount) external {
        from %= 3;
        to %= 3;
        amount = bound(amount, 0, expectedBalances[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
    }

    function approve(uint256 owner, uint256 spender, uint256 amount, bool unlimited) external {
        owner %= 3;
        spender %= 3;
        // Approvals may exceed both the owner's balance and the entire supply.
        amount = unlimited ? type(uint256).max : bound(amount, 0, type(uint256).max - 1);
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowances[owner][spender] = amount;
    }

    function transferFrom(uint256 owner, uint256 spender, uint256 to, uint256 amount) external {
        owner %= 3;
        spender %= 3;
        to %= 3;
        uint256 approved = expectedAllowances[owner][spender];
        uint256 limit = expectedBalances[owner] < approved ? expectedBalances[owner] : approved;
        amount = bound(amount, 0, limit);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[owner], actors[to], amount));
        expectedBalances[owner] -= amount;
        expectedBalances[to] += amount;
        if (approved != type(uint256).max) expectedAllowances[owner][spender] -= amount;
    }

    // Rejected calls leave ghost balances and allowances untouched. The invariant
    // compares every actor and allowance pair after each handler, including failures.
    function transferOverBalance(uint256 from, uint256 to, uint256 amount) external {
        from %= 3;
        to %= 3;
        uint256 balance = expectedBalances[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        _expectFailure(
            actors[from],
            abi.encodeCall(IERC20.transfer, (actors[to], amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, amount)
        );
    }

    function transferFromOverAllowance(uint256 owner, uint256 spender, uint256 to, uint256 approved) external {
        owner %= 3;
        spender %= 3;
        to %= 3;
        approved = bound(approved, 0, SUPPLY);
        _approve(owner, spender, approved);
        _expectFailure(
            actors[spender],
            abi.encodeCall(IERC20.transferFrom, (actors[owner], actors[to], approved + 1)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], approved, approved + 1
            )
        );
    }

    function transferFromOverBalance(uint256 owner, uint256 spender, uint256 to, uint256 amount, bool unlimited)
        external
    {
        owner %= 3;
        spender %= 3;
        to %= 3;
        uint256 balance = expectedBalances[owner];
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _expectFailure(
            actors[spender],
            abi.encodeCall(IERC20.transferFrom, (actors[owner], actors[to], amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], balance, amount)
        );
    }

    function transferToZero(uint256 owner, uint256 spender, uint256 amount, bool delegated) external {
        owner %= 3;
        spender %= 3;
        amount = bound(amount, 0, expectedBalances[owner]);
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            _approve(owner, spender, amount + 1);
            _expectFailure(
                actors[spender], abi.encodeCall(IERC20.transferFrom, (actors[owner], address(0), amount)), error
            );
        } else {
            _expectFailure(actors[owner], abi.encodeCall(IERC20.transfer, (address(0), amount)), error);
        }
    }

    function approveZeroSpender(uint256 owner, uint256 amount) external {
        owner %= 3;
        _expectFailure(
            actors[owner],
            abi.encodeCall(IERC20.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function revokeAndAttemptSpend(uint256 owner, uint256 spender, uint256 to) external {
        owner %= 3;
        spender %= 3;
        to %= 3;
        _approve(owner, spender, 0);
        _expectFailure(
            actors[spender],
            abi.encodeCall(IERC20.transferFrom, (actors[owner], actors[to], 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], 0, 1)
        );
    }

    /// @dev Any holder can move its entire balance and receive it back without a fee.
    /// This also drives empty and refilled accounts between arbitrary prior operations.
    function roundTripEntireBalance(uint256 from, uint256 to) external {
        from %= 3;
        to = (from + 1 + to % 2) % 3;
        uint256 amount = expectedBalances[from];
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        assertEq(token.balanceOf(actors[from]), 0);
        assertEq(token.balanceOf(actors[to]), expectedBalances[to] + amount);
        vm.prank(actors[to]);
        assertTrue(token.transfer(actors[from], amount));
        assertEq(token.balanceOf(actors[from]), amount);
        assertEq(token.balanceOf(actors[to]), expectedBalances[to]);
    }

    function _approve(uint256 owner, uint256 spender, uint256 amount) private {
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowances[owner][spender] = amount;
    }

    function _expectFailure(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected failure reason");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IdentityUnitsInvariantTest is Test {
    TokenHandler private handler;
    IdentityUnits private token;

    function setUp() public {
        handler = new TokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.transferOverBalance.selector;
        selectors[4] = TokenHandler.transferFromOverAllowance.selector;
        selectors[5] = TokenHandler.transferFromOverBalance.selector;
        selectors[6] = TokenHandler.transferToZero.selector;
        selectors[7] = TokenHandler.approveZeroSpender.selector;
        selectors[8] = TokenHandler.revokeAndAttemptSpend.selector;
        selectors[9] = TokenHandler.roundTripEntireBalance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ExactBalancesAllowancesAndFixedSupply() public view {
        uint256 sum;
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalances(i));
            assertEq(token.allowance(actor, address(0)), 0);
            sum += balance;
            for (uint256 j; j < 3; ++j) {
                assertEq(token.allowance(actor, handler.actors(j)), handler.expectedAllowances(i, j));
            }
        }
        assertEq(sum, 1_000_000_000 * 1e18);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "Identity Units");
        assertEq(token.symbol(), "UI");
        assertEq(token.decimals(), 18);
    }
}
