const IdoDFY = artifacts.require("./IdoDFY.sol")
const DFY = artifacts.require("./DFY.sol")
const ERC20CustomToken = artifacts.require("./ERC20CustomToken.sol")
const Web3 = require('web3')
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'))
const BigNumber = require('bignumber.js');

contract('IdoDFY contract: Buy IDO Max amount', function (accounts) {
    let owner = accounts[0]
    let ownerBTC = accounts[1]
    let ownerETH = accounts[2]
    let DFYContract, DFYContractAddress, idoDFYContract, idoDFYContractAddress
    let ETHContract, ETHContractAddress, BTCContact, BTCContractAddress

    const address0 = "0x0000000000000000000000000000000000000000"
    before("setup", async function () {

        DFYContract = await DFY.new({from: owner})
        DFYContractAddress = DFYContract.address
        console.log('\t' + DFYContractAddress)

        const currentTime = Math.floor(new Date().getTime()/1000)
        const nextDayDate = new Date()
        nextDayDate.setDate(nextDayDate.getDate() + 1);
        const nextDayTime = Math.floor(nextDayDate.getTime()/1000)

        idoDFYContract = await IdoDFY.new(DFYContract.address, 1000, 500000, 10, 750000, 15, currentTime, nextDayTime,{ from: owner })
        idoDFYContractAddress = idoDFYContract.address
        console.log('\t' + idoDFYContractAddress)

        ETHContract = await ERC20CustomToken.new("Ethereum", "ETH", {from: ownerETH})
        ETHContractAddress = ETHContract.address
        console.log('\t' + ETHContractAddress)

        BTCContact = await ERC20CustomToken.new("Bitcoin", "BTC", {from: ownerBTC})
        BTCContractAddress = BTCContact.address
        console.log('\t' + BTCContractAddress)
        await idoDFYContract.setPublic(true, { from: owner })

        await DFYContract.enableTransfer({from: owner})
        await DFYContract.transfer(idoDFYContractAddress, BigNumber(170000000 * Math.pow(10, 18)), {from: owner})
    });

    it("Buy IDO using BTC step 1", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})

        const btcDecimal = await BTCContact.decimals()

        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(Math.pow(10, btcDecimal))
        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})
        await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, address0, {from: ownerBTC})

        const idoBalance = await DFYContract.balanceOf(ownerBTC, { from: ownerBTC })
        assert.equal(BigNumber(170000*Math.pow(10, 18)).isEqualTo(idoBalance), true, "Buy IDO with BTC success!")

    }).timeout(400000000);

    it("Buy IDO using BTC fail because exceed 500k", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})

        const btcDecimal = await BTCContact.decimals()

        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(2*Math.pow(10, btcDecimal))
        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})

        try {
            await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, address0, {from: ownerBTC})
        } catch (e) {
            assert.equal(e.message,
                "Returned error: VM Exception while processing transaction: revert Request DFI amount is exceeded! -- Reason given: Request DFI amount is exceeded!.",
                "Buy IDO with BTC fail becase: Amount is exceeded!!"
            )
        }

    }).timeout(400000000);

    it("Buy IDO using BTC success because not exceed 500k", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})

        const btcDecimal = await BTCContact.decimals()

        await idoDFYContract.setStage(0, { from: owner })

        const buyAmount = BigNumber(1.9*Math.pow(10, btcDecimal))
        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})
        await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, address0, {from: ownerBTC})

        const idoBalance = await DFYContract.balanceOf(ownerBTC, { from: ownerBTC })
        assert.equal(BigNumber(493000*Math.pow(10, 18)).isEqualTo(idoBalance), true, "Buy IDO with BTC success!")

    }).timeout(400000000);

    it("Buy user have more than 750k ref coin", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 250000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})
        await idoDFYContract.setStage(0, { from: owner })

        const btcDecimal = await BTCContact.decimals()
        const buyAmount = BigNumber(2*Math.pow(10, btcDecimal))
        for(let i = 0; i < 10; i++) {
            const accountIndex = i + 4
            await BTCContact.transfer(accounts[accountIndex], buyAmount, {from: ownerBTC})


            await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: accounts[accountIndex]})
            await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, accounts[3], {from: accounts[accountIndex]})
        }

        const idoBalance = await DFYContract.balanceOf(accounts[3], { from: accounts[3] })
        assert.equal(BigNumber(750000*Math.pow(10, 18)).isEqualTo(idoBalance), true, "Buy IDO with BTC success!")

    }).timeout(400000000);

    it("Buy user have more than 10 person", async () => {
        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})
        await idoDFYContract.updateExchangePair(ETHContractAddress, 2000, 1, {from: owner})
        await idoDFYContract.setStage(0, { from: owner })

        const btcDecimal = await BTCContact.decimals()
        const buyAmount = BigNumber(Math.pow(10, btcDecimal))
        for(let i = 0; i < 12; i++) {
            const accountIndex = i + 15
            await BTCContact.transfer(accounts[accountIndex], buyAmount, {from: ownerBTC})


            await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: accounts[accountIndex]})
            await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, accounts[14], {from: accounts[accountIndex]})

        }

        const idoBalance = await DFYContract.balanceOf(accounts[14], { from: accounts[14] })
        assert.equal(BigNumber(255000*Math.pow(10, 18)).isEqualTo(idoBalance), true, "Buy IDO with BTC success!")

    }).timeout(400000000);


})
