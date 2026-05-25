// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @dev Provides tracking nonces for addresses. Nonces will only increment.
 * Vendored from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/utils/Nonces.sol
 */
abstract contract Nonces {
  /**
   * @dev The nonce used for an `account` is not the expected current nonce.
   */
  error Nonces_InvalidAccountNonce(address account, uint256 currentNonce);

  mapping(address account => uint256) private noncesMap;

  /**
   * @dev Returns the next unused nonce for an address.
   */
  function nonces(address _owner) public view virtual returns (uint256) {
    return noncesMap[_owner];
  }

  /**
   * @dev Consumes a nonce.
   *
   * Returns the current value and increments nonce.
   */
  function _useNonce(address _owner) internal virtual returns (uint256) {
    // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
    // decremented or reset. This guarantees that the nonce never overflows.
    unchecked {
      // It is important to do x++ and not ++x here.
      return noncesMap[_owner]++;
    }
  }

  /**
   * @dev Same as {_useNonce} but checking that `nonce` is the next valid for `owner`.
   */
  function _useCheckedNonce(address _owner, uint256 _nonce) internal virtual {
    uint256 _current = _useNonce(_owner);
    if (_nonce != _current) {
      revert Nonces_InvalidAccountNonce(_owner, _current);
    }
  }
}
// forgefmt: disable-end
