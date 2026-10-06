// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IdentityUnits} from "../src/IdentityUnits.sol";

/// @dev Models balances and allowances independently across three holders.
contract TokenHandler is Test {
    IdentityUnits public immutable token;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401)];
    uint256[3] public expectedBalances;
    mapping(uint256 owner => mapping(uint256 spender => uint256)) public expectedAllowances;

    constructor() {
        token = new IdentityUnits();
        uint256 third = token.totalSupply() / 3;
        for (uint256 i; i < 3; ++i) {
            expectedBalances[i] = i == 2 ? token.totalSupply() - 2 * third : third;
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
        amount = unlimited ? type(uint256).max : bound(amount, 0, token.totalSupply());
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
}

contract IdentityUnitsInvariantTest is Test {
    TokenHandler private handler;
    IdentityUnits private token;

    function setUp() public {
        handler = new TokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ExactBalancesAllowancesAndFixedSupply() public view {
        uint256 sum;
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalances(i));
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
    }
}
