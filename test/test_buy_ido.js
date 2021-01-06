const IdoDFY = artifacts.require("./IdoDFY.sol")
const DFY = artifacts.require("./DFY.sol")
const ERC20CustomToken = artifacts.require("./ERC20CustomToken.sol")
const Web3 = require('web3')
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'))
const BigNumber = require('bignumber.js');

contract('IdoDFY contract: Buy IDO', function (accounts) {
    let owner = accounts[0]
    let ownerBTC = accounts[1]
    let ownerETH = accounts[2]
    let DFYContract, DFYContractAddress, idoDFYContract, idoDFYContractAddress
    let ETHContract, ETHContractAddress, BTCContact, BTCContractAddress

    const address0 = "0x0000000000000000000000000000000000000000"
    before("setup", async function () {

        DFYContract = await DFY.new( { from: owner })
        DFYContractAddress=DFYContract.address
        console.log('\t'+DFYContractAddress)

        idoDFYContract = await IdoDFY.new(DFYContract.address,{ from: owner })
        idoDFYContractAddress=idoDFYContract.address
        console.log('\t'+idoDFYContractAddress)

        ETHContract = await ERC20CustomToken.new("Ethereum", "ETH",{ from: ownerETH })
        ETHContractAddress=ETHContract.address
        console.log('\t'+ETHContractAddress)

        BTCContact = await ERC20CustomToken.new("Bitcoin", "BTC",{ from: ownerBTC })
        BTCContractAddress=BTCContact.address
        console.log('\t'+BTCContractAddress)

        await DFYContract.enableTransfer({ from: owner })
        const ownerBalance = await DFYContract.balanceOf(owner, { from: owner })
        console.log(ownerBalance.toString())
        await DFYContract.transfer(idoDFYContractAddress, BigNumber(50000000*Math.pow(10,18)), { from: owner })
    });

    beforeEach(async function () {
    });

    it("setup exchange pair", async () => {
        await idoDFYContract.updateExchangePair( BTCContractAddress, 170000, 1, {from: owner})
        const BTCExchangePair = await idoDFYContract.getExchangePair(BTCContractAddress)
        const expectedBTCResult = {
            tokenAddress: BTCContractAddress,
            input: 1,
            output: 170000,
            status: true
        }
        assert.equal(BTCExchangePair.tokenAddress, expectedBTCResult.tokenAddress, "Add BTC address!")
        assert.equal(BTCExchangePair.input, expectedBTCResult.input, "Add BTC input!")
        assert.equal(BTCExchangePair.output, expectedBTCResult.output, "Add BTC output!")
        assert.equal(BTCExchangePair.status, expectedBTCResult.status, "Add BTC status!")

        await idoDFYContract.updateExchangePair( ETHContractAddress, 2000, 1, {from: owner})
        const ETHExchangePair = await idoDFYContract.getExchangePair(ETHContractAddress)
        const expectedETHResult = {
            tokenAddress: ETHContractAddress,
            input: 1,
            output: 2000,
            status: true
        }
        assert.equal(expectedETHResult.tokenAddress, expectedETHResult.tokenAddress, "Add BTC address!")
        assert.equal(expectedETHResult.input, expectedETHResult.input, "Add BTC input!")
        assert.equal(expectedETHResult.output, expectedETHResult.output, "Add BTC output!")
        assert.equal(expectedETHResult.status, expectedETHResult.status, "Add BTC status!")

    }).timeout(400000000);

    it("Buy IDO using BTC", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})

        const btcDecimal = await BTCContact.decimals()

        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(0.1*Math.pow(10, btcDecimal))
        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})
        await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, address0, {from: ownerBTC})

        const idoBalance = await DFYContract.balanceOf(ownerBTC, { from: ownerBTC })
        assert.equal(BigNumber(17000*Math.pow(10, 18)).isEqualTo(idoBalance), true, "Buy IDO with BTC success!")

    }).timeout(400000000);

    it("Buy IDO using ETH", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})

        const ethDecimal = await ETHContract.decimals()

        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(1*Math.pow(10, ethDecimal))
        await ETHContract.approve(idoDFYContractAddress, buyAmount, {from: ownerETH})
        await idoDFYContract.buyIdo(ETHContractAddress, buyAmount, address0, {from: ownerETH})

        const idoBalance = await DFYContract.balanceOf(ownerETH, { from: ownerETH })
        assert.equal(BigNumber(2000*Math.pow(10, 18)).isEqualTo(idoBalance), true, "Buy IDO with ETH success!")

    }).timeout(400000000);
});
