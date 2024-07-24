const hre = require('hardhat');
const { getChainId } = hre;

module.exports = async ({ getNamedAccounts, deployments }) => {
    const pyth_addr = process.env.PYTH_SEI
    const id = process.env.PYTH_SEI_USDC_USD_ID

    console.log("running deploy pyth script");
    console.log("network name: ", network.name);
    console.log("network id: ", await getChainId())
    console.log(`PYTH id: ${id}`)

    function sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const args = [
        pyth_addr,
        id
    ]

    const pyth = await deploy('PythAggregatorV3', {
        from: deployer,
        args
    })

    console.log("Pyth deployed to: ", pyth.address)

    await sleep(60000)

    if (await getChainId() !== '31337') {
        await hre.run(`verify:verify`, {
            address: pyth.address,
            constructorArguments: args
        })
    }
};

module.exports.tags = ['Pyth'];
