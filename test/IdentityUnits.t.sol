// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IdentityUnits} from "../src/IdentityUnits.sol";

contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (IdentityUnits) {
        return new IdentityUnits{salt: salt}();
    }

    function move(IdentityUnits token, address to, uint256 amount) external {
        require(token.transfer(to, amount));
    }
}

contract RejectingReceiver {
    fallback() external {
        revert("no callbacks accepted");
    }
}

contract IdentityUnitsTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    IdentityUnits private token;

    function setUp() public {
        token = new IdentityUnits();
    }

    function test_MetadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "Identity Units");
        assertEq(token.symbol(), "UI");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        new IdentityUnits();
    }

    function test_Create2FactoryReceivesAndCanForwardEntireSupply() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("Identity Units launch");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(IdentityUnits).creationCode)
                        )
                    )
                )
            )
        );
        vm.prank(ALICE);
        IdentityUnits deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
        factory.move(deployed, ALICE, SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(ALICE), SUPPLY);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 123e18);
        assertTrue(token.transfer(ALICE, 123e18));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123e18);
        assertEq(token.balanceOf(ALICE), 123e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FullBalanceTransfer() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferRejectsZeroRecipientIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EmptyAccountCannotTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_ApproveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 40));
        assertEq(token.allowance(address(this), SPENDER), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_ApproveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 100);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromDeliversExactAmountAndSpendsAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 60));
        assertEq(token.allowance(address(this), SPENDER), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60);
        assertEq(token.balanceOf(ALICE), 60);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromCanSpendExactAllowance() public {
        token.approve(SPENDER, SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        token.approve(SPENDER, type(uint256).max);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), SUPPLY - 1);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_DelegatedSelfTransferPreservesBalanceButSpendsAllowance() public {
        token.approve(SPENDER, 100);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 100));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_RevocationPreventsSpending() public {
        token.approve(SPENDER, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_TransferFromRejectsInsufficientAllowanceAtomically() public {
        token.approve(SPENDER, 99);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 99, 100));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 100);
        assertEq(token.allowance(address(this), SPENDER), 99);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_TransferFromInsufficientBalanceRollsBackAllowance() public {
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 11);
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroRecipientRollsBackAllowance() public {
        token.approve(SPENDER, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSourceCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 1);
        // Even a zero-value call cannot use the zero address as a source.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_DeployerCannotSpendHolderBalanceWithoutApproval() public {
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_TransferDoesNotCallRecipient() public {
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 100));
        assertEq(token.balanceOf(address(receiver)), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
    }

    function test_LaunchCustodyRoutesDeliverExactAmounts() public {
        address distributor = address(0xD157);
        address poolCustodian = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY / 2;
        uint256 remainder = SUPPLY - swarm - pool;
        assertTrue(token.transfer(distributor, swarm));
        assertTrue(token.transfer(poolCustodian, pool));
        assertTrue(token.transfer(ALICE, remainder));
        vm.prank(distributor);
        assertTrue(token.transfer(BOB, swarm));
        vm.prank(poolCustodian);
        assertTrue(token.transfer(BOB, 1e18));
        assertEq(token.balanceOf(BOB), swarm + 1e18);
        vm.prank(BOB);
        assertTrue(token.transfer(poolCustodian, 1e18));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(ALICE), remainder);
        assertEq(token.balanceOf(BOB), swarm);
        assertEq(token.balanceOf(poolCustodian), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_CommonMintAndAdminCallsAreUnavailable() public {
        token.transfer(ALICE, 100);
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1);
        calls[4] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[5] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[7] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[8] = abi.encodeWithSignature("pause()");
        calls[9] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[10] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[11] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[12] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 100);
        calls[13] = abi.encodeWithSignature("burn(uint256)", 100);
        calls[14] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(BOB);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_RuntimeHasNoDelegationOrDestructionOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzz_TransfersConserveSupply(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, first);
        assertTrue(token.transfer(ALICE, first));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, second));
        assertEq(token.balanceOf(address(this)), SUPPLY - first);
        assertEq(token.balanceOf(ALICE), first - second);
        assertEq(token.balanceOf(BOB), second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverBalanceTransferRevertsWithoutChangingState(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransfersRespectAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverAllowanceTransferRevertsWithoutChangingState(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        token.approve(SPENDER, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
