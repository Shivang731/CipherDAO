const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying CipherDAO with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  // Deploy Factory
  console.log("\nDeploying CipherDAOFactory...");
  const Factory = await ethers.getContractFactory("CipherDAOFactory");
  const factory = await Factory.deploy();
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("CipherDAOFactory deployed to:", factoryAddress);

  // Deploy a demo DAO via factory
  console.log("\nDeploying demo CipherDAO instance...");
  const tx = await factory.deployDAO(
    "CipherDAO Demo",
    100,   // 100 blocks voting period
    2      // quorum: 2 voters
  );
  const receipt = await tx.wait();

  // Get deployed DAO address from event
  const event = receipt.logs.find(log => {
    try {
      return factory.interface.parseLog(log).name === "DAODeployed";
    } catch {
      return false;
    }
  });
  const parsed = factory.interface.parseLog(event);
  const daoAddress = parsed.args[0];
  console.log("CipherGovernance (demo DAO) deployed to:", daoAddress);

  console.log("\n--- Deployment Summary ---");
  console.log("Network:", (await ethers.provider.getNetwork()).name);
  console.log("CipherDAOFactory:", factoryAddress);
  console.log("Demo CipherGovernance:", daoAddress);
  console.log("Deployer:", deployer.address);
  console.log("\nAdd these to your README contract addresses section.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });