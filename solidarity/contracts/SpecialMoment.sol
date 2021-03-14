// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import { ERC1155, ERC1155TokenReceiver } from "./ERC1155.sol";
import { ERC165 } from "./ERC165.sol";

contract SpecialMoment is ERC1155, ERC165 {
    address internal contract_owner;
    Token[] internal tokens;
    mapping(address => address[]) authorizedUsers;
    bytes4 constant ERC1155_Recieved = 0xbc197c81;
    bytes4 public constant ERC165_SIG = type(ERC165).interfaceId;
    bytes4 public constant ERC1155_SIG = type(ERC1155).interfaceId;
    uint public MINT_CAP; // a mint cap will keep people from issuing their own high-supply subtokens

    struct Token {
        uint256 tokenId;

        string uri;
        uint numMinted;
        address minter;

        mapping(address => uint) numOwned;
    }

    constructor() {
        contract_owner = msg.sender;
        MINT_CAP = 10000;
    }

    event TokensMinted(address indexed _minter, uint256 _id, uint _amount);
    event MintCapAdjusted(address indexed _adjuster, uint _cap);

    /// @notice Retreives all important metadata for a given moment
    ///     this includes the minter, uri, and supply
    function getMoment(uint256 _id) external view returns (
        address minterId,
        string memory tokenUri,
        uint numMinted
    ) {
        assertTokenExists(_id);

        minterId = tokens[_id].minter;
        tokenUri = tokens[_id].uri;
        numMinted = tokens[_id].numMinted;
    }

    /// @notice This adjusts the maximum mint supply allowed.
    ///     this provides the potential to freeze minting as
    ///     well as limit minting. This is strictly limited
    ///     TO ONLY THE CONTRACT OWNER
    function adjustMintCap(uint _cap) external {
        require (msg.sender == contract_owner, "Unauthorized");

        MINT_CAP = _cap;
        emit MintCapAdjusted(msg.sender, _cap);
    }

    /// @notice it is entirely possible that a need will arise to
    ///   migrate URIs to another CRN, if that occurs, this function
    ///   will provide such functionality only to the contract creator.
    function changeUri(string memory _uri, uint256 _id) external {
        require (msg.sender == contract_owner, "Unauthorized");
        assertTokenExists(_id);
        
        tokens[_id].uri = _uri;

        emit URI(_uri, _id);
    }

    /// @notice Mints a moment token and gives all of its supply
    ///     to the minter for distribution. Mint quantity is limited
    ///     strictly by the mint cap. The contract owner has no limits.
    function mintToken(uint256 _numMinted, string calldata _uri) external returns (uint256 newId) {
        require((_numMinted <= MINT_CAP) || (msg.sender == contract_owner), "Supply excedes supply cap");
        newId = tokens.length;

        Token storage newToken = tokens.push();

        newToken.minter = msg.sender;
        newToken.numMinted = _numMinted;
        newToken.tokenId = newId;
        newToken.numOwned[msg.sender] = _numMinted;
        newToken.uri = _uri;

        emit TokensMinted(msg.sender, newId, _numMinted);
    }

    /// @dev this should not be used on an incoming address, as it could
    ///  be included in a smart contract's constructor, resulting in codesize == 0.
    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    /// @notice asserts that a token exists.
    function assertTokenExists(uint256 _tokenId) view internal {
        require(_tokenId < tokens.length, "Invalid token id");
    }

    function isOperatorFor(address _owner, address _operator) view internal returns (bool) {
        if (_operator == _owner) return true;
        address[] memory approved_for_owner = authorizedUsers[_owner];

        for (uint i = 0; i < approved_for_owner.length; i++) {
            if (approved_for_owner[i] == _operator) return true;
        }

        return false;
    }

    /// @notice a helper function for batch/individual transfers of tokens
    /// @dev does not enforce ownership
    function transferToken(address _from, address _to, uint256 _id, uint256 _value) internal {
        assertTokenExists(_id);

        Token storage token = tokens[_id];

        uint256 quantity = token.numOwned[_from]; // if from doesn't own any, this will be 0
        require(quantity >= _value, "Insufficient Balance");

        // start the transfer...
        token.numOwned[_from] = token.numOwned[_from] - _value;
        token.numOwned[_to] = token.numOwned[_to] + _value;
    }

    /**
        @notice Transfers `_value` amount of an `_id` from the `_from` address to the `_to` address specified (with safety call).
        @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
        MUST revert if `_to` is the zero address.
        MUST revert if balance of holder for token `_id` is lower than the `_value` sent.
        MUST revert on any other error.
        MUST emit the `TransferSingle` event to reflect the balance change (see "Safe Transfer Rules" section of the standard).
        After the above conditions are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call `onERC1155Received` on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).
        @param _from    Source address
        @param _to      Target address
        @param _id      ID of the token type
        @param _value   Transfer amount
        @param _data    Additional data with no specified format, MUST be sent unaltered in call to `onERC1155Received` on `_to`
    */
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data) override external {
        require(isOperatorFor(_from, msg.sender)); // owner or authorized
        transferToken(_from, _to, _id, _value);

        if (isContract(_to)) {
            bytes4 retval = ERC1155TokenReceiver(_to).onERC1155Received(msg.sender, _from, _id, _value, _data);
            require(retval == ERC1155_Recieved);
        }

        emit TransferSingle(msg.sender, _from, _to, _id, _value);
    }

    /**
        @notice Transfers `_values` amount(s) of `_ids` from the `_from` address to the `_to` address specified (with safety call).
        @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
        MUST revert if `_to` is the zero address.
        MUST revert if length of `_ids` is not the same as length of `_values`.
        MUST revert if any of the balance(s) of the holder(s) for token(s) in `_ids` is lower than the respective amount(s) in `_values` sent to the recipient.
        MUST revert on any other error.
        MUST emit `TransferSingle` or `TransferBatch` event(s) such that all the balance changes are reflected (see "Safe Transfer Rules" section of the standard).
        Balance changes and events MUST follow the ordering of the arrays (_ids[0]/_values[0] before _ids[1]/_values[1], etc).
        After the above conditions for the transfer(s) in the batch are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call the relevant `ERC1155TokenReceiver` hook(s) on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).
        @param _from    Source address
        @param _to      Target address
        @param _ids     IDs of each token type (order and length must match _values array)
        @param _values  Transfer amounts per token type (order and length must match _ids array)
        @param _data    Additional data with no specified format, MUST be sent unaltered in call to the `ERC1155TokenReceiver` hook(s) on `_to`
    */
    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _values, bytes calldata _data) override external {
        require (_ids.length == _values.length, "Mismatched param lengths");
        require(isOperatorFor(_from, msg.sender)); // owner or authorized

        for (uint i = 0; i < _ids.length; i++) {
            transferToken(_from, _to, _ids[i], _values[i]);
        }

        if (isContract(_to)) {
            bytes4 retval = ERC1155TokenReceiver(_to).onERC1155BatchReceived(msg.sender, _from, _ids, _values, _data);
            require(retval == ERC1155_Recieved);
        }

        emit TransferBatch(msg.sender, _from, _to, _ids, _values);
    }

    /**
        @notice Get the balance of an account's tokens.
        @param _owner  The address of the token holder
        @param _id     ID of the token
        @return        The _owner's balance of the token type requested
     */
    function balanceOf(address _owner, uint256 _id) override external view returns (uint256) {
        assertTokenExists(_id);

        Token storage token = tokens[_id];
        return token.numOwned[_owner];
    }

    /**
        @notice Get the balance of multiple account/token pairs
        @param _owners The addresses of the token holders
        @param _ids    ID of the tokens
        @return        The _owner's balance of the token types requested (i.e. balance for each (owner, id) pair)
     */
    function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids) override external view returns (uint256[] memory) {
        require(_owners.length == _ids.length, "Argument lengths mismatched");

        uint256[] memory balances = new uint256[](_owners.length);
        for (uint i = 0; i < _owners.length; i++) {
            balances[i] = this.balanceOf(_owners[i], _ids[i]);
        }

        return balances;
    }

    /**
        @notice Enable or disable approval for a third party ("operator") to manage all of the caller's tokens.
        @dev MUST emit the ApprovalForAll event on success.
        @param _operator  Address to add to the set of authorized operators
        @param _approved  True if the operator is approved, false to revoke approval
    */
    function setApprovalForAll(address _operator, bool _approved) override external {
        address[] storage approved_for_user = authorizedUsers[msg.sender];
        
        if (_approved) { // add to approvals
            if (!isOperatorFor(msg.sender, _operator)) approved_for_user.push(_operator);
        } else { // remove from approvals
            for (uint i = 0; i < approved_for_user.length; i++) {
                if (approved_for_user[i] == _operator) {
                    delete approved_for_user[i];
                    break;
                }
            }
        }

        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    /**
        @notice Queries the approval status of an operator for a given owner.
        @param _owner     The owner of the tokens
        @param _operator  Address of authorized operator
        @return           True if the operator is approved, false if not
    */
    function isApprovedForAll(address _owner, address _operator) override external view returns (bool) {
        return isOperatorFor(_owner, _operator);
    }

    /// @notice Introspection interface as per ERC-165 (https://github.com/ethereum/EIPs/issues/165).
    ///  Returns true for any standardized interfaces implemented by this contract. We implement
    ///  ERC-165 (obviously!) and ERC-721.
    function supportsInterface(bytes4 _interfaceID) override external pure returns (bool)
    {
        return ((_interfaceID == ERC165_SIG) || (_interfaceID == ERC1155_SIG));
    }

    /// @notice Returns the balance of a given address as two parallel
    ///     arrays containing token ids and quantities owned, respectively.
    /// @return tokenIds a list of the ids owned by the owner
    /// @return quantities a list of the quantities relative to the parallel list's id.
    function balanceOfAddress(address _owner) external view returns(
        uint256[] memory tokenIds,
        uint[] memory quantities
    ) {
        uint256 count = 0;
        // count on first pass
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i].numOwned[_owner] > 0) {
                count++;
            }
        }

        tokenIds = new uint256[](count);
        quantities = new uint256[](count);

        uint256 currentIndex = 0;
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i].numOwned[_owner] > 0) {
                tokenIds[currentIndex] = tokens[i].tokenId;
                quantities[currentIndex] = tokens[i].numOwned[_owner];

                currentIndex++;
            }
        }
    }
}