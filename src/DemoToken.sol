// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Minimal ERC-20 used as the origin event source in the demo.
/// @notice Anyone following the README can mint test units to themselves and
///         emit Transfer / Approval logs that the reactive clerk subscribes to.
contract DemoToken {
    error NotOwner();
    error InsufficientBalance();
    error InsufficientAllowance();

    string public constant name = "Triage Demo";
    string public constant symbol = "TRIAGE";
    uint8 public constant decimals = 18;

    address public immutable owner;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function mint(address to_, uint256 amount_) external onlyOwner {
        totalSupply += amount_;
        balanceOf[to_] += amount_;
        emit Transfer(address(0), to_, amount_);
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    function approve(address spender_, uint256 amount_) external returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        uint256 allowed = allowance[from_][msg.sender];
        if (allowed < amount_) revert InsufficientAllowance();
        if (allowed != type(uint256).max) {
            allowance[from_][msg.sender] = allowed - amount_;
        }
        _transfer(from_, to_, amount_);
        return true;
    }

    function _transfer(address from_, address to_, uint256 amount_) internal {
        if (balanceOf[from_] < amount_) revert InsufficientBalance();
        unchecked {
            balanceOf[from_] -= amount_;
            balanceOf[to_] += amount_;
        }
        emit Transfer(from_, to_, amount_);
    }
}
