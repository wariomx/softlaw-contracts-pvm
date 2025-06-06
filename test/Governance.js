const { chai, expect } = require("chai");
const { expandTo18Decimals } = require("./shared/utilities");
const { MaxUint256 } = require("ethers");

const INITIAL_SUPPLY = "10000000000000000";
const TEST_AMOUNT = expandTo18Decimals(100);
const LARGE_AMOUNT = expandTo18Decimals(15000); // Exceeds default spender limit
const DEFAULT_SPENDER_LIMIT = expandTo18Decimals(10000);

describe("DAOTreasury", function () {
  let treasury;
  let owner;
  let beneficiary;
  let other;

  beforeEach(async function () {
    const DAOTreasury = await ethers.getContractFactory("DAOTreasury");

    [owner, beneficiary, other] = await ethers.getSigners();

    treasury = await DAOTreasury.deploy(owner.address);
    await treasury.waitForDeployment();

    let value;

    if (
      typeof hre !== "undefined" &&
      hre.network &&
      hre.network.name === "localNode"
    ) {
      value = ethers.parseEther("1000000"); // Local node has higher gas fees
    } else {
      value = ethers.parseEther("1");
    }

    // Send balance to other accounts
    await owner.sendTransaction({
      to: beneficiary.address,
      value: value,
    });

    await owner.sendTransaction({
      to: other.address,
      value: value,
    });
  });

  it("should have correct initial configuration", async () => {
    expect(await treasury.name()).to.eq("SoftLaw Token");
    expect(await treasury.symbol()).to.eq("SLaw");
    expect(await treasury.decimals()).to.eq(18);
    expect(await treasury.owner()).to.eq(owner.address);
    expect(await treasury.getSpenderLimit()).to.eq(DEFAULT_SPENDER_LIMIT);

    // Check initial treasury balance
    const initialBalance = ethers.parseUnits(INITIAL_SUPPLY, 18);
    expect(await treasury.getTreasuryBalance()).to.eq(initialBalance);
    expect(await treasury.totalSupply()).to.eq(initialBalance);
  });

  it("should fail spend with zero amount", async () => {
    await expect(
      treasury.spend(0, beneficiary.address)
    ).to.be.revertedWithCustomError(treasury, "AmountMustBeGreaterThanZero");
  });
});
