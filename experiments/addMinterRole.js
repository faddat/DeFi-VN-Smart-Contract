const Web3 = require('web3');
const compiledContract = require('../../build/contracts/BEP20.json');

const contractAddress = "0x8358DDB0C5679Dab194299aE0136e236e0FAE776";
const ownerPrivateKey = '0x8e3b6c8580509740b5bf5161367289d2f83f09a443e24f429a31ef29b17d0933';

let NEW_MINTER_ADDRESS = '0x7DE768B60B1653267B85DA2AA9648CCB0815954E';

addMinterRole(NEW_MINTER_ADDRESS);

async function addMinterRole(newMinterWalletAddress) {
  let web3 = new Web3('https://data-seed-prebsc-1-s1.binance.org:8545');

  let contract = new web3.eth.Contract(compiledContract.abi, contractAddress);
  const method = contract.methods.grantRole(
    web3.utils.soliditySha3("MINTER"),
    newMinterWalletAddress
  );

  let txData = method.encodeABI();

  const gasPrice = await web3.eth.getGasPrice();
  let tx = {
    to: contractAddress,
    value: 0,
    gas: 400000,
    gasPrice: gasPrice,
    data: txData,
  };

  web3.eth.accounts.signTransaction(tx, ownerPrivateKey).then(signed => {
    web3.eth
      .sendSignedTransaction(signed.rawTransaction)
      .on('receipt', receipt => {
        console.log('META RECEIPT', receipt);
      })
      .on('error', err => {
        console.log('ERROR ========>>>>> ', err);
      });
  });
}
