const web3 = require('web3');
const init_holders = [
  {
     address: '0x37B8516a0F88E65D677229b402ec6C1e0E333004',
     balance: web3.utils.toBN('500000000000000000000').toString('hex') // 500e18
  },
  {
     address: '0x6c468CF8c9879006E22EC4029696E005C2319C9D',
     balance: web3.utils.toBN('500000000000000000000').toString('hex') // 500e18
  },
  {
     address: '0x04d63aBCd2b9b1baa327f2Dda0f873F197ccd186',
     balance: web3.utils.toBN('500000000000000000000000000').toString('hex') // 500000000e18
  },{
     address: '0xbcdd0d2cda5f6423e57b6a4dcd75decbe31aecf0',
     balance: web3.utils.toBN('500000000000000000000000000').toString('hex') // 500000000e18
  },{
     address: '0xbbd1acc20bd8304309d31d8fd235210d0efc049d',
     balance: web3.utils.toBN('500000000000000000000000000').toString('hex') // 500000000e18
  },{
     address: '0x5e2a531a825d8b61bcc305a35a7433e9a8920f0f',
     balance: web3.utils.toBN('500000000000000000000000000').toString('hex') // 500000000e18
  },
];

exports = module.exports = init_holders;