const IdoDFY = artifacts.require("./IdoDFY.sol")
const DFY = artifacts.require("./DFY.sol")
const ERC20CustomToken = artifacts.require("./ERC20CustomToken.sol")
const Web3 = require('web3')
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'))
const BigNumber = require('bignumber.js');

contract('IdoDFY contract: Setting buying time', function (accounts) {
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

        ETHContract = await ERC20CustomToken.new("Ethereum", "ETH", {from: ownerETH})
        ETHContractAddress = ETHContract.address
        console.log('\t' + ETHContractAddress)

        BTCContact = await ERC20CustomToken.new("Bitcoin", "BTC", {from: ownerBTC})
        BTCContractAddress = BTCContact.address
        console.log('\t' + BTCContractAddress)


    });

    it("buy before start", async () => {
        const nextDayDate = new Date()
        nextDayDate.setDate(nextDayDate.getDate() + 1);
        const nextDayTime = Math.floor(nextDayDate.getTime()/1000)
        const next2DayDate = new Date()
        next2DayDate.setDate(next2DayDate.getDate() + 2);
        const next2DayTime = Math.floor(next2DayDate.getTime()/1000)
        idoDFYContract = await IdoDFY.new(DFYContract.address, 1000, 500000, 10, 750000, 15, nextDayTime, next2DayTime,{ from: owner })
        idoDFYContractAddress = idoDFYContract.address

        await DFYContract.enableTransfer({from: owner})
        await DFYContract.transfer(idoDFYContractAddress, BigNumber(100000000 * Math.pow(10, 18)), {from: owner})
        await idoDFYContract.setPublic(true, { from: owner })

        await idoDFYContract.updateExchangePair( BTCContractAddress, 170000, 1, {from: owner})

        const buyAmount = BigNumber(0.1*Math.pow(10, 18))
        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})
        try {
            await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, ownerBTC, {from: ownerBTC})
        } catch (e) {
            assert.equal(e.message,
                "Returned error: VM Exception while processing transaction: revert IDO time is not started -- Reason given: IDO time is not started.",
                "Buy IDO with BTC fail becase: Buy before IDO start!!"
            )
        }
    })

    it("buy before start", async () => {
        const twoDayBeforeDate = new Date()
        twoDayBeforeDate.setDate(twoDayBeforeDate.getDate() - 1)
        const twoDayBeforeTime = Math.floor(twoDayBeforeDate.getTime()/1000)
        const oneDayBeforeDate = new Date()
        oneDayBeforeDate.setDate(oneDayBeforeDate.getDate() - 1)
        const oneDayBeforeTime = Math.floor(oneDayBeforeDate.getTime()/1000)
        idoDFYContract = await IdoDFY.new(DFYContract.address, 1000, 500000, 10, 750000, 15, twoDayBeforeTime, oneDayBeforeTime,{ from: owner })
        idoDFYContractAddress = idoDFYContract.address

        await DFYContract.enableTransfer({from: owner})
        await DFYContract.transfer(idoDFYContractAddress, BigNumber(100000000 * Math.pow(10, 18)), {from: owner})
        await idoDFYContract.setPublic(true, { from: owner })

        await idoDFYContract.updateExchangePair( BTCContractAddress, 170000, 1, {from: owner})

        const buyAmount = BigNumber(0.1*Math.pow(10, 18))
        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})
        try {
            await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, address0, {from: ownerBTC})
        } catch (e) {
            assert.equal(e.message,
                "Returned error: VM Exception while processing transaction: revert IDO time was end -- Reason given: IDO time was end.",
                "Buy IDO with BTC fail becase: Buy after IDO end!!"
            )
        }
    })
})
