//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol'; 
import '@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol';

interface IFoundry{
    function wrapMultipleTokens(
        uint256[] calldata _tokenIds,
        address _account,
        uint256[] calldata _amounts
    ) external;

    function unWrapMultipleTokens(
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) external;

    function wrappers(uint256 _tokenId) external view returns(address);
}
interface IBPool is IERC20{
    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        external;
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut) external;
}
interface IShareToken is IERC1155{
     function buyCompleteSets(
        address _market,
        address _account,
        uint256 _amount
    ) external returns (bool);

    function sellCompleteSets(
        address _market,
        address _holder,
        address _recipient,
        uint256 _amount,
        bytes32 _fingerprint
    ) external returns (uint256 _creatorFee, uint256 _reportingFee);

    function lowestBalanceOfMarketOutcomes(address _market, uint256[] memory _outcomes, address _account) external view returns (uint256);
}
interface IERC20Wrapper is IERC20{
    function unWrapTokens(address _account, uint256 _amount) external;
}

//kovan
// _AUGUR:
// 0xbc362B362dF54f77e6786d63652bc82245cF1af4
// _FOUNDRY:
// 0xdD56274465443E6Dd063066a38AABc2ef3FEAd94
// _SHARETOKEN:
// 0xFFaFFda91CF0a333DA64a046B1506213A053B142
// _CASH:
// 0xb6085Abd65E21d205AEaD0b1b9981B8B221fA14E


//mainnet

// _AUGUR:
// 0x23916a8F5C3846e3100e5f587FF14F3098722F5d
// _FOUNDRY:
// 0x87876F172087E2fb5838E655DC6A929dC2Dcf85c
// _SHARETOKEN:
// 0x9e4799ff2023819b1272eee430eadf510eDF85f0
// _CASH:
// 0x6B175474E89094C44Da98b954EedeAC495271d0F


