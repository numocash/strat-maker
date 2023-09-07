import { startProxy } from "@viem/anvil";
import { forkBlockNumber, forkUrl } from "./constants.js";

export default async function () {
  return await startProxy({
    port: 8545, // By default, the proxy will listen on port 8545.
    host: "::", // By default, the proxy will listen on all interfaces.
    options: {
      chainId: 1,
      forkUrl,
      forkBlockNumber,
      codeSizeLimit: 0x10000,
    },
  });
}