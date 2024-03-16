// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./ISwapRouter.sol";

interface ISwapRouter02 is ISwapRouter {
    /// @notice Does a transferFrom then swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function swapExactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);

    /// @notice Does a transferFrom then swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function swapExactOutputSingle(ExactOutputSingleParams calldata params) external returns (uint256 amountOut);
}