contract Helper is ERC1155Receiver{
    IFoundry immutable public foundry;
    IShareToken immutable public shareToken;
    IERC20 immutable public cash;
    address immutable public augur;

    using SafeMath for uint256;

    constructor(address _augur,IFoundry _foundry,IShareToken _shareToken,IERC20 _cash) public{
        augur = _augur;
        foundry = _foundry;
        shareToken = _shareToken;
        cash = _cash;
        _shareToken.setApprovalForAll(address(_foundry),true);
    }

    //approve  (_mintAmount.mul(_numTicks)).add(_amountOfDAIToAdd) first
    //need to make sure that the mintAmount is greater than the amountOfDAIToAdd
    //The access DAI will be returned to the user
    function mintWrapJoin(
        uint256[] memory _tokenIds,
        uint256[] memory _wrappingAmounts,
        uint256[] memory _getBackTokenIds,
        address _market,
        uint256 _numTicks,
        uint256 _mintAmount,
        uint256 _amountOfDAIToAdd,
        IBPool _pool,
        uint256 _poolAmountOut, 
        uint256[] memory _maxAmountsIn
    ) public {
        //_tokenIds.length == _maxAmountsIn.length - 1 because one of the _maxAmountsIn is for the DAI(cash)
        require(_tokenIds.length == _wrappingAmounts.length && _tokenIds.length == _maxAmountsIn.length - 1,"Invalid inputs");
        require(
            cash.transferFrom(
                msg.sender,
                address(this),
                (_mintAmount.mul(_numTicks)).add(_amountOfDAIToAdd)
            )
        );
        cash.approve(augur, _mintAmount.mul(_numTicks).add(_amountOfDAIToAdd));

        //transfer mintAmount.mul or the minted amount would be the mintamount.div
        shareToken.buyCompleteSets(_market, address(this), _mintAmount);     
        //here we are giving the unwrapped tokens that user does not want to wrap and provide liquidity back to the user
        for (uint256 i = 0; i < _getBackTokenIds.length; i++) {
                shareToken.safeTransferFrom(
                    address(this),
                    msg.sender,
                    _getBackTokenIds[i],
                    _mintAmount,
                    ''
                );
        }
        foundry.wrapMultipleTokens(_tokenIds,address(this),_wrappingAmounts);
        //Tokens are wrapped now
        if(address(_pool) != address(0)){
            //Give permission to spend the tokens so that the pool can pool can pull
            for(uint256 i=0 ; i<_tokenIds.length; i++){
                address erc20WrapperAddress = foundry.wrappers(_tokenIds[i]);
                IERC20(erc20WrapperAddress).approve(address(_pool),uint256(-1));
            }
            cash.approve(address(_pool),_amountOfDAIToAdd);

            _pool.joinPool(_poolAmountOut,_maxAmountsIn);

            //Give the pool tokens to the user
            _pool.transfer(msg.sender,_poolAmountOut);
        }
        //Give back the unused ERC20s back to the user
        for(uint256 i=0;i<_tokenIds.length;i++){
            IERC20 erc20Wrapper = IERC20(foundry.wrappers(_tokenIds[i]));
            uint256 balanceOfERC20Wrapper =erc20Wrapper.balanceOf(address(this));
            if(balanceOfERC20Wrapper != 0){
                erc20Wrapper.transfer(msg.sender,balanceOfERC20Wrapper);
            }
        }
        //transfer DAI if any
        uint256 balanceOfCash = cash.balanceOf(address(this));
        if(balanceOfCash != 0){
                cash.transfer(msg.sender,balanceOfCash);
        }
    }
    //user needs to setArrovalForAll of shareToken to this contract and also aprrove their BPT token to this contract
    //Before doing this
    function exitUnWrapRedeem(IBPool _pool,uint256 _poolAmountIn, uint256[] memory _minAmountsOut,uint256[] memory _tokenIds,address _market,uint256[] memory _outcomes,bytes32 _fingerprint) public{
       require(_tokenIds.length == _minAmountsOut.length - 1,"Invalid inputs");
       require(
            _pool.transferFrom(
                msg.sender,
                address(this),
               _poolAmountIn
            )
        );
        _pool.exitPool(_poolAmountIn,_minAmountsOut);


        //transfer DAI back to the user
        uint256 balanceOfCash = cash.balanceOf(address(this));
        if(balanceOfCash != 0){
                cash.transfer(msg.sender,balanceOfCash);
        }

        //all the unwrapped tokens are given back to the user
        for(uint256 i = 0; i <_tokenIds.length;i++){
            IERC20Wrapper erc20Wrapper = IERC20Wrapper(foundry.wrappers(_tokenIds[i]));
            uint256 balanceOfERC20Wrapper = erc20Wrapper.balanceOf(address(this));
            if(balanceOfERC20Wrapper != 0){
                erc20Wrapper.unWrapTokens(address(this),balanceOfERC20Wrapper);
                shareToken.safeTransferFrom(
                        address(this),
                        msg.sender,
                        _tokenIds[i],
                        balanceOfERC20Wrapper,
                        ''
                );
            }
        }
        //user may have some left over ERC1155s that needs to be displayed in the UI
        uint256 amountOfcompleteShares = shareToken.lowestBalanceOfMarketOutcomes(_market,_outcomes,msg.sender);
        shareToken.sellCompleteSets(_market,msg.sender,msg.sender,amountOfcompleteShares,_fingerprint);

    }
    

  /**
        @dev Handles the receipt of a single ERC1155 token type. This function is
        called at the end of a `safeTransferFrom` after the balance has been updated.
        To accept the transfer, this must return
        `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
        (i.e. 0xf23a6e61, or its own function selector).
        @param operator The address which initiated the transfer (i.e. _msgSender())
        @param from The address which previously owned the token
        @param id The ID of the token being transferred
        @param value The amount of tokens being transferred
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
    */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override pure returns (bytes4) {
        return (
            bytes4(
                keccak256(
                    'onERC1155Received(address,address,uint256,uint256,bytes)'
                )
            )
        );
    }

    /**
        @dev Handles the receipt of a multiple ERC1155 token types. This function
        is called at the end of a `safeBatchTransferFrom` after the balances have
        been updated. To accept the transfer(s), this must return
        `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
        (i.e. 0xbc197c81, or its own function selector).
        @param operator The address which initiated the batch transfer (i.e. _msgSender())
        @param from The address which previously owned the token
        @param ids An array containing ids of each token being transferred (order and length must match values array)
        @param values An array containing amounts of each token being transferred (order and length must match ids array)
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
    */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override pure returns (bytes4) {
        return
            bytes4(
                keccak256(
                    'onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)'
                )
            );
    }
}