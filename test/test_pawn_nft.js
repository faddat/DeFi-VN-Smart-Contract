const DFY_NFT = artifacts.require('DFY_Physical_NFTs');
const Evaluation = artifacts.require('AssetEvaluation');
const Pawn_NFT = artifacts.require('PawnNFTContract');
const DFY_Token = artifacts.require('Defi');
const { assert } = require('chai');
const BigNumber = require('bignumber.js');



require('chai').use(require('chai-as-promised')).should();

contract('Pawn_NFT', (accounts) => {

    const admin = accounts[0];
    const evaluator = accounts[1];
    const customer = accounts[2];
    const lender = accounts[3];

    let NFT_Contract;
    let Eva_Contract;
    let PawnNFT_Contract;
    let DFY_Token_Contract;


    let NFT_Contract_Address;
    let Eva_Contract_Address;
    let Pawn_NFT_Address;
    let DFY_Token_Address;


    before('setup', async ()=> {

        DFY_Token_Contract = await DFY_Token.new({from: admin});

        DFY_Token_Address =  await DFY_Token_Contract.address;

        const total =  await DFY_Token_Contract.totalSupply();


        console.log(total);

        NFT_Contract = await DFY_NFT.deployed();

        NFT_Contract_Address = await NFT_Contract.address;

        assert.notEqual(NFT_Contract_Address, 0x0);
        assert.notEqual(NFT_Contract_Address, '');
        assert.notEqual(NFT_Contract_Address, null);
        assert.notEqual(NFT_Contract_Address, undefined);

        Eva_Contract = await Evaluation.deployed();

        Eva_Contract_Address = await Eva_Contract.address;

        assert.notEqual(Eva_Contract_Address, 0x0);
        assert.notEqual(Eva_Contract_Address, '');
        assert.notEqual(Eva_Contract_Address, null);
        assert.notEqual(Eva_Contract_Address, undefined);


        PawnNFT_Contract = await Pawn_NFT.deployed();

        Pawn_NFT_Address = await PawnNFT_Contract.address;

        assert.notEqual(Pawn_NFT_Address, 0x0);
        assert.notEqual(Pawn_NFT_Address, '');
        assert.notEqual(Pawn_NFT_Address, null);
        assert.notEqual(Pawn_NFT_Address, undefined);
    });

    describe('Config', async()=>{

        // Transfer token
        it('transfer', async() => {
        await DFY_Token_Contract.transfer(evaluator, BigNumber(5000000*Math.pow(10,18)), {from: admin});

        })
        it('Initializer_nft', async()=>{

            const name = await NFT_Contract.name();

            console.log(name);
            
            const init_NFT = await NFT_Contract.initialize("DFY_Physical_NFTs", "DFYNFT", "https://ipfs.io/ipfs", {from: admin});
            
            await PawnNFT_Contract.initialize(100000, {from: admin});
        })

        it('Initializer_EVA', async()=>{
            const init_Eva = await Eva_Contract.initialize("https://ipfs.io/ipfs", NFT_Contract_Address, DFY_Token_Address, {from: admin});

        })


        it('Set_Evaluation_Contract', async()=>{
           const result = await NFT_Contract.setEvaluationContract(Eva_Contract_Address, {from: admin});
        });

        it('Config_Pawn_NFT', async()=>{
            await PawnNFT_Contract.setFeeWallet(admin, {from: admin});
            await PawnNFT_Contract.setOperator(admin, {from: admin});
            await PawnNFT_Contract.setLateThreshold(3, {from: admin});
            await PawnNFT_Contract.setPenaltyRate(15000000, {from: admin});
            await PawnNFT_Contract.setPrepaidFeeRate(300000, {from: admin});
            await PawnNFT_Contract.setSystemFeeRate(2000000, {from: admin});
            await PawnNFT_Contract.setWhitelistCollateral(NFT_Contract_Address, 1, {from: admin});
        });
    })

    describe('Test', async() =>{

        // Add evaluator
        it('add_evaluator', async()=>{
            const result = await Eva_Contract.addEvaluator(evaluator, {from: admin});
        })

        // Create asset request
        it('asset_create_request',async()=>{
            const result = await Eva_Contract.createAssetRequest('CID_ASSET', {from: customer});

            const totalAssets  = await Eva_Contract.totalAssets();

            console.log("-->: ",totalAssets);
        })

        // Evaluation Asset
        it('evaluation_asset',async()=>{
            const result = await Eva_Contract.evaluateAsset(0,DFY_Token_Address,1000,"CID_EVALUATION",10, {from: evaluator});
        })

        // Accept evaluation
        it('accept_evaluation',async()=>{
            const result = await Eva_Contract.acceptEvaluation(0,0, {from: customer});
        })

        // Approve DFY
        it('approve_token_dfy', async()=>{
            const result = await DFY_Token_Contract.approve(Eva_Contract_Address, 100000000, {from: evaluator});
        })

        // Create NFT
        it('create_nft',async()=>{
            const result = await Eva_Contract.createNftToken(0,0,100000000,"CID_NFT" ,{from: evaluator});
            console.log(result);
        })

        // Approve NFT
        it('approve_nft',async()=>{
            const result = await NFT_Contract.setApprovalForAll(Pawn_NFT_Address,true,{from: customer});
        })

        // Create collateral
        it('create_collateral', async()=>{
            const result = await PawnNFT_Contract.createCollateral(NFT_Contract_Address
                ,0
                , 1000
                ,DFY_Token_Address
                ,1
                ,10
                ,0
                ,123456789
                ,{from: customer});
        })

        // Send Offer
        it('create_offer', async()=>{
            const result = await PawnNFT_Contract.createOffer(
                0,
                DFY_Token_Address,
                70,
                1000,
                15,
                10,
                80,
                0,
                0,
                123456789,
                {from: lender});
        })

    })
})
