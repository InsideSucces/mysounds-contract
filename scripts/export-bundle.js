const fs = require('fs');
const path = require('path');

function exportBundle() {
  const deploymentsPath = path.join(__dirname, '..', 'deployments', 'base-8453.json');
  if (!fs.existsSync(deploymentsPath)) {
    console.error('Deployment file not found at:', deploymentsPath);
    process.exit(1);
  }

  const deploymentData = JSON.parse(fs.readFileSync(deploymentsPath, 'utf8'));
  const contracts = deploymentData.contracts;

  const outDir = path.join(__dirname, '..', 'out');
  const bundle = {
    network: deploymentData.network || 'base',
    chainId: deploymentData.chainId || 8453,
    deployer: deploymentData.deployer,
    deployedAtBlock: deploymentData.deployedAtBlock,
    contracts: {}
  };

  for (const [name, address] of Object.entries(contracts)) {
    const artifactPath = path.join(outDir, `${name}.sol`, `${name}.json`);
    let abi = [];
    if (fs.existsSync(artifactPath)) {
      const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
      abi = artifact.abi || [];
    } else {
      console.warn(`Artifact not found for ${name} at ${artifactPath}`);
    }

    bundle.contracts[name] = {
      address,
      abi
    };
  }

  const outputPath = path.join(__dirname, '..', 'deployments', 'contract-bundle.json');
  fs.writeFileSync(outputPath, JSON.stringify(bundle, null, 2));
  console.log(`Contract bundle exported successfully to: ${outputPath}`);
}

exportBundle();
