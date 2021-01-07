const IdoDFY = artifacts.require("./IdoDFY.sol")
const DFY = artifacts.require("./DFY.sol")
const Web3 = require('web3')
const BigNumber = require('bignumber.js');
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'))

contract('IdoDFY contract: Setup stage', function (accounts) {
    before("setup ", async function () {

    });

    beforeEach(async function () {

    });
    // console.log(accounts)
    let owner = accounts[0];
    // let A = accounts[1];
    // let B = accounts[2];
    // let C = accounts[3];
    // let D = accounts[4];
    // let E = accounts[5];
    // let F = accounts[6];
    // let G = accounts[7];
    // let H = accounts[8];
    // let I = accounts[9];
    // let J = accounts[10];
    // let K = accounts[11];

    const ethValue = web3.utils.toWei("0.25", "ether");

    it("test call set stage  ", async () => {
        console.log('****************************************************')
        const DFYContracy = await DFY.new( { from: owner })
        const DFYContracyAddress=DFYContracy.address
        console.log('\t'+DFYContracyAddress)

        const idoDFYContracy = await IdoDFY.new(DFYContracy.address, 500000, 10, 750000, 15,{ from: owner })
        const idoDFYContracyAddress=idoDFYContracy.address
        console.log('\t'+idoDFYContracyAddress)

        console.log('\ttransfer 350mil to idoDFY contract')
        await DFYContracy.transfer(idoDFYContracyAddress, 350000000, { from: owner })

        const idoBalance = await DFYContracy.balanceOf(idoDFYContracyAddress, { from: owner })
        assert.equal(idoBalance, 350000000, "idoDFY balance inconrrect")

        console.log('\tsetup stage to unpaused')
        let stage = await idoDFYContracy.stage( { from: owner });
        assert.equal(stage, 1, "idoDFY stage inconrrect")

        await idoDFYContracy.setStage(0, { from: owner })
        stage = await idoDFYContracy.stage( { from: owner });
        assert.equal(stage, 0, "idoDFY stage inconrrect")

    }).timeout(400000000);
});
