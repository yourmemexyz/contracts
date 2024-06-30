// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ILP {
	function addLiquidityETH(
		address token,
		bool stable,
		uint256 amountTokenDesired,
		uint256 amountTokenMin,
		uint256 amountETHMin,
		address to,
		uint256 deadline
	) external payable returns (uint256, uint256, uint256);

	function pairFor(
		address tokenA,
		address tokenB,
		bool stable
	) external view returns (address);

	function renounceOwnership() external;
}
