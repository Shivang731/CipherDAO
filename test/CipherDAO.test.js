const { expect } = require("chai");
const { ethers } = require("hardhat");

// NOTE: These tests use the Fhenix CoFHE mock environment via cofhe-hardhat-plugin.
// Run with: npx hardhat test --network localfhenix

describe("CipherDAOFactory", function () {
  let factory;
  let owner, alice, bob, carol;

  beforeEach(async function () {
    [owner, alice, bob, carol] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("CipherDAOFactory");
    factory = await Factory.deploy();
    await factory.waitForDeployment();
  });

  it("deploys successfully", async function () {
    expect(await factory.totalDAOs()).to.equal(0);
  });

  it("deploys a new DAO", async function () {
    const tx = await factory.deployDAO("TestDAO", 100, 2);
    const receipt = await tx.wait();
    expect(await factory.totalDAOs()).to.equal(1);
  });

  it("emits DAODeployed event with correct data", async function () {
    await expect(factory.deployDAO("TestDAO", 100, 2))
      .to.emit(factory, "DAODeployed")
      .withArgs(
        expect.anything(),
        owner.address,
        "TestDAO",
        expect.anything()
      );
  });

  it("tracks DAOs by admin", async function () {
    await factory.deployDAO("DAO1", 100, 2);
    await factory.deployDAO("DAO2", 200, 3);
    const daos = await factory.getDAOsByAdmin(owner.address);
    expect(daos.length).to.equal(2);
  });

  it("marks deployed DAOs as valid", async function () {
    const tx = await factory.deployDAO("TestDAO", 100, 2);
    const receipt = await tx.wait();
    const event = receipt.logs.find(log => {
      try { return factory.interface.parseLog(log).name === "DAODeployed"; }
      catch { return false; }
    });
    const parsed = factory.interface.parseLog(event);
    const daoAddress = parsed.args[0];
    expect(await factory.isValidDAO(daoAddress)).to.be.true;
  });

  it("rejects zero voting period", async function () {
    await expect(factory.deployDAO("TestDAO", 0, 2))
      .to.be.revertedWith("Voting period must be > 0");
  });

  it("rejects zero quorum", async function () {
    await expect(factory.deployDAO("TestDAO", 100, 0))
      .to.be.revertedWith("Quorum must be > 0");
  });
});

