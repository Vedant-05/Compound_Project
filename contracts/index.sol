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

    // Borrow from compound

    function borrowERC20(
        address _token,
        address _ctoken,
        uint256 amount
    ) external {
        Comptroller comptroller = Comptroller(comptroller_address);
        PriceFeed priceFeed = PriceFeed(pricefeed_address);
        CErc20 ctoken = CErc20(_ctoken);
        IERC20 token = IERC20(_token);
        uint256 price = priceFeed.getUnderlyingPrice(_ctoken);
        address[] memory cTokens = new address[](1);
        cTokens[0] = _token;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0, "Comptroller.enterMarkets failed.");

        (uint256 error2, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));
        require(error2 == 0, "Comptroller.getAccountLiquidity failed.");
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        uint256 maxBorrow = (liquidity * (10**18)) / price;
        require(maxBorrow > amount, "Can't borrow this much!");

        require(ctoken.borrow(amount) == 0, "borrow failed!");
        token.transfer(msg.sender, amount);
    }

    function borrowEth(
        address _cEtherAddress,
        address _cTokenAddress,
        uint256 amount
    ) public payable {
        Comptroller comptroller = Comptroller(comptroller_address);
        PriceFeed priceFeed = PriceFeed(pricefeed_address);

        CEth cEth = CEth(_cEtherAddress);

        uint256 price = priceFeed.getUnderlyingPrice(_cTokenAddress);

        address[] memory cTokens = new address[](1);
        cTokens[0] = _cTokenAddress;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0, "Comptroller.enterMarkets failed.");

        (uint256 error2, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));

        require(error2 == 0, "Comptroller.getAccountLiquidity failed.");
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        uint256 maxBorrow = (liquidity * (10**18)) / price;
        require(maxBorrow > amount, "Can't borrow this much!");

        require(cEth.borrow(amount) == 0, "borrow failed");
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to borrow Ether");
    }

    // Repay Borrow to compound

    function paybackBorrowERC20(
        address _ctoken,
        address _token,
        uint256 amount
    ) external {
        CErc20 ctoken = CErc20(_ctoken);
        IERC20 token = IERC20(_token);

        token.transferFrom(msg.sender, address(this), amount);
        token.approve(_ctoken, amount);
        require(ctoken.repayBorrow(amount) == 0, "repay borrow failed!");
    }

    function paybackborrowEth(address _ctoken) external payable {
        CEth cEth = CEth(_ctoken);
        cEth.repayBorrow{value: msg.value}();
    }
}
