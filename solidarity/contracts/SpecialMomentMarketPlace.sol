// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import { ERC1155TokenReceiver } from "./ERC1155.sol";
import { SpecialMoment } from "./SpecialMoment.sol";

contract SpecialMomentMarketPlace is SpecialMoment {
    uint256 newestSaleId;
    uint commissionPercent = 1;
    address payable commissionAccount;

    struct MomentSale {
        uint256 saleId;
        uint price; // in wei
        uint256 tokenId;
        address seller;
        uint quantity;
    }

    constructor() SpecialMoment() {
        commissionAccount = msg.sender;
    }

    event Received(address account, uint256 amount);

    mapping(address => MomentSale[]) userSales;

    function setCommissionAccount(address payable _account) external {
        require(contract_owner == msg.sender);

        commissionAccount = _account;
    }

    function setCommissionRate(uint _rate) external {
        require(contract_owner == msg.sender);
        require(_rate < 15); // rate will never be above 15 perecent, that's just too high...

        commissionPercent = _rate;
    }

    function sell(address _from, uint256 _tokenId, uint _quantity, uint _price) external {
        assertTokenExists(_tokenId);
        require(isOperatorFor(_from, msg.sender));

        // transferToken checks quantities, not ownership
        transferToken(_from, address(this), _tokenId, _quantity);
        newestSaleId++;

        MomentSale memory newSale = MomentSale(newestSaleId, _price, _tokenId, _from, _quantity);

        userSales[_from].push(newSale);
    }

    function getSale(address _seller, uint _saleId) private view returns (MomentSale memory) {
        MomentSale[] memory sales = userSales[_seller];

        for (uint i = 0; i < sales.length; i++) {
            if (sales[i].saleId == _saleId) return sales[i];
        }

        revert();
    }

    function getSaleData(address _seller, uint _saleId) external view returns (
        string memory uri,
        uint256 tokenId,
        uint price, // wei
        address seller,
        uint quantity
    ) {
        MomentSale memory sale = getSale(_seller, _saleId);
        uri = tokens[sale.tokenId].uri;
        tokenId = sale.tokenId;
        price = sale.price;
        quantity = sale.quantity;
        seller = sale.seller;
    }

    function getCommission(uint _value) internal view returns(uint commission, uint remaining) {
        commission = (commissionPercent * _value) / 100;
        remaining = _value - commission;
    }

    function purchase(address payable _seller, uint256 _saleId) external payable {
        MomentSale memory sale = getSale(_seller, _saleId);
        require(msg.value == sale.price, "Transaction value does not equal the price");

        (uint commission, uint value) = getCommission(sale.price);
        _seller.transfer(value);
        if (commissionPercent > 0) commissionAccount.transfer(commission);

        transferToken(address(this), msg.sender, sale.tokenId, sale.quantity);
    }
}