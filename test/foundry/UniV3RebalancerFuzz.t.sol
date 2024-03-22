// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "./fixtures/TestBed.sol";
import "../../contracts/UniV3Rebalancer.sol";

contract UniV3RebalanerFuzz is TestBed {
    

    UniV3Rebalancer rebalancer;

    function setUp() public {
        initSetup();
        rebalancer = new UniV3Rebalancer(address(uniFactory), address(weth));
    }

    function testStates() public {
        assertGt(weth.balanceOf(address(wethUsdcPool)), 100 * 1e18);
        assertGt(usdc.balanceOf(address(wethUsdcPool)), 300000 * 1e6);
        assertGt(weth.balanceOf(address(wethUsdtPool)), 887 * 1e18);
        assertGt(usdt.balanceOf(address(wethUsdtPool)), 2600000 * 1e6);
    }

    function testSingleHopRebalance(uint256 delta, bool isToken0, bool isBuy) public {
        // Token0 WETH, Token1 USDC
        // Limit
        //   WETH -> [1000 gWei, 10 WETH]
        //   USDC -> [1 USDC, 30k USDC]
        delta = isToken0 ? bound(delta, 1e12, 1e19) : bound(delta, 1e6, 30_000e6);
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);

        int256[] memory deltas = new int256[](2);
        if (isToken0) {
            deltas[0] = isBuy ? int256(delta) : -int256(delta);
        } else {
            deltas[1] = isBuy ? int256(delta) : -int256(delta);
        }

        uint256[] memory amountsLimit = new uint256[](2);
        if (isToken0) {
            amountsLimit[1] = isBuy ? type(uint256).max : 0;
        } else {
            amountsLimit[0] = isBuy ? type(uint256).max : 0;
        }

        weth.mint(address(rebalancer), 20);
        usdc.mint(address(rebalancer), 50_000);

        UniV3Rebalancer.RebalanceData memory data = UniV3Rebalancer.RebalanceData({
            tokens: tokens,
            deltas: deltas,
            amountsLimit: amountsLimit,
            poolFee: poolFee1,
            sqrtPriceLimit: 0,
            deadline: type(uint256).max,
            tokenId: 100,
            path: ""
        });

        // Reverts
        {
            uint128[] memory amounts = new uint128[](2);
            vm.expectRevert("UniV3Rebalancer: Invalid deposit");
            rebalancer.externalCall(vm.addr(1), amounts, 1000, abi.encode(data));

            amounts[0] = 20e18 + 1;
            vm.expectRevert("UniV3Rebalancer: Invalid token amount");
            rebalancer.externalCall(vm.addr(1), amounts, 0, abi.encode(data));

            UniV3Rebalancer.RebalanceData memory tempData = UniV3Rebalancer.RebalanceData({
                tokens: tokens,
                deltas: new int256[](2),
                amountsLimit: amountsLimit,
                poolFee: poolFee1,
                sqrtPriceLimit: 0,
                deadline: type(uint256).max,
                tokenId: 100,
                path: ""
            });
            vm.expectRevert("UniV3Rebalancer: Invalid deltas");
            rebalancer.externalCall(vm.addr(1), new uint128[](2), 0, abi.encode(tempData));
        }

        // Pass
        {
            uint128[] memory amounts = new uint128[](2);
            amounts[0] = 20e18;
            amounts[1] = 50_000e6;

            (address tokenIn, address tokenOut) = deltas[0] < 0 || deltas[1] > 0 ? (address(weth), address(usdc)) : (address(usdc), address(weth));
            (uint256 amountIn, uint256 amountOut) = isBuy ? (uint256(0), delta) : (delta, uint256(0));
            SingleSwapEventParams memory params = SingleSwapEventParams({
                sender: vm.addr(1),
                caller: address(this),
                tokenId: 100,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                poolFee: poolFee1,
                amountIn: amountIn,
                amountOut: amountOut,
                isBuy: isBuy
            });
            params = _quoteSingleSwap(params);

            vm.expectEmit();
            emit ExternalRebalanceSingleSwap(params.sender, params.caller, params.tokenId, params.tokenIn, params.tokenOut, params.poolFee, params.amountIn, params.amountOut, params.isBuy);
            rebalancer.externalCall(vm.addr(1), amounts, 0, abi.encode(data));
        }

        assertGt(weth.balanceOf(address(this)), 0);
        assertGt(usdc.balanceOf(address(this)), 0);
        if (isToken0 && isBuy) {
            assertGt(weth.balanceOf(address(this)), delta);
        } else if (!isToken0 && isBuy) {
            assertGt(usdc.balanceOf(address(this)), delta);
        }
    }

    function testMultiHopRebalance(uint256 delta, bool isToken0, bool isBuy) public {
        // Token0 USDC, Token1 USDT
        // Limit
        //   USDC -> [1 USDC, 1k USDC]
        //   USDT -> [1 USDT, 1k USDT]
        delta = bound(delta, 10e6, 1_000e6);
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);

        bytes memory pathUsdcToUsdt = abi.encodePacked(address(usdc), poolFee1, address(weth), poolFee2, address(usdt));
        bytes memory pathUsdtToUsdc = abi.encodePacked(address(usdt), poolFee2, address(weth), poolFee1, address(usdc));

        int256[] memory deltas = new int256[](2);
        if (isToken0) {
            deltas[0] = isBuy ? int256(delta) : -int256(delta);
        } else {
            deltas[1] = isBuy ? int256(delta) : -int256(delta);
        }
        bytes memory path = deltas[0] > 0 || deltas[1] < 0 ? pathUsdtToUsdc : pathUsdcToUsdt;

        {
            deltas[0] > 0 || deltas[1] < 0 ? console.log("USDT -> USDC") : console.log("USDC -> USDT");
        }

        uint256[] memory amountsLimit = new uint256[](2);
        if (isToken0) {
            amountsLimit[1] = isBuy ? type(uint256).max : 0;
        } else {
            amountsLimit[0] = isBuy ? type(uint256).max : 0;
        }

        UniV3Rebalancer.RebalanceData memory data = UniV3Rebalancer.RebalanceData({
            tokens: tokens,
            deltas: deltas,
            amountsLimit: amountsLimit,
            poolFee: 0,
            sqrtPriceLimit: 0,
            deadline: type(uint256).max,
            tokenId: 100,
            path: path
        });
        usdc.mint(address(rebalancer), 10_000);
        usdt.mint(address(rebalancer), 10_000);

        uint128[] memory amounts = new uint128[](2);
        amounts[0] = 10_000e6;
        amounts[1] = 10_000e6;

        // Avoid stack-too-deep
        {
            (address tokenIn, address tokenOut) = deltas[0] > 0 || deltas[1] < 0 ? (address(usdt),  address(usdc)) : (address(usdc),  address(usdt));
            (uint256 amountIn, uint256 amountOut) = isBuy ? (uint256(0), delta) : (delta, uint256(0));
            MultihopSwapEventParams memory params = MultihopSwapEventParams({
                sender: vm.addr(1),
                caller: address(this),
                tokenId: 100,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                amountOut: amountOut,
                isBuy: isBuy
            });
            params = _quoteSwap(params, path);

            vm.expectEmit();
            emit ExternalRebalanceSwap(params.sender, params.caller, params.tokenId, params.tokenIn, params.tokenOut, params.amountIn, params.amountOut, params.isBuy);
            rebalancer.externalCall(vm.addr(1), amounts, 0, abi.encode(data));
        }

        assertGt(usdc.balanceOf(address(this)), 0);
        assertGt(usdt.balanceOf(address(this)), 0);
        if (isToken0 && isBuy) {
            assertGt(usdc.balanceOf(address(this)), delta);
        } else if (!isToken0 && isBuy) {
            assertGt(usdt.balanceOf(address(this)), delta);
        }
    }

    function _quoteSingleSwap(SingleSwapEventParams memory params) internal returns (SingleSwapEventParams memory) {
        if (params.isBuy) {
            IQuoterV2.QuoteExactOutputSingleParams memory outputParams = IQuoterV2.QuoteExactOutputSingleParams({
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amount: params.amountOut,
                fee: params.poolFee,
                sqrtPriceLimitX96: 0
            });
            (uint256 amountIn,,,) = quoter.quoteExactOutputSingle(outputParams);
            params.amountIn = amountIn;
        } else {
            IQuoterV2.QuoteExactInputSingleParams memory inputParams = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountIn: params.amountIn,
                fee: params.poolFee,
                sqrtPriceLimitX96: 0
            });
            (uint256 amountOut,,,) = quoter.quoteExactInputSingle(inputParams);
            params.amountOut = amountOut;
        }
        return params;
    }

    function _quoteSwap(MultihopSwapEventParams memory params, bytes memory path) internal returns (MultihopSwapEventParams memory) {
        if (params.isBuy) {
            (uint256 amountIn,,,) = quoter.quoteExactOutput(path, params.amountOut);
            params.amountIn = amountIn;
        } else {
            (uint256 amountOut,,,) = quoter.quoteExactInput(path, params.amountIn);
            params.amountOut = amountOut;
        }
        return params;
    }
}