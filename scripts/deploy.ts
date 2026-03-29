// scripts/deploy.ts
import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying CipherDAO Factory...");

  const Factory = await ethers.getContractFactory("CipherDAOFactory");
  const factory = await Factory.deploy();
  await factory.waitForDeployment();

  console.log("✅ Factory deployed at:", factory.target);

  // Example deployment of one DAO
  const config = {
    name: "CipherDAO Test",
    membershipToken: ethers.ZeroAddress,
    votingPeriodBlocks: 200,
    admin: (await ethers.getSigners())[0].address,
    treasuryEnabled: true,
  };

  const tx = await factory.deployDAO(config);
  const receipt = await tx.wait();

  const event = receipt!.logs.find((log: any) => log.eventName === "DAODeployed");
  const [dao, treasury] = event!.args;

  console.log("✅ DAO Governance deployed at:", dao);
  console.log("✅ DAO Treasury deployed at:", treasury);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});