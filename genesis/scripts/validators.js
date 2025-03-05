const web3 = require('web3')
const RLP = require('rlp');

// Configure
const validators = [
   {
     'consensusAddr': '0xbcdd0d2cda5f6423e57b6a4dcd75decbe31aecf0',
     'feeAddr': '0xbcdd0d2cda5f6423e57b6a4dcd75decbe31aecf0',
     'bscFeeAddr': '0xbcdd0d2cda5f6423e57b6a4dcd75decbe31aecf0',
     'votingPower': 0x000001d1a94a2000,
   },
   {
     'consensusAddr': '0xbbd1acc20bd8304309d31d8fd235210d0efc049d',
     'feeAddr': '0xbbd1acc20bd8304309d31d8fd235210d0efc049d',
     'bscFeeAddr': '0xbbd1acc20bd8304309d31d8fd235210d0efc049d',
     'votingPower': 0x000001d1a94a2000,
   },
   {
     'consensusAddr': '0x5e2a531a825d8b61bcc305a35a7433e9a8920f0f',
     'feeAddr': '0x5e2a531a825d8b61bcc305a35a7433e9a8920f0f',
     'bscFeeAddr': '0x5e2a531a825d8b61bcc305a35a7433e9a8920f0f',
     'votingPower': 0x000001d1a94a2000,
   },
];
const bLSPublicKeys = [
   '0xb3baf71dc234890671fc3292afde45e20ce83cb8cd65c614be9fa29932c34051a75cbc1e25b968cc72142c91a56b521a',
   '0x8f124155128c0f4ff8c2b0803c3390bf672e6d26480af4f9648b8d2214d642a6dc2c25c9a37ccc576766e5838d71f52a',
   '0xa42d8fd0af73dc1c2a0238545985c0dba04fd57bc2f66573c86cfbb9f2a3cd5c10d6ddb6a588500ef80f2f5b56b8a21b',
];

// ======== Do not edit below ========
function generateExtraData(validators) {
  let extraVanity = Buffer.alloc(32);
  let validatorsBytes = extraDataSerialize(validators);
  let extraSeal = Buffer.alloc(65);
  return Buffer.concat([extraVanity,validatorsBytes, extraSeal]);
}

function extraDataSerialize(validators) {
  let n = validators.length;
  let arr = [];
  for (let i = 0; i < n; i++) {
    let validator = validators[i];
    arr.push(Buffer.from(web3.utils.hexToBytes(validator.consensusAddr)));
  }
  return Buffer.concat(arr);
}

function validatorUpdateRlpEncode(validators, bLSPublicKeys) {
  let n = validators.length;
  let vals = [];
  for (let i = 0; i < n; i++) {
    vals.push([
      validators[i].consensusAddr,
      validators[i].bscFeeAddr,
      validators[i].feeAddr,
      validators[i].votingPower,
      bLSPublicKeys[i],
    ]);
  }
  let pkg = [0x00, vals];
  return web3.utils.bytesToHex(RLP.encode(pkg));
}

extraValidatorBytes = generateExtraData(validators);
validatorSetBytes = validatorUpdateRlpEncode(validators, bLSPublicKeys);

exports = module.exports = {
  extraValidatorBytes: extraValidatorBytes,
  validatorSetBytes: validatorSetBytes,
};