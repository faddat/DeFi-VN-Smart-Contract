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
    let user3 = accounts[3]
    let user4 = accounts[4]

    const address0 = "0x0000000000000000000000000000000000000000"
    before("setup", async function () {

        DFYContract = await DFY.new( { from: owner })
        DFYContractAddress=DFYContract.address
        console.log('\t'+DFYContractAddress)
        const currentTime = Math.floor(new Date().getTime()/1000)
        const nextDayDate = new Date()
        nextDayDate.setDate(nextDayDate.getDate() + 1);
        const nextDayTime = Math.floor(nextDayDate.getTime()/1000)
        idoDFYContract = await IdoDFY.new(DFYContract.address, 1000, 500000, 10, 750000, 15, currentTime, nextDayTime,{ from: owner })
        idoDFYContractAddress=idoDFYContract.address
        console.log('\t'+idoDFYContractAddress)

        ETHContract = await ERC20CustomToken.new("Ethereum", "ETH",{ from: ownerETH })
        ETHContractAddress=ETHContract.address
        console.log('\t'+ETHContractAddress)

        BTCContact = await ERC20CustomToken.new("Bitcoin", "BTC",{ from: ownerBTC })
        BTCContractAddress=BTCContact.address
        console.log('\t'+BTCContractAddress)

        await DFYContract.enableTransfer({ from: owner })
        await DFYContract.transfer(idoDFYContractAddress, BigNumber(50000000*Math.pow(10,18)), { from: owner })
        await BTCContact.transfer(user3, BigNumber(Math.pow(10,18)), {from: ownerBTC})
        await ETHContract.transfer(user4, BigNumber(2*Math.pow(10,18)), {from: ownerETH})

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

    it("BuyIdo with referal", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})
        const btcDecimal = await BTCContact.decimals()

        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(0.05*Math.pow(10, btcDecimal))
        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: user3})
        await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, ownerBTC, {from: user3})

        const idoBalance = await DFYContract.balanceOf(user3, { from: user3 })
        assert.equal(BigNumber(8500*Math.pow(10, 18)).isEqualTo(idoBalance), true, "Buy IDO with BTC and Ref success!")

        const refBalance = await DFYContract.balanceOf(ownerBTC, { from: user3 })
        assert.equal(BigNumber(18275*Math.pow(10, 18)).isEqualTo(refBalance), true, "Receive Ref success!")

        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: user3})
        await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, ownerBTC, {from: user3})
        const idoBalance2 = await DFYContract.balanceOf(user3, { from: user3 })
        assert.equal(BigNumber(17000*Math.pow(10, 18)).isEqualTo(idoBalance2), true, "Buy IDO with BTC twice success!")

        const refBalance2 = await DFYContract.balanceOf(ownerBTC, { from: user3 })
        assert.equal(BigNumber(18275*Math.pow(10, 18)).isEqualTo(refBalance2), true, "Not receive Ref success!")
    }).timeout(400000000);

    it("BuyIdo with referal itself", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})
        const ethDecimal = await ETHContract.decimals()

        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(2*Math.pow(10, ethDecimal))
        await ETHContract.approve(idoDFYContractAddress, buyAmount, {from: user4})
        await idoDFYContract.buyIdo(ETHContractAddress, buyAmount, user4, {from: user4})

        const idoBalance = await DFYContract.balanceOf(user4, { from: user4 })
        assert.equal(BigNumber(4000*Math.pow(10, 18)).isEqualTo(idoBalance), true, "Buy IDO with ETH and not have Ref success!")
    }).timeout(400000000);

    it("Buy Ido failed because lower than 1000 DFY", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(0.005*Math.pow(10, 18))
        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})

        try {
            await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, address0, {from: ownerBTC})
        } catch (e) {
            assert.equal(e.message,
                "Returned error: VM Exception while processing transaction: revert Amount DFI request is too low -- Reason given: Amount DFI request is too low.",
                "Buy IDO with BTC fail because: Buy too low"
            )
        }
    })

    it("Buy Ido success when buy 1000 DFY", async () => {
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})
        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(0.5*Math.pow(10, 18))
        await ETHContract.approve(idoDFYContractAddress, buyAmount, {from: ownerETH})

        await idoDFYContract.buyIdo(ETHContractAddress, buyAmount, address0, {from: ownerETH})
        const ownerETHBalance = await DFYContract.balanceOf(ownerETH, { from: ownerETH })
        assert.equal(ownerETHBalance.toString(), "3000000000000000000000", "Buy IDO with exact 1000 DFY success")

    })
});
