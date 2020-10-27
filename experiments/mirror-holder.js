const fs = require("fs");
const readline = require("readline");
const Web3 = require("web3");
const compiledContract = require("../../build/contracts/BEP20.json");
const BigNumber = require("bignumber.js");

const ERC20_ADDRESS = "0x4728a6790ba272448094c94ee11e203b79a5e012";
const BEP20_ADDRESS = "0x8358DDB0C5679Dab194299aE0136e236e0FAE776";
const MINTER_PRIVATE_KEY =
  "0x8e3b6c8580509740b5bf5161367289d2f83f09a443e24f429a31ef29b17d0933";

const holders = [];

const readAddress = async () => {
  const fileStream = fs.createReadStream("holder.txt");

  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  for await (const line of rl) {
    holders.push({ address: line });
  }

  fileStream.destroy();

  await getBalances();
};

const getBalances = async () => {
  const web3Ether = new Web3(
    new Web3.providers.HttpProvider(
      "https://mainnet.infura.io/v3/acac19c3f59543c8899ec6ddd562b7ae"
    )
  );
  const erc20Contract = new web3Ether.eth.Contract(
    compiledContract.abi,
    ERC20_ADDRESS
  );
  const erc20Decimal = await erc20Contract.methods.decimals().call();

  const web3BSC = new Web3("https://data-seed-prebsc-1-s1.binance.org:8545");
  const bep20Contract = new web3BSC.eth.Contract(
    compiledContract.abi,
    BEP20_ADDRESS
  );
  const bep20Decimal = await bep20Contract.methods.decimals().call();

  let index = 0;
  while (index < holders.length) {
    await Promise.all(
      holders.slice(index, index + 50).map(async holder => {
        holder.erc20Balance = await erc20Contract.methods
          .balanceOf(holder.address)
          .call();
      }),
      holders.slice(index, index + 50).map(async holder => {
        holder.bep20Balance = await bep20Contract.methods
          .balanceOf(holder.address)
          .call();
      })
    );

    index += 50;
  }

  console.log("holder length", holders.length);
  await mintBalances(erc20Decimal, bep20Decimal, holders);
};

const mintBalances = async (erc20Decimal, bep20Decimal, holders) => {
  const web3 = new Web3("https://data-seed-prebsc-1-s1.binance.org:8545");

  const bep20Contract = new web3.eth.Contract(
    compiledContract.abi,
    BEP20_ADDRESS
  );

  let index = 0;
  while (index < holders.length) {
    const addressesMint = [];
    const balanceMint = [];

    const targetHolderIndex = Math.min(holders.length, index + 100);
    for (
      let indexHolder = index;
      indexHolder < targetHolderIndex;
      indexHolder++
    ) {
      const holderCorrespondBalance = new BigNumber(
        holders[indexHolder].erc20Balance
      )
        .multipliedBy(10 ** bep20Decimal)
        .dividedBy(10 ** erc20Decimal)
        .minus(holders[indexHolder].bep20Balance)
        .integerValue();

      if (holderCorrespondBalance > 0) {
        addressesMint.push(holders[indexHolder].address);
        balanceMint.push(holderCorrespondBalance);
      }
    }

    if (addressesMint.length) {
      const method = bep20Contract.methods.mintBatch(
        addressesMint,
        balanceMint
      );
      const txData = method.encodeABI();
      const gasPrice = await web3.eth.getGasPrice();
      let tx = {
        to: BEP20_ADDRESS,
        value: 0,
        gas: 4000000,
        gasPrice: gasPrice,
        data: txData
      };

      await new Promise((resolve, reject) => {
        web3.eth.accounts
          .signTransaction(tx, MINTER_PRIVATE_KEY)
          .then(signed => {
            web3.eth
              .sendSignedTransaction(signed.rawTransaction)
              .on("receipt", receipt => {
                console.log(
                  "Finish minting",
                  addressesMint.length,
                  "addresses"
                );
                console.log("META RECEIPT", receipt.transactionHash);
                resolve();
              })
              .on("error", err => {
                console.log("ERROR ========>>>>> ", err);
                reject(err);
              });
          });
      });
    }

    index += 100;
  }
};

readAddress();
