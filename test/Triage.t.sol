// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {AbstractPayer} from "@reactive/src/base/AbstractPayer.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {DemoToken} from "../src/DemoToken.sol";
import {TriageDesk} from "../src/TriageDesk.sol";
import {TriageReactive} from "../src/TriageReactive.sol";
import {TriageScore} from "../src/TriageScore.sol";
import {MockSystem} from "./MockSystem.sol";

contract TriageTest is Test {
    address internal constant SYSTEM_ADDR =
        address(uint160(0x8888888888888888888888888888888888888888));
    address internal constant CALLBACK_PROXY =
        address(uint160(uint256(keccak256("callback-proxy"))));
    uint256 internal constant ORIGIN_CHAIN = 84532;
    uint64 internal constant GAS_LIMIT = 400_000;
    uint256 internal constant LARGE_TRANSFER = 1000 ether;
    uint256 internal constant LARGE_APPROVAL = 10_000 ether;
    uint256 internal constant DUST = 0.001 ether;
    uint256 internal constant TRANSFER_TOPIC =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    uint256 internal constant APPROVAL_TOPIC =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    DemoToken internal token;
    TriageDesk internal desk;
    TriageReactive internal reactive;
    address internal clerk;

    event CaseOpened(
        uint256 indexed caseId,
        uint8 kind,
        address indexed subject,
        address indexed counterparty,
        uint256 amount,
        uint8 score,
        uint256 originChainId,
        address originContract,
        uint256 originTxHash,
        uint256 originBlock
    );
    event VerdictFiled(
        uint256 indexed caseId,
        uint8 severity,
        uint8 action,
        bytes32 policyId,
        bytes32 rationaleHash,
        string rationale
    );
    event AlertRaised(
        uint256 indexed caseId,
        address indexed subject,
        address indexed counterparty,
        uint8 kind,
        uint256 amount,
        uint8 severity,
        string rationale
    );
    event CaseRequested(
        uint8 kind,
        address indexed subject,
        address indexed counterparty,
        uint256 amount,
        uint8 score,
        uint256 originTxHash,
        uint256 originBlock
    );
    event Subscribed(
        uint256 chainId,
        address contractAddress,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3
    );
    event CallbackRequested(uint256 chainId, address recipient, uint64 gasLimit, bytes payload);

    function setUp() public {
        clerk = makeAddr("clerk");
        MockSystem mock = new MockSystem();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        vm.deal(SYSTEM_ADDR, 0);

        token = new DemoToken();

        uint64 nonce = vm.getNonce(address(this));
        address predictedDesk = vm.computeCreateAddress(address(this), nonce);
        address predictedReactive = vm.computeCreateAddress(address(this), nonce + 1);

        desk = new TriageDesk{value: 1 ether}(
            IPayable(payable(CALLBACK_PROXY)), predictedReactive, clerk
        );
        reactive = new TriageReactive{value: 1 ether}(
            ORIGIN_CHAIN,
            address(token),
            predictedDesk,
            GAS_LIMIT,
            LARGE_TRANSFER,
            LARGE_APPROVAL,
            DUST
        );

        assertEq(address(desk), predictedDesk);
        assertEq(address(reactive), predictedReactive);
        assertEq(desk.clerk(), clerk);
        assertEq(address(desk).balance, 1 ether);
        assertEq(address(reactive).balance, 1 ether);
    }

    function test_constructorSubscribesToTransferAndApproval() public {
        token = new DemoToken();
        uint64 nonce = vm.getNonce(address(this));
        address predictedDesk = vm.computeCreateAddress(address(this), nonce);
        address predictedReactive = vm.computeCreateAddress(address(this), nonce + 1);

        desk = new TriageDesk{value: 0.1 ether}(
            IPayable(payable(CALLBACK_PROXY)), predictedReactive, clerk
        );

        vm.expectEmit(false, false, false, true, SYSTEM_ADDR);
        emit Subscribed(
            ORIGIN_CHAIN,
            address(token),
            TRANSFER_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        vm.expectEmit(false, false, false, true, SYSTEM_ADDR);
        emit Subscribed(
            ORIGIN_CHAIN,
            address(token),
            APPROVAL_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );

        reactive = new TriageReactive{value: 0.1 ether}(
            ORIGIN_CHAIN,
            address(token),
            predictedDesk,
            GAS_LIMIT,
            LARGE_TRANSFER,
            LARGE_APPROVAL,
            DUST
        );
        assertEq(address(reactive), predictedReactive);
    }

    function test_constructorRevertsOnInvalidConfig() public {
        vm.expectRevert(TriageReactive.InvalidConfig.selector);
        new TriageReactive(0, address(token), address(desk), GAS_LIMIT, 1, 1, 1);

        vm.expectRevert(TriageReactive.InvalidConfig.selector);
        new TriageReactive(ORIGIN_CHAIN, address(0), address(desk), GAS_LIMIT, 1, 1, 1);

        vm.expectRevert(TriageReactive.InvalidConfig.selector);
        new TriageReactive(ORIGIN_CHAIN, address(token), address(0), GAS_LIMIT, 1, 1, 1);

        vm.expectRevert(TriageReactive.InvalidConfig.selector);
        new TriageReactive(ORIGIN_CHAIN, address(token), address(desk), 0, 1, 1, 1);
    }

    function test_onlySystemCanReact() public {
        IReactive.LogRecord memory log_ = _transferLog(address(1), address(2), 5 ether, 1, 100);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM_ADDR)
        );
        reactive.react(log_);
    }

    function test_mismatchedOriginIsIgnored() public {
        IReactive.LogRecord memory log_ = _transferLog(address(1), address(2), 5 ether, 1, 100);
        log_.chainId = 1;
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
        // No callback, no cases.
        assertEq(desk.caseCount(), 0);
    }

    function test_unknownTopicIsIgnored() public {
        IReactive.LogRecord memory log_ = _transferLog(address(1), address(2), 5 ether, 1, 100);
        log_.topic0 = uint256(keccak256("Nope()"));
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
        assertEq(desk.caseCount(), 0);
    }

    function test_fullLoop_routineTransferOpensCaseAndRecordsVerdict() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        uint256 txHash = uint256(keccak256("tx-routine"));
        uint256 blockNumber = 123;

        _reactAndDeliver(_transferLog(alice, bob, 5 ether, txHash, blockNumber));

        assertEq(desk.caseCount(), 1);
        TriageDesk.Case memory openedCase = _case(1);
        assertTrue(openedCase.opened);
        assertFalse(openedCase.verdictFiled);
        assertEq(openedCase.kind, TriageScore.KIND_TRANSFER);
        assertEq(openedCase.score, 35);
        assertEq(openedCase.subject, alice);
        assertEq(openedCase.counterparty, bob);
        assertEq(openedCase.amount, 5 ether);
        assertEq(openedCase.originChainId, ORIGIN_CHAIN);
        assertEq(openedCase.originContract, address(token));
        assertEq(openedCase.originTxHash, txHash);
        assertEq(openedCase.originBlock, blockNumber);
        assertEq(openedCase.severity, 0);
        assertEq(openedCase.action, 0);

        string memory rationale = "Routine transfer; record only.";
        vm.prank(clerk);
        desk.fileVerdict(1, 35, TriageScore.ACTION_RECORD, keccak256("heuristic-v1"), rationale);

        TriageDesk.Case memory filed = _case(1);
        assertTrue(filed.verdictFiled);
        assertEq(filed.severity, 35);
        assertEq(filed.action, TriageScore.ACTION_RECORD);
        assertEq(filed.policyId, keccak256("heuristic-v1"));
        assertEq(filed.rationaleHash, keccak256(bytes(rationale)));
    }

    function test_fullLoop_unlimitedApprovalEscalates() public {
        address alice = makeAddr("alice");
        address spender = makeAddr("spender");
        uint256 txHash = uint256(keccak256("tx-unlimited"));

        vm.expectEmit(true, true, true, true, address(reactive));
        emit CaseRequested(
            TriageScore.KIND_APPROVAL, alice, spender, type(uint256).max, 90, txHash, 50
        );

        _reactAndDeliver(_approvalLog(alice, spender, type(uint256).max, txHash, 50));

        TriageDesk.Case memory approvalCase = _case(1);
        assertEq(approvalCase.kind, TriageScore.KIND_APPROVAL);
        assertEq(approvalCase.score, 90);

        string memory rationale = "Unlimited approval; escalate.";
        vm.expectEmit(true, true, true, true, address(desk));
        emit VerdictFiled(
            1,
            90,
            TriageScore.ACTION_ESCALATE,
            keccak256("heuristic-v1"),
            keccak256(bytes(rationale)),
            rationale
        );
        vm.expectEmit(true, true, true, true, address(desk));
        emit AlertRaised(
            1, alice, spender, TriageScore.KIND_APPROVAL, type(uint256).max, 90, rationale
        );

        vm.prank(clerk);
        desk.fileVerdict(1, 90, TriageScore.ACTION_ESCALATE, keccak256("heuristic-v1"), rationale);
    }

    function test_largeTransferIsScoredSeventyFive() public {
        _reactAndDeliver(_transferLog(makeAddr("a"), makeAddr("b"), LARGE_TRANSFER, 7, 9));
        assertEq(_case(1).score, 75);
    }

    function test_dustAndMintScores() public {
        _reactAndDeliver(_transferLog(makeAddr("a"), makeAddr("b"), DUST, 1, 1));
        assertEq(_case(1).score, 10);

        _reactAndDeliver(_transferLog(address(0), makeAddr("b"), 100 ether, 2, 2));
        assertEq(_case(2).score, 20);
    }

    function test_openCaseRejectsWrongProxyOrSender() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractPayer.NotAuthorized.selector, address(this), CALLBACK_PROXY
            )
        );
        desk.openCase(
            address(reactive), 0, address(1), address(2), 1, 10, ORIGIN_CHAIN, address(token), 1, 1
        );

        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractCallback.CallbackNotAuthorized.selector, address(0xBEEF), address(reactive)
            )
        );
        desk.openCase(
            address(0xBEEF), 0, address(1), address(2), 1, 10, ORIGIN_CHAIN, address(token), 1, 1
        );
    }

    function test_fileVerdictAccessAndReplay() public {
        _reactAndDeliver(_transferLog(makeAddr("a"), makeAddr("b"), 5 ether, 1, 1));

        vm.expectRevert(TriageDesk.NotClerk.selector);
        desk.fileVerdict(1, 1, 0, bytes32(0), "nope");

        vm.prank(clerk);
        vm.expectRevert(abi.encodeWithSelector(TriageDesk.UnknownCase.selector, 99));
        desk.fileVerdict(99, 1, 0, bytes32(0), "missing");

        vm.prank(clerk);
        vm.expectRevert(abi.encodeWithSelector(TriageDesk.InvalidAction.selector, 9));
        desk.fileVerdict(1, 1, 9, bytes32(0), "bad action");

        vm.prank(clerk);
        desk.fileVerdict(1, 35, TriageScore.ACTION_RECORD, keccak256("p"), "ok");

        vm.prank(clerk);
        vm.expectRevert(abi.encodeWithSelector(TriageDesk.VerdictAlreadyFiled.selector, 1));
        desk.fileVerdict(1, 35, TriageScore.ACTION_RECORD, keccak256("p"), "again");
    }

    function test_ownerCanRotateClerk() public {
        address nextClerk = makeAddr("next");
        desk.setClerk(nextClerk);
        assertEq(desk.clerk(), nextClerk);

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(TriageDesk.NotOwner.selector);
        desk.setClerk(nextClerk);

        vm.expectRevert(TriageDesk.ZeroAddress.selector);
        desk.setClerk(address(0));
    }

    function test_demoTokenMintTransferApprove() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        token.mint(alice, 10 ether);
        assertEq(token.balanceOf(alice), 10 ether);

        vm.prank(alice);
        token.transfer(bob, 3 ether);
        assertEq(token.balanceOf(bob), 3 ether);

        vm.prank(alice);
        token.approve(bob, 2 ether);
        assertEq(token.allowance(alice, bob), 2 ether);

        vm.prank(bob);
        token.transferFrom(alice, bob, 2 ether);
        assertEq(token.balanceOf(alice), 5 ether);

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(DemoToken.NotOwner.selector);
        token.mint(alice, 1);
    }

    function test_injectsReactiveAddressIntoCallbackPayload() public {
        IReactive.LogRecord memory log_ = _transferLog(makeAddr("a"), makeAddr("b"), 5 ether, 42, 7);

        vm.recordLogs();
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
        bytes memory payload = _callbackPayload(vm.getRecordedLogs());

        // Selector (4) + first address word should still be the zero placeholder
        // in the request; the proxy overwrites it before delivery.
        address placeholder;
        assembly {
            placeholder := mload(add(payload, 36))
        }
        assertEq(placeholder, address(0));

        bytes memory delivered = _injectSender(payload, address(reactive));
        address injected;
        assembly {
            injected := mload(add(delivered, 36))
        }
        assertEq(injected, address(reactive));

        vm.prank(CALLBACK_PROXY);
        (bool ok,) = address(desk).call(delivered);
        assertTrue(ok);
        assertEq(desk.caseCount(), 1);
    }

    function test_receiveKeepsContractsFundable() public {
        (bool ok1,) = address(desk).call{value: 0.2 ether}("");
        (bool ok2,) = address(reactive).call{value: 0.3 ether}("");
        assertTrue(ok1 && ok2);
        assertEq(address(desk).balance, 1.2 ether);
        assertEq(address(reactive).balance, 1.3 ether);
    }

    function _case(uint256 id) internal view returns (TriageDesk.Case memory) {
        return desk.getCase(id);
    }

    function _reactAndDeliver(IReactive.LogRecord memory log_) internal {
        vm.recordLogs();
        vm.prank(SYSTEM_ADDR);
        reactive.react(log_);
        bytes memory payload = _callbackPayload(vm.getRecordedLogs());
        bytes memory delivered = _injectSender(payload, address(reactive));
        vm.prank(CALLBACK_PROXY);
        (bool ok, bytes memory err) = address(desk).call(delivered);
        if (!ok) {
            assembly {
                revert(add(err, 32), mload(err))
            }
        }
    }

    function _callbackPayload(Vm.Log[] memory logs) internal pure returns (bytes memory payload) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == SYSTEM_ADDR && logs[i].topics.length > 0
                    && logs[i].topics[0] == MockSystem.CallbackRequested.selector
            ) {
                (,,, payload) = abi.decode(logs[i].data, (uint256, address, uint64, bytes));
                return payload;
            }
        }
        revert("callback not requested");
    }

    function _injectSender(bytes memory payload, address sender)
        internal
        pure
        returns (bytes memory out)
    {
        out = payload;
        require(out.length >= 36, "payload too short");
        assembly {
            mstore(add(out, 36), sender)
        }
    }

    function _transferLog(
        address from,
        address to,
        uint256 amount,
        uint256 txHash,
        uint256 blockNumber
    ) internal view returns (IReactive.LogRecord memory log_) {
        log_.chainId = ORIGIN_CHAIN;
        log_.contractAddress = address(token);
        log_.topic0 = TRANSFER_TOPIC;
        log_.topic1 = uint256(uint160(from));
        log_.topic2 = uint256(uint160(to));
        log_.data = abi.encode(amount);
        log_.blockNumber = blockNumber;
        log_.txHash = txHash;
    }

    function _approvalLog(
        address owner,
        address spender,
        uint256 amount,
        uint256 txHash,
        uint256 blockNumber
    ) internal view returns (IReactive.LogRecord memory log_) {
        log_ = _transferLog(owner, spender, amount, txHash, blockNumber);
        log_.topic0 = APPROVAL_TOPIC;
    }
}
