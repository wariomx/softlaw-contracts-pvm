const { ethers } = require("hardhat");

async function deploy() {
  [account] = await ethers.getSigners();
  deployerAddress = account.address;
  console.log(`Deploying contracts using ${deployerAddress}`);

  const eth = await ethers.getContractFactory("UniswapV2ERC20");
  const ethInstance = await eth.deploy();
  await ethInstance.waitForDeployment();

  console.log(`ETH deployed to : ${ethInstance.address}`);

  //Deploy Factory
  const factory = await ethers.getContractFactory("UniswapV2Factory");
  const factoryInstance = await factory.deploy(deployerAddress);
  await factoryInstance.waitForDeployment();

  console.log(`Factory deployed to : ${factoryInstance.address}`);

  // Deploy Pair
  const pair = await ethers.getContractFactory("UniswapV2Pair");
  const pairInstance = await pair.deploy();
  await pairInstance.waitForDeployment();

  console.log(`Pair deployed to : ${pairInstance.address}`);
}

deploy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
