const { ethers } = require("hardhat");

async function deploy() {
  [account] = await ethers.getSigners();
  deployerAddress = account.address;
  console.log(`Deploying contracts using ${deployerAddress}`);

  // Deploy ERC20
  console.log("Deploying UniswapV2ERC20...");
  const uniswapV2ERC20 = await ethers.getContractFactory("UniswapV2ERC20");
  const uniswapV2ERC20Instance = await uniswapV2ERC20.deploy();
  await uniswapV2ERC20Instance.waitForDeployment();
  console.log(`ETH deployed to : ${await uniswapV2ERC20Instance.getAddress()}`);

  //Deploy Factory
  console.log("Deploying UniswapV2Factory...");
  const factory = await ethers.getContractFactory("UniswapV2Factory");
  const factoryInstance = await factory.deploy(deployerAddress);
  await factoryInstance.waitForDeployment();
  console.log(`Factory deployed to : ${await factoryInstance.getAddress()}`);

  // Deploy Pair
  console.log("Deploying UniswapV2Pair...");
  const pair = await ethers.getContractFactory("UniswapV2Pair");
  const pairInstance = await pair.deploy();
  await pairInstance.waitForDeployment();
  console.log(`Pair deployed to : ${await pairInstance.getAddress()}`);
}

deploy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