describe("CipherGovernance", function () {
  let governance;
  let owner, alice, bob, carol;

  beforeEach(async function () {
    [owner, alice, bob, carol] = await ethers.getSigners();
    const Governance = await ethers.getContractFactory("CipherGovernance");
    governance = await Governance.deploy(
      owner.address,
      "TestDAO",
      100,    // 100 blocks voting period
      2       // quorum: 2 voters minimum
    );
    await governance.waitForDeployment();

    // Add members
    await governance.addMember(alice.address);
    await governance.addMember(bob.address);
    await governance.addMember(carol.address);
  });

  // --- MEMBERSHIP TESTS ---

  it("sets admin correctly on deploy", async function () {
    expect(await governance.admin()).to.equal(owner.address);
  });

  it("admin is automatically a member", async function () {
    expect(await governance.isMember(owner.address)).to.be.true;
  });

  it("admin can add members", async function () {
    expect(await governance.isMember(alice.address)).to.be.true;
  });

  it("admin can remove members", async function () {
    await governance.removeMember(alice.address);
    expect(await governance.isMember(alice.address)).to.be.false;
  });

  it("non-admin cannot add members", async function () {
    await expect(
      governance.connect(alice).addMember(carol.address)
    ).to.be.revertedWith("Only admin");
  });

  // --- PROPOSAL TESTS ---

  it("member can create a proposal", async function () {
    await governance.connect(alice).createProposal();
    expect(await governance.proposalCount()).to.equal(1);
  });

  it("non-member cannot create a proposal", async function () {
    const [,,,, stranger] = await ethers.getSigners();
    await expect(
      governance.connect(stranger).createProposal()
    ).to.be.revertedWith("Not a member");
  });

  it("emits ProposalCreated event", async function () {
    await expect(governance.connect(alice).createProposal())
      .to.emit(governance, "ProposalCreated")
      .withArgs(0, alice.address, expect.anything());
  });

  it("proposal is open after creation", async function () {
    await governance.connect(alice).createProposal();
    expect(await governance.isVotingOpen(0)).to.be.true;
  });

  it("proposal count increments correctly", async function () {
    await governance.connect(alice).createProposal();
    await governance.connect(alice).createProposal();
    expect(await governance.proposalCount()).to.equal(2);
  });

  // --- VOTING TESTS (using mock FHE) ---

  it("member can cast an encrypted vote", async function () {
    await governance.connect(alice).createProposal();

    // In CoFHE mock: encrypt values client-side
    const encChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const encWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);

    await expect(
      governance.connect(alice).castVote(0, encChoice, encWeight)
    ).to.emit(governance, "VoteCast").withArgs(0, alice.address);
  });

  it("hasVoted is true after voting", async function () {
    await governance.connect(alice).createProposal();

    const encChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const encWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);

    await governance.connect(alice).castVote(0, encChoice, encWeight);
    expect(await governance.hasVoted(alice.address, 0)).to.be.true;
  });

  it("member cannot vote twice", async function () {
    await governance.connect(alice).createProposal();

    const encChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const encWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);

    await governance.connect(alice).castVote(0, encChoice, encWeight);

    const encChoice2 = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const encWeight2 = await ethers.provider.send("fhenix_encrypt_uint64", [5]);

    await expect(
      governance.connect(alice).castVote(0, encChoice2, encWeight2)
    ).to.be.revertedWith("Already voted — use revokeAndRevote");
  });

  it("member can revoke and revote before deadline", async function () {
    await governance.connect(alice).createProposal();

    const encChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const encWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);
    await governance.connect(alice).castVote(0, encChoice, encWeight);

    const newChoice = await ethers.provider.send("fhenix_encrypt_uint8", [2]);
    const newWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);

    await expect(
      governance.connect(alice).revokeAndRevote(0, newChoice, newWeight)
    ).to.emit(governance, "VoteRevoked").withArgs(0, alice.address);
  });

  it("cannot revoke without having voted", async function () {
    await governance.connect(alice).createProposal();

    const newChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const newWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);

    await expect(
      governance.connect(alice).revokeAndRevote(0, newChoice, newWeight)
    ).to.be.revertedWith("No vote to revoke");
  });

  // --- TALLY TESTS ---

  it("cannot finalize before deadline", async function () {
    await governance.connect(alice).createProposal();
    await expect(
      governance.finalizeTally(0)
    ).to.be.revertedWith("Voting still open");
  });

  it("cannot finalize without quorum", async function () {
    await governance.connect(alice).createProposal();

    // Only 1 vote but quorum is 2
    const encChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const encWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);
    await governance.connect(alice).castVote(0, encChoice, encWeight);

    // Mine past deadline
    await ethers.provider.send("hardhat_mine", [101]);

    await expect(
      governance.finalizeTally(0)
    ).to.be.revertedWith("Quorum not reached");
  });

  it("full vote lifecycle: create → vote → finalize", async function () {
    await governance.connect(alice).createProposal();

    // Alice votes For
    const aliceChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const aliceWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);
    await governance.connect(alice).castVote(0, aliceChoice, aliceWeight);

    // Bob votes For
    const bobChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const bobWeight = await ethers.provider.send("fhenix_encrypt_uint64", [8]);
    await governance.connect(bob).castVote(0, bobChoice, bobWeight);

    // Mine past deadline
    await ethers.provider.send("hardhat_mine", [101]);

    await expect(governance.finalizeTally(0))
      .to.emit(governance, "ProposalFinalized")
      .withArgs(0, true);

    expect(await governance.proposalPassed(0)).to.be.true;
  });

  it("proposal fails when against votes win", async function () {
    await governance.connect(alice).createProposal();

    // Alice votes Against
    const aliceChoice = await ethers.provider.send("fhenix_encrypt_uint8", [2]);
    const aliceWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);
    await governance.connect(alice).castVote(0, aliceChoice, aliceWeight);

    // Bob votes Against
    const bobChoice = await ethers.provider.send("fhenix_encrypt_uint8", [2]);
    const bobWeight = await ethers.provider.send("fhenix_encrypt_uint64", [8]);
    await governance.connect(bob).castVote(0, bobChoice, bobWeight);

    await ethers.provider.send("hardhat_mine", [101]);
    await governance.finalizeTally(0);

    expect(await governance.proposalPassed(0)).to.be.false;
  });

  it("cannot finalize the same proposal twice", async function () {
    await governance.connect(alice).createProposal();

    const aliceChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const aliceWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);
    await governance.connect(alice).castVote(0, aliceChoice, aliceWeight);

    const bobChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const bobWeight = await ethers.provider.send("fhenix_encrypt_uint64", [8]);
    await governance.connect(bob).castVote(0, bobChoice, bobWeight);

    await ethers.provider.send("hardhat_mine", [101]);
    await governance.finalizeTally(0);

    await expect(governance.finalizeTally(0))
      .to.be.revertedWith("Already finalized");
  });

  // --- AUDITOR ACCESS TESTS ---

  it("admin can grant auditor permit after finalization", async function () {
    await governance.connect(alice).createProposal();

    const aliceChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const aliceWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);
    await governance.connect(alice).castVote(0, aliceChoice, aliceWeight);

    const bobChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const bobWeight = await ethers.provider.send("fhenix_encrypt_uint64", [8]);
    await governance.connect(bob).castVote(0, bobChoice, bobWeight);

    await ethers.provider.send("hardhat_mine", [101]);
    await governance.finalizeTally(0);

    // Should not revert
    await governance.grantAuditorPermit(carol.address, 0);
  });

  it("cannot grant auditor permit before finalization", async function () {
    await governance.connect(alice).createProposal();

    await expect(
      governance.grantAuditorPermit(carol.address, 0)
    ).to.be.revertedWith("Proposal not finalized yet");
  });

  it("non-admin cannot grant auditor permit", async function () {
    await governance.connect(alice).createProposal();

    const aliceChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const aliceWeight = await ethers.provider.send("fhenix_encrypt_uint64", [10]);
    await governance.connect(alice).castVote(0, aliceChoice, aliceWeight);

    const bobChoice = await ethers.provider.send("fhenix_encrypt_uint8", [1]);
    const bobWeight = await ethers.provider.send("fhenix_encrypt_uint64", [8]);
    await governance.connect(bob).castVote(0, bobChoice, bobWeight);

    await ethers.provider.send("hardhat_mine", [101]);
    await governance.finalizeTally(0);

    await expect(
      governance.connect(alice).grantAuditorPermit(carol.address, 0)
    ).to.be.revertedWith("Only admin");
  });
});