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

  it("should mint additional tokens (printBrrrr)", async () => {
    const mintAmount = expandTo18Decimals(1000);
    const initialBalance = await treasury.getTreasuryBalance();

    await expect(treasury.printBrrrr(mintAmount))
      .to.emit(treasury, "TokensMinted")
      .withArgs(await treasury.getAddress(), mintAmount);

    expect(await treasury.getTreasuryBalance()).to.eq(
      initialBalance + mintAmount
    );
  });

  it("should fail to mint with zero amount", async () => {
    await expect(treasury.printBrrrr(0)).to.be.revertedWithCustomError(
      treasury,
      "AmountMustBeGreaterThanZero"
    );
  });

  it("should fail mint from non-owner", async () => {
    const mintAmount = expandTo18Decimals(1000);
    await expect(
      treasury.connect(other).printBrrrr(mintAmount)
    ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
  });

  it("should spend tokens successfully", async () => {
    const initialTreasuryBalance = await treasury.getTreasuryBalance();
    const initialBeneficiaryBalance = await treasury.getAccountBalance(
      beneficiary.address
    );

    await expect(treasury.spend(TEST_AMOUNT, beneficiary.address))
      .to.emit(treasury, "TokensDistributed")
      .withArgs(beneficiary.address, TEST_AMOUNT);

    expect(await treasury.getTreasuryBalance()).to.eq(
      initialTreasuryBalance - TEST_AMOUNT
    );
    expect(await treasury.getAccountBalance(beneficiary.address)).to.eq(
      initialBeneficiaryBalance + TEST_AMOUNT
    );
  });

  it("should fail spend with zero address beneficiary", async () => {
    await expect(
      treasury.spend(TEST_AMOUNT, ethers.ZeroAddress)
    ).to.be.revertedWithCustomError(treasury, "InvalidBeneficiary");
  });

  it("should fail spend with zero amount", async () => {
    await expect(
      treasury.spend(0, beneficiary.address)
    ).to.be.revertedWithCustomError(treasury, "AmountMustBeGreaterThanZero");
  });

  it("should fail spend exceeding spender limit", async () => {
    await expect(
      treasury.spend(LARGE_AMOUNT, beneficiary.address)
    ).to.be.revertedWithCustomError(treasury, "AmountExceedsSpendingLimit");
  });

  it("should fail spend from non-owner", async () => {
    await expect(
      treasury.connect(other).spend(TEST_AMOUNT, beneficiary.address)
    ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
  });

  it("should update spender limit", async () => {
    const newLimit = expandTo18Decimals(20000);

    await expect(treasury.updateSpenderLimit(newLimit))
      .to.emit(treasury, "SpenderLimitUpdated")
      .withArgs(DEFAULT_SPENDER_LIMIT, newLimit);

    expect(await treasury.getSpenderLimit()).to.eq(newLimit);

    // Should now be able to spend the larger amount
    await expect(treasury.spend(LARGE_AMOUNT, beneficiary.address))
      .to.emit(treasury, "TokensDistributed")
      .withArgs(beneficiary.address, LARGE_AMOUNT);
  });

  it("should fail update spender limit from non-owner", async () => {
    const newLimit = expandTo18Decimals(20000);
    await expect(
      treasury.connect(other).updateSpenderLimit(newLimit)
    ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
  });

  it("should check sufficient balance correctly", async () => {
    const treasuryBalance = await treasury.getTreasuryBalance();

    expect(await treasury.hasSufficientBalance(TEST_AMOUNT)).to.be.true;
    expect(await treasury.hasSufficientBalance(treasuryBalance)).to.be.true;

    // Create a larger amount by adding 1 to treasury balance
    const largerAmount = treasuryBalance + 1n;
    expect(await treasury.hasSufficientBalance(largerAmount)).to.be.false;
  });

  it("should perform emergency withdraw", async () => {
    const initialTreasuryBalance = await treasury.getTreasuryBalance();
    const initialBeneficiaryBalance = await treasury.getAccountBalance(
      beneficiary.address
    );

    await expect(treasury.emergencyWithdraw(beneficiary.address))
      .to.emit(treasury, "TokensDistributed")
      .withArgs(beneficiary.address, initialTreasuryBalance);

    expect(await treasury.getTreasuryBalance()).to.eq(0);
    expect(await treasury.getAccountBalance(beneficiary.address)).to.eq(
      initialBeneficiaryBalance + initialTreasuryBalance
    );
  });

  it("should fail emergency withdraw to zero address", async () => {
    await expect(
      treasury.emergencyWithdraw(ethers.ZeroAddress)
    ).to.be.revertedWithCustomError(treasury, "InvalidBeneficiary");
  });

  it("should fail emergency withdraw from non-owner", async () => {
    await expect(
      treasury.connect(other).emergencyWithdraw(beneficiary.address)
    ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
  });

  it("should perform batch spend successfully", async () => {
    const recipients = [beneficiary.address, other.address];
    const amounts = [expandTo18Decimals(100), expandTo18Decimals(200)];
    const totalAmount = amounts[0] + amounts[1];

    const initialTreasuryBalance = await treasury.getTreasuryBalance();
    const initialBeneficiaryBalance = await treasury.getAccountBalance(
      beneficiary.address
    );
    const initialOtherBalance = await treasury.getAccountBalance(other.address);

    await expect(treasury.batchSpend(recipients, amounts))
      .to.emit(treasury, "TokensDistributed")
      .withArgs(beneficiary.address, amounts[0])
      .to.emit(treasury, "TokensDistributed")
      .withArgs(other.address, amounts[1]);

    expect(await treasury.getTreasuryBalance()).to.eq(
      initialTreasuryBalance - totalAmount
    );
    expect(await treasury.getAccountBalance(beneficiary.address)).to.eq(
      initialBeneficiaryBalance + amounts[0]
    );
    expect(await treasury.getAccountBalance(other.address)).to.eq(
      initialOtherBalance + amounts[1]
    );
  });

  it("should fail batch spend with mismatched arrays", async () => {
    const recipients = [beneficiary.address, other.address];
    const amounts = [expandTo18Decimals(100)]; // Different length

    await expect(treasury.batchSpend(recipients, amounts)).to.be.revertedWith(
      "Recipients and amounts length mismatch"
    );
  });

  it("should fail batch spend exceeding spender limit", async () => {
    const recipients = [beneficiary.address, other.address];
    const amounts = [expandTo18Decimals(6000), expandTo18Decimals(5000)]; // Total: 11000 > 10000 limit

    await expect(
      treasury.batchSpend(recipients, amounts)
    ).to.be.revertedWithCustomError(treasury, "AmountExceedsSpendingLimit");
  });

  it("should fail batch spend with zero address recipient", async () => {
    const recipients = [ethers.ZeroAddress, other.address];
    const amounts = [expandTo18Decimals(100), expandTo18Decimals(200)];

    await expect(
      treasury.batchSpend(recipients, amounts)
    ).to.be.revertedWithCustomError(treasury, "InvalidBeneficiary");
  });

  it("should fail batch spend with zero amount", async () => {
    const recipients = [beneficiary.address, other.address];
    const amounts = [0, expandTo18Decimals(200)];

    await expect(
      treasury.batchSpend(recipients, amounts)
    ).to.be.revertedWithCustomError(treasury, "AmountMustBeGreaterThanZero");
  });

  it("should fail batch spend from non-owner", async () => {
    const recipients = [beneficiary.address];
    const amounts = [expandTo18Decimals(100)];

    await expect(
      treasury.connect(other).batchSpend(recipients, amounts)
    ).to.be.revertedWithCustomError(treasury, "OwnableUnauthorizedAccount");
  });

  it("should fail spend when insufficient treasury balance", async () => {
    // First drain most of the treasury
    const treasuryBalance = await treasury.getTreasuryBalance();
    await treasury.emergencyWithdraw(beneficiary.address);

    // Try to spend when treasury is empty
    await expect(
      treasury.spend(TEST_AMOUNT, other.address)
    ).to.be.revertedWithCustomError(treasury, "InsufficientTreasuryBalance");
  });

  it("should handle edge case with maximum spending limit", async () => {
    // Set spender limit to max uint256
    await treasury.updateSpenderLimit(MaxUint256);
    expect(await treasury.getSpenderLimit()).to.eq(MaxUint256);

    // Should still be limited by actual treasury balance
    const treasuryBalance = await treasury.getTreasuryBalance();
    const largerAmount = treasuryBalance + 1n;
    await expect(
      treasury.spend(largerAmount, beneficiary.address)
    ).to.be.revertedWithCustomError(treasury, "InsufficientTreasuryBalance");
  });
});
