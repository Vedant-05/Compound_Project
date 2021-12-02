//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.3;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/compound.sol";

contract Compound_middleware {
    // ether

    address comptroller_address = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address pricefeed_address = 0x922018674c12a7F0D394ebEEf9B58F186CdE13c1;
    uint256 ctoken_balance = 0;

    // supply to compound

    // ERC20
    function supplyERC20(
        uint256 amount,
        address _ctoken,
        address _token
    ) external {
        CErc20 ctoken = CErc20(_ctoken);
        IERC20 token = IERC20(_token);
        token.transferFrom(msg.sender, address(this), amount);
        token.approve(_ctoken, amount);

        uint256 before_ctoken_balance = ctoken.balanceOf(address(this));
        require(ctoken.mint(amount) == 0, "mint failed");
        uint256 after_ctoken_balance = ctoken.balanceOf(address(this));
        ctoken_balance = after_ctoken_balance - before_ctoken_balance;
    }

    // ETH
    function supplyeth(address _ctoken) external payable {
        CEth cEth = CEth(_ctoken);
        cEth.mint{value: msg.value}();
    }

    // withdraw asset from compound

    function withdrawERC20(
        address _ctoken,
        address _token,
        uint256 ctoken_amount
    ) external {
        CErc20 ctoken = CErc20(_ctoken);
        IERC20 token = IERC20(_token);

        require(ctoken_balance >= ctoken_amount, "choose lower _amount value");
        require(ctoken.approve(_ctoken, ctoken_amount), "Approve Failed");
        require(ctoken.redeem(ctoken_amount) == 0, "redeem failed");
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function withdrawEth(address _ctoken, uint256 ctoken_amount) external {
        CEth ctoken = CEth(_ctoken);
        require(ctoken.approve(_ctoken, ctoken_amount), "Approve Failed");
        require(ctoken.redeem(ctoken_amount) == 0, "redeem failed");

        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    // borrow and payback //

    // enter market and borrow Erc20
    function borrowErc20(
        address _tokenToBorrow,
        address _cTokenToBorrow,
        uint256 _decimals,
        uint256 _amount,
        address[] memory cTokens
    ) external {
        // enter market
        // enter the supply market so you can borrow another type of asset
        uint256[] memory errors = Comptroller.enterMarkets(cTokens);
        for (uint256 i = 0; i < errors.length; i++) {
            require(errors[i] == 0, "Comptroller.enterMarkets failed.");
        }

        // check liquidity
        (uint256 error, uint256 liquidity, uint256 shortfall) = Comptroller
            .getAccountLiquidity(address(this));
        require(error == 0, "error");
        require(shortfall == 0, "shortfall > 0");
        require(liquidity > 0, "liquidity = 0");

        CErc20 cToken = CErc20(_cTokenToBorrow);
        IERC20Upgradeable token = IERC20Upgradeable(_tokenToBorrow);

        // calculate max borrow
        uint256 price = priceFeed.getUnderlyingPrice(_cTokenToBorrow);
        // liquidity - USD scaled up by 1e18
        // price - USD scaled up by 1e18
        // decimals - decimals of token to borrow
        uint256 maxBorrow = (liquidity * (10**_decimals)) / price;

        require(maxBorrow > _amount, "Can't borrow this much!");
        require(cToken.borrow(_amount) == 0, "borrow failed");

        token.safeTransfer(msg.sender, _amount);
    }

    // enter market and borrow Ether
    function borrowEth(
        address _cTokenToBorrow,
        uint256 _decimals,
        uint256 _amount,
        address[] memory cTokens
    ) external payable {
        // enter market
        // enter the supply market so you can borrow another type of asset
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        for (uint256 i = 0; i < errors.length; i++) {
            require(errors[i] == 0, "Comptroller.enterMarkets failed.");
        }

        // check liquidity
        (uint256 error, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));
        require(error == 0, "error");
        require(shortfall == 0, "shortfall > 0");
        require(liquidity > 0, "liquidity = 0");

        CEth cToken = CEth(_cTokenToBorrow);

        // calculate max borrow
        uint256 price = priceFeed.getUnderlyingPrice(_cTokenToBorrow);
        // liquidity - USD scaled up by 1e18
        // price - USD scaled up by 1e18
        // decimals - decimals of token to borrow
        uint256 maxBorrow = (liquidity * (10**_decimals)) / price;
        require(maxBorrow > _amount, "Can't borrow this much!");
        require(cToken.borrow(_amount) == 0, "borrow failed");
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to borrow Ether");
    }

    // payback Erc20
    function paybackErc20(
        address _tokenBorrowed,
        address _cTokenBorrowed,
        uint256 _amount
    ) external {
        IERC20Upgradeable token = IERC20Upgradeable(_tokenBorrowed);
        CErc20 cToken = CErc20(_cTokenBorrowed);

        token.safeTransferFrom(msg.sender, address(this), _amount);

        token.safeApprove(_cTokenBorrowed, _amount);

        require(cToken.repayBorrow(_amount) == 0, "repay failed");
    }

    function paybackborrowEth(address _ctoken) external payable {
        CEth cEth = CEth(_ctoken);
        cEth.repayBorrow{value: msg.value}();
    }

    // payback Ether
    function paybackEth(address _cTokenBorrowed) external payable {
        CEth(_cTokenBorrowed).repayBorrow{value: msg.value};
    }
}
