const IdoDFY = artifacts.require("./IdoDFY.sol")
const DFY = artifacts.require("./DFY.sol")
const ERC20CustomToken = artifacts.require("./ERC20CustomToken.sol")
const Web3 = require('web3')
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'))
const BigNumber = require('bignumber.js');

contract('IdoDFY contract: Withdraw token', function (accounts) {
    let owner = accounts[0]
    let ownerBTC = accounts[1]
    let ownerETH = accounts[2]
    let DFYContract, DFYContractAddress, idoDFYContract, idoDFYContractAddress
    let ETHContract, ETHContractAddress, BTCContact, BTCContractAddress

    before("setup", async function () {

    })

    it("withdraw DFY token", async () => {
        DFYContract = await DFY.new({from: owner})
        DFYContractAddress = DFYContract.address

        const currentTime = Math.floor(new Date().getTime()/1000)
        const nextDayDate = new Date()
        nextDayDate.setDate(nextDayDate.getDate() + 1);
        const nextDayTime = Math.floor(nextDayDate.getTime()/1000)
        idoDFYContract = await IdoDFY.new(DFYContract.address, 1000, 500000, 10, 750000, 15, currentTime, nextDayTime,{ from: owner })
        idoDFYContractAddress=idoDFYContract.address

        await DFYContract.enableTransfer({ from: owner })

        await DFYContract.transfer(idoDFYContractAddress, BigNumber(50000000*Math.pow(10,18)), { from: owner })

        const balanceBeforeWithDraw = await DFYContract.balanceOf(owner, { from: owner })
        const withdrawnAmount = "1000000000000000000"
        await idoDFYContract.withdrawnToken(DFYContractAddress, withdrawnAmount, { from: owner })
        const balanceAfterWithDraw = await DFYContract.balanceOf(owner, { from: owner })

        assert.equal(BigNumber(balanceAfterWithDraw).minus(balanceBeforeWithDraw).toString(), withdrawnAmount, 'withdraw DFY success')

    })

    it("withdraw DFY failed when not owner request", async () => {
        DFYContract = await DFY.new({from: owner})
        DFYContractAddress = DFYContract.address

        const currentTime = Math.floor(new Date().getTime()/1000)
        const nextDayDate = new Date()
        nextDayDate.setDate(nextDayDate.getDate() + 1);
        const nextDayTime = Math.floor(nextDayDate.getTime()/1000)
        idoDFYContract = await IdoDFY.new(DFYContract.address, 1000, 500000, 10, 750000, 15, currentTime, nextDayTime,{ from: owner })
        idoDFYContractAddress=idoDFYContract.address

        await DFYContract.enableTransfer({ from: owner })

        await DFYContract.transfer(idoDFYContractAddress, BigNumber(50000000*Math.pow(10,18)), { from: owner })

        try {
            const withdrawnAmount = "1000000000000000000"
            await idoDFYContract.withdrawnToken(DFYContractAddress, withdrawnAmount, { from: ownerBTC })
        } catch (e) {
            assert.equal(
                e.message,
                'Returned error: VM Exception while processing transaction: revert Ownable: caller is not the owner -- Reason given: Ownable: caller is not the owner.',
                'failed because not owner'
            )
        }


    })
})
