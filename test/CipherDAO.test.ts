// test/CipherDAO.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { FHE } from "@fhenixprotocol/cofhe-contracts";

describe("CipherDAO - Wave 1", function () {
  let factory: any;
  let owner: any;
  let user1: any;
  let user2: any;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("CipherDAOFactory");
    factory = await Factory.deploy();
    await factory.waitForDeployment();
  });

  it("should deploy a new DAO with treasury", async function () {
    const config = {
      name: "Test DAO",
      membershipToken: ethers.ZeroAddress,
      votingPeriodBlocks: 100,
      admin: owner.address,
      treasuryEnabled: true,
    };

    const tx = await factory.deployDAO(config);
    const receipt = await tx.wait();
    const event = receipt.logs.find((log: any) => log.eventName === "DAODeployed");

    expect(event).to.not.be.undefined;
    const [dao, treasury] = event.args;
    expect(dao).to.be.properAddress;
    expect(treasury).to.be.properAddress;
  });

  it("should create proposal and support encrypted voting", async function () {
    const config = { name: "Test", membershipToken: ethers.ZeroAddress, votingPeriodBlocks: 100, admin: owner.address, treasuryEnabled: true };
    const [dao] = await factory.deployDAO(config);
    const gov = await ethers.getContractAt("CipherDAOGovernance", dao);

    const desc = FHE.encrypt(123n);
    await gov.createProposal(desc, 200);

    const choice = FHE.encrypt(1n);
    const weight = FHE.encrypt(100n);
    await gov.connect(user1).castVote(0, choice, weight);

    expect(await gov.hasVoted(0, user1.address)).to.be.true;
  });
});