const IdoDFY = artifacts.require("./IdoDFY.sol")
const DFY = artifacts.require("./DFY.sol")
const ERC20CustomToken = artifacts.require("./ERC20CustomToken.sol")
const Web3 = require('web3')
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'))
const BigNumber = require('bignumber.js');

contract('IdoDFY contract: Public Ido', function (accounts) {
    let owner = accounts[0]
    let ownerBTC = accounts[1]
    let ownerETH = accounts[2]
    let DFYContract, DFYContractAddress, idoDFYContract, idoDFYContractAddress
    let ETHContract, ETHContractAddress, BTCContact, BTCContractAddress
    const address0 = "0x0000000000000000000000000000000000000000"

    before("setup", async function () {
        BTCContact = await ERC20CustomToken.new("Bitcoin", "BTC",{ from: ownerBTC })
        BTCContractAddress=BTCContact.address
        console.log('\t'+BTCContractAddress)

    });

    it("Cannot buy ido when it not public", async () => {
        DFYContract = await DFY.new({from: owner})
        DFYContractAddress = DFYContract.address

        const currentTime = Math.floor(new Date().getTime()/1000)
        const nextDayDate = new Date()
        nextDayDate.setDate(nextDayDate.getDate() + 1);
        const nextDayTime = Math.floor(nextDayDate.getTime()/1000)
        idoDFYContract = await IdoDFY.new(DFYContract.address, 1000, 500000, 10, 750000, 15, currentTime, nextDayTime,{ from: owner })
        idoDFYContractAddress=idoDFYContract.address

        await DFYContract.enableTransfer({ from: owner })

        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})

        const buyAmount = BigNumber(0.1*Math.pow(10, 18))

        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})
        try {
            await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, address0, {from: ownerBTC})
        } catch (e) {
            assert.equal(e.message, 'Returned error: VM Exception while processing transaction: revert Public sale still not open -- Reason given: Public sale still not open.', 'Buy Ido failed because contract not public')
        }
    });

    it("Can buy ido when it not public but address in white list", async () => {
        DFYContract = await DFY.new({from: owner})
        DFYContractAddress = DFYContract.address

        const currentTime = Math.floor(new Date().getTime()/1000)
        const nextDayDate = new Date()
        nextDayDate.setDate(nextDayDate.getDate() + 1);
        const nextDayTime = Math.floor(nextDayDate.getTime()/1000)
        idoDFYContract = await IdoDFY.new(DFYContract.address, 1000, 500000, 10, 750000, 15, currentTime, nextDayTime,{ from: owner })
        idoDFYContractAddress = idoDFYContract.address
        await DFYContract.transfer(idoDFYContractAddress, BigNumber(50000000*Math.pow(10,18)), { from: owner })

        await DFYContract.enableTransfer({ from: owner })

        await idoDFYContract.updateExchangePair(BTCContractAddress, 170000, 1, {from: owner})

        const buyAmount = BigNumber(0.1*Math.pow(10, 18))

        idoDFYContract.addWhiteList(ownerBTC, {from: owner})

        const balanceBeforeBuying = await DFYContract.balanceOf(ownerBTC, { from: owner })

        await BTCContact.approve(idoDFYContractAddress, buyAmount, {from: ownerBTC})

        await idoDFYContract.buyIdo(BTCContractAddress, buyAmount, address0, {from: ownerBTC})

        const balanceAfterBuying = await DFYContract.balanceOf(ownerBTC, { from: owner })

        assert.equal(
            BigNumber(17000*Math.pow(10, 18)).isEqualTo(BigNumber(balanceAfterBuying).minus(balanceBeforeBuying)),
            true,
            'Buying DFY success'
        )

    });
})
