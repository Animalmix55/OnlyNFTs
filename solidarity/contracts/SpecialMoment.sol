// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import { ERC721, ERC721Receiver } from "./ERC721.sol";

contract SpecialMomentContract is ERC721 {
    bytes4 constant ERC721_RECEIVED = 0xf0b9e5ba;
    string constant public name = "Special Moment";

    address private contract_owner;
    SpecialMoment[] private special_moments;
    mapping(address => address[]) authorized_users;
    address[] authorized_minters;

    struct SpecialMoment {
        uint256 id;
        string url;
        address owner;
        address approved_address;
        address minter;
    }

    constructor() {
        contract_owner = msg.sender;
    }

    /// @dev This emits when a minter is authorized or deauthorized
    event Authorized(address indexed _minter, bool indexed _authorized);

    /// @dev This emits when a new token is minted
    event Minted(address indexed _owner, uint256 indexed _tokenId);
    
    function mintToken(string calldata url) external {
        require(this.isAuthorizedMinter(msg.sender));

        uint256 _tokenId = special_moments.length;

        SpecialMoment memory newMoment;
        newMoment.minter = msg.sender;
        newMoment.id = _tokenId;
        newMoment.owner = msg.sender;
        newMoment.url = url;

        special_moments.push(newMoment);

        emit Minted(msg.sender, _tokenId);
    }

    function isAuthorizedMinter(address _minter) external view returns(bool) {
        if (_minter == contract_owner) return true;
        address[] memory minters = authorized_minters;

        for (uint i = 0; i < minters.length; i++) {
            if (minters[i] == _minter) return true;
        }

        return false;
    }

    function authorizeMinter(address _minter, bool _authorized) external {
        require(msg.sender == contract_owner, "Not the contract minter, denied.");
        require(_minter != address(0));

        if (_authorized) {
            if (!this.isAuthorizedMinter(_minter)) authorized_minters.push(_minter);
        } else {
            address[] storage minters = authorized_minters;
            for (uint i = 0; i < minters.length; i++) {
                if (minters[i] == _minter) { 
                    delete minters[i];
                    break;
                }
            }
        }

        emit Authorized(_minter, _authorized);
    }

    /// @notice Count all NFTs assigned to an owner
    /// @dev NFTs assigned to the zero address are considered invalid, and this
    ///  function throws for queries about the zero address.
    /// @param _owner An address for whom to query the balance
    /// @return The number of NFTs owned by `_owner`, possibly zero
    function balanceOf(address _owner) override external view returns (uint256) {
        require (_owner != address(0));

        uint256 count = 0;
        for (uint256 i = 0; i < special_moments.length; i++) {
            if (special_moments[i].owner == _owner) count++;
        }

        return count;
    }

    /// @notice Find the owner of an NFT
    /// @dev NFTs assigned to zero address are considered invalid, and queries
    ///  about them do throw.
    /// @param _tokenId The identifier for an NFT
    /// @return The address of the owner of the NFT
    function ownerOf(uint256 _tokenId) override external view returns (address) {
        address owner = special_moments[_tokenId].owner;
        require(owner != address(0));

        return owner;
    }

    /// @dev this should not be used on an incoming address, as it could
    ///  be included in a smart contract's constructor, resulting in codesize == 0.
    function isContract(address addr) private view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    /// @notice asserts that a token exists.
    function assertTokenExists(uint256 _tokenId) view private {
        require(_tokenId < special_moments.length, "Invalid token id");
    }

    /// @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
    ///  TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
    ///  THEY MAY BE PERMANENTLY LOST
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function transferFrom(address _from, address _to, uint256 _tokenId) override external payable {
        require(_to != address(0));
        assertTokenExists(_tokenId);

        SpecialMoment memory moment = special_moments[_tokenId];
        require(moment.owner == _from, "The from address does not own this token.");
        require(canModify(msg.sender, _tokenId), "You do not have access to this token.");

        special_moments[_tokenId].owner = _to;
        special_moments[_tokenId].approved_address = address(0); // remove previous authorized user

        emit Transfer(_from, _to, _tokenId);
    }

        /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT. When transfer is complete, this function
    ///  checks if `_to` is a smart contract (code size > 0). If so, it calls
    ///  `onERC721Received` on `_to` and throws if the return value is not
    ///  `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    /// @param data Additional data with no specified format, sent in call to `_to`
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory data) override external payable {
        this.transferFrom(_from, _to, _tokenId);

        if (isContract(_to)) {
            bytes4 retval = ERC721Receiver(_to).onERC721Received(_from, _tokenId, data);
            require(retval == ERC721_RECEIVED);
        }
    }

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev This works identically to the other function with an extra data parameter,
    ///  except this function just sets data to "".
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) override external payable {
        this.safeTransferFrom(_from, _to, _tokenId, "");
    }

    /// @notice Returns if a given address has rights as an owner or operator on a
    /// specified NFT.
    ///
    /// @dev Does not check to ensure tokenId is a valid location in the array.
    function canModify(address _address, uint256 _tokenId) private view returns(bool) {
        SpecialMoment memory moment = special_moments[_tokenId];

        return (moment.approved_address == _address) || (this.isApprovedForAll(moment.owner, _address));
    }

    /// @notice Change or reaffirm the approved address for an NFT
    /// @dev The zero address indicates there is no approved address.
    ///  Throws unless `msg.sender` is the current NFT owner, or an authorized
    ///  operator of the current owner.
    /// @param _approved The new approved NFT controller
    /// @param _tokenId The NFT to approve
    function approve(address _approved, uint256 _tokenId) override external payable {
        assertTokenExists(_tokenId);
        require(canModify(msg.sender, _tokenId));

        special_moments[_tokenId].approved_address = _approved;

        emit Approval(msg.sender, _approved, _tokenId);
    }
    
    /// @notice Query if an address is an authorized operator for another address
    /// @param _owner The address that owns the NFTs
    /// @param _operator The address that acts on behalf of the owner
    /// @return True if `_operator` is an approved operator for `_owner`, false otherwise
    function isApprovedForAll(address _owner, address _operator) override external view returns (bool) {
        if (_operator == _owner) return true;
        address[] memory approved_for_owner = authorized_users[_owner];

        for (uint i = 0; i < approved_for_owner.length; i++) {
            if (approved_for_owner[i] == _operator) return true;
        }

        return false;
    }

    /// @notice Enable or disable approval for a third party ("operator") to manage
    ///  all of `msg.sender`'s assets
    /// @dev Emits the ApprovalForAll event. The contract MUST allow
    ///  multiple operators per owner.
    /// @param _operator Address to add to the set of authorized operators
    /// @param _approved True if the operator is approved, false to revoke approval
    function setApprovalForAll(address _operator, bool _approved) override external {
        address[] storage approved_for_user = authorized_users[msg.sender];
        
        if (_approved) { // add to approvals
            if (!this.isApprovedForAll(msg.sender, _operator)) approved_for_user.push(_operator);
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

    /// @notice Get the approved address for a single NFT
    /// @dev Throws if `_tokenId` is not a valid NFT.
    /// @param _tokenId The NFT to find the approved address for
    /// @return The approved address for this NFT, or the zero address if there is none
    function getApproved(uint256 _tokenId) override external view returns (address) {
        assertTokenExists(_tokenId);

        return special_moments[_tokenId].approved_address;
    }

    function getCreatorOf(uint256 _tokenId) external view returns (address) {
        assertTokenExists(_tokenId);

        return special_moments[_tokenId].minter;
    }

    function getUriOf(uint256 _tokenId) external view returns (string memory) {
        assertTokenExists(_tokenId);

        return special_moments[_tokenId].url;
    }
}